public with sharing class VisitSurveyLinkController {
  public class PhoneOption {
    @AuraEnabled public String key;
    @AuraEnabled public String label;
    @AuraEnabled public String phone;
    @AuraEnabled public String firstName;
    @AuraEnabled public String accountName;
  }

  public class ProductOption {
    @AuraEnabled public String productId;
    @AuraEnabled public String productName;
  }

  public class WhatsAppSurveyContext {
    @AuraEnabled public List<PhoneOption> phoneOptions;
    @AuraEnabled public List<ProductOption> products;
    @AuraEnabled public String surveyBaseUrl;
  }

  @AuraEnabled(cacheable=true)
  public static WhatsAppSurveyContext getWhatsAppSurveyContext(Id visitId) {
    WhatsAppSurveyContext context = new WhatsAppSurveyContext();
    context.phoneOptions = new List<PhoneOption>();
    context.products = new List<ProductOption>();
    context.surveyBaseUrl = resolveSurveyBaseUrl();

    if (visitId == null) {
      return context;
    }

    List<Visit__c> visits = [
      SELECT
        Id,
        Account__c,
        Account__r.Name,
        Account__r.Phone
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      return context;
    }

    Visit__c visit = visits[0];
    addPhoneOption(
      context.phoneOptions,
      'account-phone',
      visit.Account__r?.Name + ' (Account Phone)',
      visit.Account__r?.Phone,
      visit.Account__r?.Name
    );
    addMobileOption(
      context.phoneOptions,
      'account-mobile',
      visit.Account__r?.Name + ' (Mobile)',
      visit.Account__c,
      visit.Account__r?.Name
    );

    List<Visit_Attendee__c> attendees = [
      SELECT
        Id,
        Account__c,
        Account__r.Name,
        Account__r.Phone
      FROM Visit_Attendee__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
      ORDER BY CreatedDate ASC
    ];
    Integer attendeeOrder = 0;
    for (Visit_Attendee__c attendee : attendees) {
      attendeeOrder++;
      String prefix = attendeeOrder == 1 ? 'Primary: ' : '';
      addPhoneOption(
        context.phoneOptions,
        'attendee-' + attendee.Id + '-phone',
        prefix + attendee.Account__r?.Name + ' (Phone)',
        attendee.Account__r?.Phone,
        attendee.Account__r?.Name
      );
      addMobileOption(
        context.phoneOptions,
        'attendee-' + attendee.Id + '-mobile',
        prefix + attendee.Account__r?.Name + ' (Mobile)',
        attendee.Account__c,
        attendee.Account__r?.Name
      );
    }

    for (VisitCallReportService.TerritoryProductOption product : VisitCallReportService.getTerritoryProducts(
      visitId
    )) {
      ProductOption option = new ProductOption();
      option.productId = product.productId;
      option.productName = product.productName;
      context.products.add(option);
    }

    return context;
  }

  @AuraEnabled
  public static String buildSurveyUrl(Id visitId, String productName) {
    if (visitId == null || String.isBlank(productName)) {
      return null;
    }
    String base = resolveSurveyBaseUrl();
    return base +
      '/productsurvey/ProductSurvey?visitId=' +
      EncodingUtil.urlEncode(String.valueOf(visitId), 'UTF-8') +
      '&product=' +
      EncodingUtil.urlEncode(productName, 'UTF-8');
  }

  @AuraEnabled
  public static String buildWhatsAppMessage(
    String firstName,
    String productName,
    String surveyUrl
  ) {
    String greetingName = String.isNotBlank(firstName) ? firstName : 'there';
    String productLabel = String.isNotBlank(productName) ? productName : 'our product';
    return 'Hello ' +
      greetingName +
      ', It was great meeting you today, please feel free to leave your review about ' +
      productLabel +
      ' on this link: ' +
      surveyUrl;
  }

  @AuraEnabled
  public static String buildMeetingReminderMessage(
    Id visitId,
    String recipientAccountName
  ) {
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }

    List<Visit__c> visits = [
      SELECT Start_Date__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }

    String doctorFirstName = extractDoctorGreetingName(recipientAccountName);
    String meetingTime = formatMeetingTime(visits[0].Start_Date__c);
    String repFirstName = UserInfo.getFirstName();
    if (String.isBlank(repFirstName)) {
      repFirstName = UserInfo.getName();
    }

    return 'Hello Dr. ' +
      doctorFirstName +
      ',\n\n' +
      'Looking forward to meeting you today at ' +
      meetingTime +
      '!\n' +
      'Thank you for your time!\n\n' +
      'Regards,\n' +
      repFirstName;
  }

  private static void addPhoneOption(
    List<PhoneOption> options,
    String key,
    String label,
    String phone,
    String accountName
  ) {
    if (String.isBlank(phone)) {
      return;
    }
    PhoneOption option = new PhoneOption();
    option.key = key;
    option.label = label;
    option.phone = phone;
    option.firstName = extractFirstName(accountName);
    option.accountName = accountName;
    options.add(option);
  }

  private static void addMobileOption(
    List<PhoneOption> options,
    String key,
    String label,
    Id accountId,
    String accountName
  ) {
    if (accountId == null || !hasPersonMobilePhoneField()) {
      return;
    }
    List<Account> accounts = [
      SELECT PersonMobilePhone, IsPersonAccount
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (accounts.isEmpty() || !accounts[0].IsPersonAccount) {
      return;
    }
    addPhoneOption(
      options,
      key,
      label,
      accounts[0].PersonMobilePhone,
      accountName
    );
  }

  private static Boolean hasPersonMobilePhoneField() {
    return Schema.SObjectType.Account.fields.getMap().containsKey('PersonMobilePhone');
  }

  public static String extractFirstName(String accountName) {
    if (String.isBlank(accountName)) {
      return null;
    }
    String trimmed = accountName.trim();
    Integer spaceIndex = trimmed.indexOf(' ');
    return spaceIndex > 0 ? trimmed.substring(0, spaceIndex) : trimmed;
  }

  @TestVisible
  public static String extractDoctorGreetingName(String accountName) {
    if (String.isBlank(accountName)) {
      return 'Doctor';
    }
    String trimmed = accountName.trim();
    String lower = trimmed.toLowerCase();
    if (lower.startsWith('dr. ')) {
      trimmed = trimmed.substring(4).trim();
    } else if (lower.startsWith('dr ')) {
      trimmed = trimmed.substring(3).trim();
    }
    String firstName = extractFirstName(trimmed);
    return String.isNotBlank(firstName) ? firstName : 'Doctor';
  }

  @TestVisible
  private static String formatMeetingTime(DateTime visitStart) {
    if (visitStart == null) {
      return 'the scheduled time';
    }
    return visitStart.format('h:mm a');
  }

  public static String digitsOnlyPhone(String phone) {
    if (String.isBlank(phone)) {
      return null;
    }
    String digits = phone.replaceAll('[^0-9]', '');
    return String.isBlank(digits) ? null : digits;
  }

  private static String resolveSurveyBaseUrl() {
    List<Site> sites = [
      SELECT Id, Subdomain, UrlPathPrefix
      FROM Site
      WHERE UrlPathPrefix = 'productsurvey'
      LIMIT 1
    ];
    if (!sites.isEmpty() && String.isNotBlank(sites[0].Subdomain)) {
      return 'https://' + sites[0].Subdomain + '.force.com';
    }

    List<Domain> siteDomains = [
      SELECT Domain
      FROM Domain
      WHERE DomainType = 'DNS' AND Domain LIKE '%.my.salesforce-sites.com'
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    if (!siteDomains.isEmpty()) {
      return 'https://' + siteDomains[0].Domain;
    }

    return URL.getOrgDomainUrl().toExternalForm();
  }
}