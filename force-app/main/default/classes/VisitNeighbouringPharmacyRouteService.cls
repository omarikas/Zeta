public with sharing class VisitNeighbouringPharmacyRouteService {
  private static final Integer FOLLOW_ON_DURATION_MINUTES = 30;
  private static final Integer FOLLOW_ON_GAP_MINUTES = 15;

  public class AddPharmacyResult {
    @AuraEnabled public Id accountId;
    @AuraEnabled public Id visitId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Boolean createdAccount;
    @AuraEnabled public DateTime visitStart;
    @AuraEnabled public DateTime visitEnd;
  }

  @AuraEnabled
  public static AddPharmacyResult addExternalPharmacyToRoute(
    Id currentVisitId,
    String externalId,
    String name,
    String street,
    String city,
    String state,
    String postalCode,
    String country,
    String phone,
    Decimal latitude,
    Decimal longitude
  ) {
    if (currentVisitId == null) {
      throw new AuraHandledException('Current visit is required.');
    }
    if (String.isBlank(externalId) || String.isBlank(name)) {
      throw new AuraHandledException('Pharmacy name and external id are required.');
    }
    if (latitude == null || longitude == null) {
      throw new AuraHandledException('Pharmacy coordinates are required.');
    }

    Visit__c currentVisit = queryCurrentVisit(currentVisitId);
    PharmacyAccountOutcome pharmacy = findOrCreateExternalPharmacy(
      externalId,
      name,
      street,
      city,
      state,
      postalCode,
      country,
      phone,
      latitude,
      longitude
    );

    Visit__c followOn = insertFollowOnVisit(currentVisit, pharmacy.account.Id);
    AccountAffiliationStrengthService.upsertAndStrengthen(
      currentVisit.Account__c,
      pharmacy.account.Id,
      AccountAffiliationStrengthService.SOURCE_PHARMACY_VISIT
    );

    return toResult(pharmacy.account, followOn, pharmacy.created);
  }

  @AuraEnabled
  public static AddPharmacyResult scheduleAccountPharmacyOnRoute(
    Id currentVisitId,
    Id pharmacyAccountId
  ) {
    if (currentVisitId == null || pharmacyAccountId == null) {
      throw new AuraHandledException('Current visit and pharmacy account are required.');
    }

    Visit__c currentVisit = queryCurrentVisit(currentVisitId);
    List<Account> pharmacies = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :pharmacyAccountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (pharmacies.isEmpty()) {
      throw new AuraHandledException('Pharmacy account not found.');
    }
    Account pharmacy = pharmacies[0];
    if (pharmacy.Id == currentVisit.Account__c) {
      throw new AuraHandledException('Cannot schedule a follow-on visit to the same account.');
    }

    Visit__c followOn = insertFollowOnVisit(currentVisit, pharmacy.Id);
    AccountAffiliationStrengthService.upsertAndStrengthen(
      currentVisit.Account__c,
      pharmacy.Id,
      AccountAffiliationStrengthService.SOURCE_PHARMACY_VISIT
    );

    return toResult(pharmacy, followOn, false);
  }

  private static Visit__c queryCurrentVisit(Id currentVisitId) {
    List<Visit__c> visits = [
      SELECT Id, Account__c, Assigned_To__c, Start_Date__c, End_Date__c, Status__c
      FROM Visit__c
      WHERE Id = :currentVisitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    Visit__c visit = visits[0];
    if (visit.Account__c == null) {
      throw new AuraHandledException('Current visit has no account.');
    }
    if (visit.End_Date__c == null) {
      throw new AuraHandledException('Current visit needs an end time to schedule a follow-on.');
    }
    return visit;
  }

  private class PharmacyAccountOutcome {
    Account account;
    Boolean created;
  }

  private static PharmacyAccountOutcome findOrCreateExternalPharmacy(
    String externalId,
    String name,
    String street,
    String city,
    String state,
    String postalCode,
    String country,
    String phone,
    Decimal latitude,
    Decimal longitude
  ) {
    PharmacyAccountOutcome outcome = new PharmacyAccountOutcome();
    String placeKey = 'OSM-' + externalId;

    List<Account> existing = [
      SELECT Id, Name
      FROM Account
      WHERE Maps_Place_Id__c = :placeKey OR External_ID__c = :placeKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      outcome.account = existing[0];
      outcome.created = false;
      return outcome;
    }

    Id pharmacyRtId = resolvePharmacyRecordTypeId();
    Account pharmacy = new Account(
      Name = name,
      BillingStreet = street,
      BillingCity = city,
      BillingState = state,
      BillingPostalCode = postalCode,
      BillingCountry = String.isBlank(country) ? 'Egypt' : country,
      Phone = phone,
      BillingLatitude = latitude,
      BillingLongitude = longitude,
      Maps_Place_Id__c = placeKey,
      External_ID__c = placeKey,
      Account_Stage__c = 'Draft'
    );
    if (pharmacyRtId != null) {
      pharmacy.RecordTypeId = pharmacyRtId;
    }
    insert as user pharmacy;
    outcome.account = pharmacy;
    outcome.created = true;
    return outcome;
  }

  private static Visit__c insertFollowOnVisit(Visit__c currentVisit, Id pharmacyAccountId) {
    DateTime startAt = currentVisit.End_Date__c.addMinutes(FOLLOW_ON_GAP_MINUTES);
    DateTime endAt = startAt.addMinutes(FOLLOW_ON_DURATION_MINUTES);

    Visit__c followOn = new Visit__c(
      Account__c = pharmacyAccountId,
      Assigned_To__c = currentVisit.Assigned_To__c != null
        ? currentVisit.Assigned_To__c
        : UserInfo.getUserId(),
      Start_Date__c = startAt,
      End_Date__c = endAt,
      Visit_Date__c = startAt,
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)',
      Visit_Objective__c = 'Follow-on pharmacy visit'
    );
    insert as user followOn;
    return followOn;
  }

  private static AddPharmacyResult toResult(Account pharmacy, Visit__c followOn, Boolean created) {
    AddPharmacyResult result = new AddPharmacyResult();
    result.accountId = pharmacy.Id;
    result.accountName = pharmacy.Name;
    result.createdAccount = created;
    result.visitId = followOn.Id;
    result.visitStart = followOn.Start_Date__c;
    result.visitEnd = followOn.End_Date__c;
    return result;
  }

  private static Id resolvePharmacyRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy' AND IsActive = TRUE
      LIMIT 1
    ];
    return types.isEmpty() ? null : types[0].Id;
  }
}
