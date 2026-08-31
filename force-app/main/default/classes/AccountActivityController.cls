public with sharing class AccountActivityController {
  private static final Integer DEFAULT_TIMELINE_LIMIT = 50;
  private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount'
  };

  public class SpecialtyRow {
    @AuraEnabled
    public Integer specialtyNumber;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  public class HcpAccountOverview {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String recordTypeName;
    @AuraEnabled
    public Boolean isHcp;
    @AuraEnabled
    public String designation;
    @AuraEnabled
    public String tier;
    @AuraEnabled
    public String licenseNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String postalCode;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public List<SpecialtyRow> specialties;
  }

  public class ProductChip {
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public String imageUrl;
  }

  public class SlideThumbnail {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String thumbnailUrl;
  }

  public class PresentationSummary {
    @AuraEnabled
    public Id sessionId;
    @AuraEnabled
    public String presentationName;
    @AuraEnabled
    public Integer slidesPresented;
    @AuraEnabled
    public Integer slideCount;
    @AuraEnabled
    public String durationLabel;
    @AuraEnabled
    public String slidesLabel;
    @AuraEnabled
    public List<SlideThumbnail> slideThumbnails;
  }

  public class TimelineItem {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public Datetime activityDate;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public List<String> productNames;
    @AuraEnabled
    public List<ProductChip> products;
    @AuraEnabled
    public List<String> detailLines;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public String typeLabel;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String channel;
    @AuraEnabled
    public String dateGroupLabel;
    @AuraEnabled
    public List<PresentationSummary> presentations;
  }

  @AuraEnabled(cacheable=true)
  public static HcpAccountOverview getHcpAccountOverview(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }

    List<String> selectFields = new List<String>{
      'Id',
      'Name',
      'RecordType.Name',
      'RecordType.DeveloperName',
      'BillingStreet',
      'BillingCity',
      'BillingState',
      'BillingPostalCode',
      'BillingCountry',
      'Owner.Name'
    };
    for (String fieldName : new List<String>{
      'Professional_Designation__c',
      'Tier__c',
      'Professional_License_Number__c',
      'Account_Status__c',
      'PersonEmail',
      'PersonMobilePhone',
      'Specialty_1__c',
      'Specialty_2__c',
      'Specialty_3__c',
      'Specialty_4__c'
    }) {
      if (isAccountFieldQueryable(fieldName)) {
        selectFields.add(fieldName);
      }
    }

    String soql =
      'SELECT ' +
      String.join(selectFields, ',') +
      ' FROM Account WHERE Id = :accountId LIMIT 1';
    List<Account> accounts = Database.query(soql);

    if (accounts.isEmpty()) {
      throw new AuraHandledException('Account not found.');
    }

    Account acct = accounts[0];
    HcpAccountOverview overview = new HcpAccountOverview();
    overview.accountId = acct.Id;
    overview.name = acct.Name;
    overview.recordTypeName = acct.RecordType?.Name;
    overview.isHcp = HCP_RECORD_TYPES.contains(acct.RecordType?.DeveloperName);
    overview.designation = (String) safeGet(acct, 'Professional_Designation__c');
    overview.tier = (String) safeGet(acct, 'Tier__c');
    overview.licenseNumber = (String) safeGet(acct, 'Professional_License_Number__c');
    overview.status = (String) safeGet(acct, 'Account_Status__c');
    overview.email = (String) safeGet(acct, 'PersonEmail');
    overview.phone = (String) safeGet(acct, 'PersonMobilePhone');
    overview.street = acct.BillingStreet;
    overview.city = acct.BillingCity;
    overview.state = acct.BillingState;
    overview.postalCode = acct.BillingPostalCode;
    overview.country = acct.BillingCountry;
    overview.ownerName = acct.Owner?.Name;
    overview.specialties = buildSpecialtyRows(acct);
    return overview;
  }

  @AuraEnabled
  public static AccountActivityInsightsTypes.AccountVisitInsights getAccountVisitInsights(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }

    AccountActivityInsightsTypes.AccountVisitInsights base =
      AccountActivityInsightsAggregator.build(accountId);
    AccountActivityEinsteinClient.GenerationResult einstein =
      AccountActivityEinsteinClient.tryEnhance(accountId, base);
    if (einstein.success && einstein.insights != null) {
      return einstein.insights;
    }
    base.source = AccountActivityInsightsTypes.SOURCE_STRUCTURED;
    return base;
  }

  @AuraEnabled(cacheable=true)
  public static List<TimelineItem> getAccountActivityTimeline(Id accountId, Integer recordLimit) {
    if (accountId == null) {
      return new List<TimelineItem>();
    }

    Integer resolvedLimit = recordLimit == null || recordLimit < 1
      ? DEFAULT_TIMELINE_LIMIT
      : Math.min(recordLimit, 100);

    List<TimelineItem> items = new List<TimelineItem>();
    items.addAll(buildVisitTimelineItems(accountId));
    items.addAll(buildPresentationTimelineItems(accountId));
    items.addAll(buildSampleTimelineItems(accountId));
    items.addAll(buildEmailTimelineItems(accountId));

    items.sort(new TimelineItemComparator());

    for (TimelineItem item : items) {
      item.dateGroupLabel = buildDateGroupLabel(item.activityDate);
    }

    if (items.size() > resolvedLimit) {
      List<TimelineItem> trimmed = new List<TimelineItem>();
      for (Integer i = 0; i < resolvedLimit; i++) {
        trimmed.add(items[i]);
      }
      return trimmed;
    }
    return items;
  }

  private static List<SpecialtyRow> buildSpecialtyRows(Account acct) {
    List<SpecialtyRow> rows = new List<SpecialtyRow>();
    rows.add(buildSpecialtyRow(1, 'Specialty 1', (String) safeGet(acct, 'Specialty_1__c')));
    rows.add(buildSpecialtyRow(2, 'Specialty 2', (String) safeGet(acct, 'Specialty_2__c')));
    rows.add(buildSpecialtyRow(3, 'Specialty 3', (String) safeGet(acct, 'Specialty_3__c')));
    rows.add(buildSpecialtyRow(4, 'Specialty 4', (String) safeGet(acct, 'Specialty_4__c')));
    return rows;
  }

  private static Boolean isAccountFieldQueryable(String fieldName) {
    Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
    if (!fieldMap.containsKey(fieldName)) {
      return false;
    }
    Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
    return describe.isAccessible();
  }

  private static Object safeGet(Account acct, String fieldName) {
    if (acct == null || String.isBlank(fieldName)) {
      return null;
    }
    try {
      return acct.get(fieldName);
    } catch (Exception ex) {
      return null;
    }
  }

  private static SpecialtyRow buildSpecialtyRow(Integer specialtyNumber, String label, String value) {
    SpecialtyRow row = new SpecialtyRow();
    row.specialtyNumber = specialtyNumber;
    row.label = label;
    row.value = String.isNotBlank(value)
      ? MedicalSpecialtyPicklist.getLabel(value)
      : '—';
    return row;
  }

  private static List<TimelineItem> buildVisitTimelineItems(Id accountId) {
    List<TimelineItem> items = new List<TimelineItem>();

    Account account = getAccountForTimeline(accountId);
    String accountName = account?.Name;
    String formattedAddress = formatAccountAddress(account);

    List<Visit__c> visits = [
      SELECT
        Id,
        Name,
        Status__c,
        Visit_Type__c,
        Start_Date__c,
        Visit_Objective__c,
        Visit_Notes__c,
        Products_Discussed__c,
        Assigned_To__r.Name
      FROM Visit__c
      WHERE Account__c = :accountId
      WITH USER_MODE
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 100
    ];

    if (visits.isEmpty()) {
      return items;
    }

    Set<Id> visitIds = new Set<Id>();
    for (Visit__c visit : visits) {
      visitIds.add(visit.Id);
    }

    Map<Id, List<ProductChip>> productsByVisit = getProductsByVisit(visitIds);
    Map<Id, List<PresentationSummary>> presentationsByVisit = getPresentationsByVisit(visitIds);

    for (Visit__c visit : visits) {
      TimelineItem item = new TimelineItem();
      item.key = 'visit-' + visit.Id;
      item.type = 'visit';
      item.typeLabel = 'Visit';
      item.iconName = 'utility:event';
      item.recordId = visit.Id;
      item.accountName = accountName;
      item.title = buildVisitCallTitle(accountName, visit);
      item.subtitle = visit.Visit_Objective__c;
      item.activityDate = visit.Start_Date__c;
      item.ownerName = visit.Assigned_To__r?.Name;
      item.status = visit.Status__c;
      item.address = formattedAddress;
      item.channel = String.isNotBlank(visit.Visit_Type__c) ? visit.Visit_Type__c : 'Face To Face';
      item.presentations = presentationsByVisit.containsKey(visit.Id)
        ? presentationsByVisit.get(visit.Id)
        : new List<PresentationSummary>();
      if (productsByVisit.containsKey(visit.Id)) {
        item.products = productsByVisit.get(visit.Id);
      } else {
        item.products = buildProductChipsFromNames(
          splitProductNames(visit.Products_Discussed__c)
        );
      }
      item.productNames = productNamesFromChips(item.products);
      item.detailLines = buildVisitDetailLines(visit);
      items.add(item);
    }
    return items;
  }

  private static List<TimelineItem> buildPresentationTimelineItems(Id accountId) {
    List<TimelineItem> items = new List<TimelineItem>();
    List<CLM_Presentation_Session__c> sessions = [
      SELECT
        Id,
        Name,
        Status__c,
        Started_At__c,
        Total_Duration_Seconds__c,
        Slides_Presented_Count__c,
        User__r.Name,
        Visit__c,
        Visit__r.Name,
        CLM_Presentation__r.Name,
        CLM_Presentation__r.Slide_Count__c,
        CLM_Presentation__r.Product__r.Name,
        CLM_Presentation__r.Product__r.Product_Image_URL__c
      FROM CLM_Presentation_Session__c
      WHERE Account__c = :accountId AND Status__c = 'Completed' AND Visit__c = NULL
      WITH USER_MODE
      ORDER BY Started_At__c DESC NULLS LAST
      LIMIT 100
    ];

    if (sessions.isEmpty()) {
      return items;
    }

    Set<Id> sessionIds = new Set<Id>();
    for (CLM_Presentation_Session__c session : sessions) {
      sessionIds.add(session.Id);
    }
    Map<Id, List<String>> productsBySession = getPresentationProductNames(sessionIds);
    Map<Id, List<SlideThumbnail>> thumbnailsBySession = getSlideThumbnailsBySession(sessionIds);

    for (CLM_Presentation_Session__c session : sessions) {
      TimelineItem item = new TimelineItem();
      item.key = 'presentation-' + session.Id;
      item.type = 'presentation';
      item.typeLabel = 'Presentation';
      item.iconName = 'utility:screen';
      item.recordId = session.Id;
      item.title = session.CLM_Presentation__r?.Name;
      item.subtitle = session.Visit__r?.Name != null
        ? 'Visit ' + session.Visit__r.Name
        : null;
      item.activityDate = session.Started_At__c;
      item.ownerName = session.User__r?.Name;
      item.status = session.Status__c;
      item.productNames = productsBySession.containsKey(session.Id)
        ? productsBySession.get(session.Id)
        : buildPresentationProductFallback(session);
      item.products = buildProductChipsFromNames(item.productNames);
      if (
        item.products.isEmpty() &&
        session.CLM_Presentation__r?.Product__r?.Name != null
      ) {
        ProductChip chip = new ProductChip();
        chip.productName = session.CLM_Presentation__r.Product__r.Name;
        chip.imageUrl = session.CLM_Presentation__r.Product__r.Product_Image_URL__c;
        item.products = new List<ProductChip>{ chip };
        item.productNames = new List<String>{ chip.productName };
      }
      item.detailLines = buildPresentationDetailLines(session);
      item.presentations = new List<PresentationSummary>{
        buildPresentationSummary(session, thumbnailsBySession.get(session.Id))
      };
      items.add(item);
    }
    return items;
  }

  private static List<TimelineItem> buildSampleTimelineItems(Id accountId) {
    return new List<TimelineItem>();
  }

  private static List<TimelineItem> buildEmailTimelineItems(Id accountId) {
    List<TimelineItem> items = new List<TimelineItem>();

    try {
      if (Schema.sObjectType.EmailMessage.isAccessible()) {
        for (EmailMessage email : [
          SELECT Id, Subject, MessageDate, FromName, FromAddress, TextBody, Status
          FROM EmailMessage
          WHERE RelatedToId = :accountId
          ORDER BY MessageDate DESC NULLS LAST
          LIMIT 50
        ]) {
          TimelineItem item = new TimelineItem();
          item.key = 'email-' + email.Id;
          item.type = 'email';
          item.typeLabel = 'Email Sent';
          item.iconName = 'utility:email';
          item.recordId = email.Id;
          item.title = String.isNotBlank(email.Subject) ? email.Subject : '(No subject)';
          item.subtitle = email.FromName;
          item.activityDate = email.MessageDate;
          item.ownerName = email.FromName;
          item.status = email.Status;
          item.detailLines = buildEmailPreview(email.TextBody);
          items.add(item);
        }
      }
    } catch (Exception ex) {
      // EmailMessage may be unavailable depending on org features.
    }

    try {
      String emailType = 'Email';
      for (Task task : [
        SELECT Id, Subject, ActivityDate, Owner.Name, Description, Status, Type
        FROM Task
        WHERE WhatId = :accountId AND Type = :emailType
        ORDER BY ActivityDate DESC NULLS LAST
        LIMIT 50
      ]) {
        TimelineItem item = new TimelineItem();
        item.key = 'task-email-' + task.Id;
        item.type = 'email';
        item.typeLabel = 'Email';
        item.iconName = 'utility:email';
        item.recordId = task.Id;
        item.title = String.isNotBlank(task.Subject) ? task.Subject : '(No subject)';
        item.activityDate = task.ActivityDate != null
          ? Datetime.newInstance(task.ActivityDate, Time.newInstance(12, 0, 0, 0))
          : null;
        item.ownerName = task.Owner?.Name;
        item.status = task.Status;
        item.detailLines = buildEmailPreview(task.Description);
        items.add(item);
      }
    } catch (Exception ex) {
      // Task.Type filtering can fail in some orgs.
    }

    return items;
  }

  private static Map<Id, List<ProductChip>> getProductsByVisit(Set<Id> visitIds) {
    Map<Id, List<ProductChip>> productsByVisit = new Map<Id, List<ProductChip>>();
    if (visitIds.isEmpty() || !Schema.sObjectType.Visit_Product_Detail__c.isAccessible()) {
      return productsByVisit;
    }

    List<Id> visitIdList = new List<Id>(visitIds);
    for (Visit_Product_Detail__c detail : [
      SELECT Visit__c, Product2__c, Product2__r.Name, Product2__r.Product_Image_URL__c, Display_Order__c
      FROM Visit_Product_Detail__c
      WHERE Visit__c IN :visitIdList
      ORDER BY Display_Order__c ASC, CreatedDate ASC
    ]) {
      if (!productsByVisit.containsKey(detail.Visit__c)) {
        productsByVisit.put(detail.Visit__c, new List<ProductChip>());
      }
      ProductChip chip = new ProductChip();
      chip.productId = detail.Product2__c;
      chip.productName = detail.Product2__r?.Name;
      chip.imageUrl = detail.Product2__r?.Product_Image_URL__c;
      productsByVisit.get(detail.Visit__c).add(chip);
    }
    return productsByVisit;
  }

  private static List<ProductChip> buildProductChipsFromNames(List<String> names) {
    List<ProductChip> chips = new List<ProductChip>();
    if (names == null) {
      return chips;
    }
    for (String name : names) {
      if (String.isBlank(name)) {
        continue;
      }
      ProductChip chip = new ProductChip();
      chip.productName = name;
      chips.add(chip);
    }
    return enrichProductChipsWithImages(chips);
  }

  private static List<ProductChip> enrichProductChipsWithImages(List<ProductChip> chips) {
    if (chips == null || chips.isEmpty()) {
      return chips == null ? new List<ProductChip>() : chips;
    }

    Set<String> namesToResolve = new Set<String>();
    for (ProductChip chip : chips) {
      if (chip.productId == null && String.isNotBlank(chip.productName)) {
        namesToResolve.add(chip.productName);
      }
    }

    Map<String, Product2> productsByName = getProductsByName(namesToResolve);
    for (ProductChip chip : chips) {
      if (chip.productId != null || String.isBlank(chip.productName)) {
        continue;
      }
      Product2 product = productsByName.get(chip.productName.toLowerCase());
      if (product != null) {
        chip.productId = product.Id;
        chip.imageUrl = product.Product_Image_URL__c;
      }
    }
    return chips;
  }

  private static Map<String, Product2> getProductsByName(Set<String> names) {
    Map<String, Product2> productsByName = new Map<String, Product2>();
    if (names == null || names.isEmpty()) {
      return productsByName;
    }
    for (Product2 product : [
      SELECT Id, Name, Product_Image_URL__c
      FROM Product2
      WHERE Name IN :names AND IsActive = TRUE
      WITH USER_MODE
    ]) {
      productsByName.put(product.Name.toLowerCase(), product);
    }
    return productsByName;
  }

  private static List<String> productNamesFromChips(List<ProductChip> chips) {
    List<String> names = new List<String>();
    if (chips == null) {
      return names;
    }
    for (ProductChip chip : chips) {
      if (String.isNotBlank(chip.productName)) {
        names.add(chip.productName);
      }
    }
    return names;
  }

  private static Map<Id, List<String>> getPresentationProductNames(Set<Id> sessionIds) {
    Map<Id, List<String>> productsBySession = new Map<Id, List<String>>();
    if (sessionIds.isEmpty()) {
      return productsBySession;
    }

    for (CLM_Message_Response__c response : [
      SELECT CLM_Presentation_Session__c, Product_Name__c, Message_Name__c
      FROM CLM_Message_Response__c
      WHERE CLM_Presentation_Session__c IN :sessionIds
      WITH USER_MODE
      ORDER BY Sort_Order__c ASC NULLS LAST
    ]) {
      if (!productsBySession.containsKey(response.CLM_Presentation_Session__c)) {
        productsBySession.put(response.CLM_Presentation_Session__c, new List<String>());
      }
      List<String> names = productsBySession.get(response.CLM_Presentation_Session__c);
      if (String.isNotBlank(response.Product_Name__c) && !names.contains(response.Product_Name__c)) {
        names.add(response.Product_Name__c);
      }
    }
    return productsBySession;
  }

  private static List<String> buildPresentationProductFallback(CLM_Presentation_Session__c session) {
    List<String> names = new List<String>();
    if (session.CLM_Presentation__r?.Product__r?.Name != null) {
      names.add(session.CLM_Presentation__r.Product__r.Name);
    }
    return names;
  }

  private static Account getAccountForTimeline(Id accountId) {
    List<Account> accounts = [
      SELECT
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    return accounts.isEmpty() ? null : accounts[0];
  }

  private static String formatAccountAddress(Account account) {
    if (account == null) {
      return null;
    }
    List<String> parts = new List<String>();
    if (String.isNotBlank(account.BillingStreet)) {
      parts.add(account.BillingStreet);
    }
    if (String.isNotBlank(account.BillingCity)) {
      parts.add(account.BillingCity);
    }
    if (String.isNotBlank(account.BillingState)) {
      parts.add(account.BillingState);
    }
    if (String.isNotBlank(account.BillingPostalCode)) {
      parts.add(account.BillingPostalCode);
    }
    if (String.isNotBlank(account.BillingCountry)) {
      parts.add(account.BillingCountry);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static Map<Id, List<PresentationSummary>> getPresentationsByVisit(Set<Id> visitIds) {
    Map<Id, List<PresentationSummary>> presentationsByVisit = new Map<Id, List<PresentationSummary>>();
    if (visitIds.isEmpty()) {
      return presentationsByVisit;
    }

    List<CLM_Presentation_Session__c> sessions = [
      SELECT
        Id,
        Visit__c,
        Status__c,
        Started_At__c,
        Total_Duration_Seconds__c,
        Slides_Presented_Count__c,
        CLM_Presentation__r.Name,
        CLM_Presentation__r.Slide_Count__c
      FROM CLM_Presentation_Session__c
      WHERE Visit__c IN :visitIds AND Status__c = 'Completed'
      WITH USER_MODE
      ORDER BY Started_At__c ASC NULLS LAST
    ];

    if (sessions.isEmpty()) {
      return presentationsByVisit;
    }

    Set<Id> sessionIds = new Set<Id>();
    for (CLM_Presentation_Session__c session : sessions) {
      sessionIds.add(session.Id);
    }
    Map<Id, List<SlideThumbnail>> thumbnailsBySession = getSlideThumbnailsBySession(sessionIds);

    for (CLM_Presentation_Session__c session : sessions) {
      if (!presentationsByVisit.containsKey(session.Visit__c)) {
        presentationsByVisit.put(session.Visit__c, new List<PresentationSummary>());
      }
      presentationsByVisit.get(session.Visit__c).add(
        buildPresentationSummary(session, thumbnailsBySession.get(session.Id))
      );
    }
    return presentationsByVisit;
  }

  private static PresentationSummary buildPresentationSummary(
    CLM_Presentation_Session__c session,
    List<SlideThumbnail> thumbnails
  ) {
    PresentationSummary summary = new PresentationSummary();
    summary.sessionId = session.Id;
    summary.presentationName = session.CLM_Presentation__r?.Name;
    Integer presented = session.Slides_Presented_Count__c != null
      ? Integer.valueOf(session.Slides_Presented_Count__c)
      : 0;
    Integer total = session.CLM_Presentation__r?.Slide_Count__c != null
      ? Integer.valueOf(session.CLM_Presentation__r.Slide_Count__c)
      : 0;
    summary.slidesPresented = presented;
    summary.slideCount = total;
    summary.slidesLabel = presented + '/' + total + ' slides presented';
    summary.durationLabel = buildDurationLabel(session.Total_Duration_Seconds__c);
    summary.slideThumbnails = thumbnails != null ? thumbnails : new List<SlideThumbnail>();
    return summary;
  }

  private static Map<Id, List<SlideThumbnail>> getSlideThumbnailsBySession(Set<Id> sessionIds) {
    Map<Id, List<SlideThumbnail>> thumbnailsBySession = new Map<Id, List<SlideThumbnail>>();
    if (sessionIds.isEmpty()) {
      return thumbnailsBySession;
    }

    for (CLM_Slide_Metric__c metric : [
      SELECT
        CLM_Presentation_Session__c,
        Sequence_Name__c,
        Was_Presented__c,
        Sequence_Order__c,
        CLM_Sequence__r.Thumbnail_Content_Version_Id__c,
        CLM_Sequence__r.Slide_Image_URL__c
      FROM CLM_Slide_Metric__c
      WHERE CLM_Presentation_Session__c IN :sessionIds AND Was_Presented__c = TRUE
      WITH USER_MODE
      ORDER BY Sequence_Order__c ASC NULLS LAST
    ]) {
      if (!thumbnailsBySession.containsKey(metric.CLM_Presentation_Session__c)) {
        thumbnailsBySession.put(
          metric.CLM_Presentation_Session__c,
          new List<SlideThumbnail>()
        );
      }
      List<SlideThumbnail> thumbnails = thumbnailsBySession.get(metric.CLM_Presentation_Session__c);
      if (thumbnails.size() >= 4) {
        continue;
      }
      SlideThumbnail thumb = new SlideThumbnail();
      thumb.label = truncate(metric.Sequence_Name__c, 24);
      thumb.thumbnailUrl = ClmContentService.buildContentUrl(
        metric.CLM_Sequence__r?.Thumbnail_Content_Version_Id__c,
        metric.CLM_Sequence__r?.Slide_Image_URL__c
      );
      thumbnails.add(thumb);
    }
    return thumbnailsBySession;
  }

  private static String buildDurationLabel(Decimal totalSeconds) {
    if (totalSeconds == null) {
      return null;
    }
    Integer seconds = Integer.valueOf(totalSeconds);
    Integer mins = seconds / 60;
    Integer secs = Math.mod(seconds, 60);
    return mins + 'm ' + secs + 's';
  }

  private static String buildDateGroupLabel(Datetime activityDate) {
    if (activityDate == null) {
      return 'Earlier';
    }
    Date activityDay = activityDate.date();
    Date today = Date.today();
    if (activityDay == today) {
      return 'Today';
    }
    if (activityDay == today.addDays(-1)) {
      return 'Yesterday';
    }
    return activityDay.format();
  }

  private static String buildVisitCallTitle(String accountName, Visit__c visit) {
    if (String.isNotBlank(accountName)) {
      return 'Call started with ' + accountName;
    }
    return buildVisitTitle(visit);
  }

  private static String buildVisitTitle(Visit__c visit) {
    String typeLabel = String.isNotBlank(visit.Visit_Type__c) ? visit.Visit_Type__c : 'Visit';
    return typeLabel + ' — ' + visit.Name;
  }

  private static List<String> buildVisitDetailLines(Visit__c visit) {
    List<String> lines = new List<String>();
    if (String.isNotBlank(visit.Visit_Notes__c)) {
      lines.add(truncate(visit.Visit_Notes__c, 220));
    }
    return lines;
  }

  private static List<String> buildPresentationDetailLines(CLM_Presentation_Session__c session) {
    List<String> lines = new List<String>();
    Decimal presented = session.Slides_Presented_Count__c != null ? session.Slides_Presented_Count__c : 0;
    Decimal total = session.CLM_Presentation__r?.Slide_Count__c != null
      ? session.CLM_Presentation__r.Slide_Count__c
      : 0;
    lines.add(Integer.valueOf(presented) + ' of ' + Integer.valueOf(total) + ' slides presented');

    if (session.Total_Duration_Seconds__c != null) {
      Integer seconds = Integer.valueOf(session.Total_Duration_Seconds__c);
      Integer mins = seconds / 60;
      Integer secs = Math.mod(seconds, 60);
      lines.add('Duration ' + mins + 'm ' + secs + 's');
    }
    return lines;
  }

  private static List<String> buildSampleDetailLines(Visit_Sample__c sample) {
    List<String> lines = new List<String>();
    if (sample.Quantity__c != null) {
      lines.add('Quantity: ' + sample.Quantity__c.intValue());
    }
    if (String.isNotBlank(sample.Lot_Number__c)) {
      lines.add('Lot ' + sample.Lot_Number__c);
    }
    return lines;
  }

  private static List<String> buildEmailPreview(String body) {
    if (String.isBlank(body)) {
      return new List<String>();
    }
    return new List<String>{ truncate(body, 220) };
  }

  private static List<String> splitProductNames(String productsDiscussed) {
    List<String> names = new List<String>();
    if (String.isBlank(productsDiscussed)) {
      return names;
    }
    for (String part : productsDiscussed.split('[;,]')) {
      String trimmed = part.trim();
      if (String.isNotBlank(trimmed)) {
        names.add(trimmed);
      }
    }
    return names;
  }

  private static String truncate(String value, Integer maxLength) {
    if (String.isBlank(value)) {
      return value;
    }
    String normalized = value.replaceAll('\\s+', ' ').trim();
    if (normalized.length() <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength - 1) + '…';
  }

  private class TimelineItemComparator implements Comparator<TimelineItem> {
    public Integer compare(TimelineItem a, TimelineItem b) {
      Long aTime = a.activityDate != null ? a.activityDate.getTime() : 0;
      Long bTime = b.activityDate != null ? b.activityDate.getTime() : 0;
      if (aTime == bTime) {
        return 0;
      }
      return aTime > bTime ? -1 : 1;
    }
  }
}