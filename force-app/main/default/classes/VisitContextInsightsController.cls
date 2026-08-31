public with sharing class VisitContextInsightsController {
  private static final Decimal DEFAULT_RADIUS_KM = 25;
  private static final Decimal MAX_SEARCH_RADIUS_KM = 200;
  private static final Integer MAX_PHARMACIES = 50;
  private static final Integer PAGE_SIZE = 5;
  private static final Integer MAX_PRIOR_VISITS = 3;
  private static final Integer NOTES_SNIPPET_LEN = 180;

  public class PharmacyRow {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String name;
    @AuraEnabled public String street;
    @AuraEnabled public String city;
    @AuraEnabled public String state;
    @AuraEnabled public String postalCode;
    @AuraEnabled public String country;
    @AuraEnabled public String phone;
    @AuraEnabled public Decimal distanceKm;
    @AuraEnabled public Decimal latitude;
    @AuraEnabled public Decimal longitude;
    @AuraEnabled public Boolean inAccountList;
    @AuraEnabled public String source;
    @AuraEnabled public String externalId;
    @AuraEnabled public String mapsUrl;
  }

  public class PriorVisitRow {
    @AuraEnabled public Id visitId;
    @AuraEnabled public String visitName;
    @AuraEnabled public DateTime startDateTime;
    @AuraEnabled public String repName;
    @AuraEnabled public String objective;
    @AuraEnabled public String notesSnippet;
    @AuraEnabled public String productsDiscussed;
  }

  public class VisitContextInsights {
    @AuraEnabled public Boolean hasGeo;
    @AuraEnabled public Decimal searchRadiusKm;
    @AuraEnabled public Decimal centerLatitude;
    @AuraEnabled public Decimal centerLongitude;
    @AuraEnabled public String centerAccountName;
    @AuraEnabled public Integer totalPharmacyCount;
    @AuraEnabled public Integer pharmacyPageSize;
    @AuraEnabled public List<PharmacyRow> neighbouringPharmacies;
    @AuraEnabled public List<PriorVisitRow> territoryPriorVisits;
    @AuraEnabled public List<PriorVisitRow> zetaPriorVisits;
  }

  @AuraEnabled(cacheable=true)
  public static VisitContextInsights getVisitContextInsights(Id visitId) {
    VisitContextInsights result = new VisitContextInsights();
    result.hasGeo = false;
    result.searchRadiusKm = DEFAULT_RADIUS_KM;
    result.pharmacyPageSize = PAGE_SIZE;
    result.neighbouringPharmacies = new List<PharmacyRow>();
    result.territoryPriorVisits = new List<PriorVisitRow>();
    result.zetaPriorVisits = new List<PriorVisitRow>();

    if (visitId == null) {
      return result;
    }

    List<Visit__c> visits = [
      SELECT
        Id,
        Account__c,
        Start_Date__c,
        Assigned_To__c,
        Account__r.Name,
        Account__r.BillingLatitude,
        Account__r.BillingLongitude
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      return result;
    }

    Visit__c visit = visits[0];
    if (
      visit.Account__r.BillingLatitude != null &&
      visit.Account__r.BillingLongitude != null
    ) {
      result.hasGeo = true;
      result.centerLatitude = visit.Account__r.BillingLatitude;
      result.centerLongitude = visit.Account__r.BillingLongitude;
      result.centerAccountName = visit.Account__r.Name;
      result.neighbouringPharmacies = loadNeighbouringPharmacies(
        visit.Account__c,
        visit.Account__r.BillingLatitude,
        visit.Account__r.BillingLongitude
      );
      result.totalPharmacyCount = result.neighbouringPharmacies.size();
    }

    result.territoryPriorVisits = loadTerritoryPriorVisits(visit);
    result.zetaPriorVisits = loadZetaPriorVisits(visit);
    return result;
  }

  @AuraEnabled
  public static List<PharmacyRow> searchOpenMapPharmacies(
    Decimal centerLat,
    Decimal centerLng,
    Decimal radiusKm,
    String accountPharmacyAnchorsJson
  ) {
    return VisitOpenMapPharmacyService.searchNearby(
      centerLat,
      centerLng,
      radiusKm,
      accountPharmacyAnchorsJson
    );
  }

  @AuraEnabled
  public static VisitNeighbouringPharmacyRouteService.AddPharmacyResult addExternalPharmacyToRoute(
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
    return VisitNeighbouringPharmacyRouteService.addExternalPharmacyToRoute(
      currentVisitId,
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
  }

  private static List<PharmacyRow> loadNeighbouringPharmacies(
    Id excludeAccountId,
    Decimal centerLat,
    Decimal centerLng
  ) {
    Id pharmacyRtId = resolvePharmacyRecordTypeId();
    List<Account> candidates = pharmacyRtId == null
      ? new List<Account>()
      : [
          SELECT Id, Name, BillingCity, Phone, BillingLatitude, BillingLongitude
          FROM Account
          WHERE
            RecordTypeId = :pharmacyRtId
            AND Id != :excludeAccountId
            AND BillingLatitude != NULL
            AND BillingLongitude != NULL
          WITH USER_MODE
          LIMIT 500
        ];

    List<PharmacyRow> rows = new List<PharmacyRow>();
    for (Account pharmacy : candidates) {
      Decimal distanceKm = haversineKm(
        centerLat,
        centerLng,
        pharmacy.BillingLatitude,
        pharmacy.BillingLongitude
      );
      if (distanceKm > MAX_SEARCH_RADIUS_KM) {
        continue;
      }
      PharmacyRow row = new PharmacyRow();
      row.accountId = pharmacy.Id;
      row.name = pharmacy.Name;
      row.city = pharmacy.BillingCity;
      row.phone = pharmacy.Phone;
      row.distanceKm = distanceKm.setScale(1);
      row.latitude = pharmacy.BillingLatitude;
      row.longitude = pharmacy.BillingLongitude;
      row.inAccountList = true;
      row.source = 'account';
      rows.add(row);
    }

    rows.sort(new PharmacyDistanceComparator());
    List<PharmacyRow> withinRadius = new List<PharmacyRow>();
    for (PharmacyRow row : rows) {
      if (row.distanceKm <= DEFAULT_RADIUS_KM) {
        withinRadius.add(row);
      }
      if (withinRadius.size() >= MAX_PHARMACIES) {
        break;
      }
    }
    return withinRadius;
  }

  private static List<PriorVisitRow> loadTerritoryPriorVisits(Visit__c visit) {
    Set<Id> territoryUserIds = getTerritoryPeerUserIds(visit.Assigned_To__c);
    if (territoryUserIds.isEmpty()) {
      return new List<PriorVisitRow>();
    }
    return loadPriorVisits(
      visit.Account__c,
      visit.Id,
      visit.Start_Date__c,
      territoryUserIds
    );
  }

  private static List<PriorVisitRow> loadZetaPriorVisits(Visit__c visit) {
    return loadPriorVisits(visit.Account__c, visit.Id, visit.Start_Date__c, null);
  }

  private static List<PriorVisitRow> loadPriorVisits(
    Id accountId,
    Id currentVisitId,
    DateTime beforeStart,
    Set<Id> assignedToFilter
  ) {
    if (accountId == null) {
      return new List<PriorVisitRow>();
    }

    String soql =
      'SELECT Id, Name, Start_Date__c, Visit_Objective__c, Visit_Notes__c, ' +
      'Products_Discussed__c, Assigned_To__r.Name ' +
      'FROM Visit__c ' +
      'WHERE Account__c = :accountId ' +
      'AND Status__c = \'Completed\' ' +
      'AND Id != :currentVisitId ';
    if (beforeStart != null) {
      soql += 'AND Start_Date__c < :beforeStart ';
    }
    if (assignedToFilter != null && !assignedToFilter.isEmpty()) {
      soql += 'AND Assigned_To__c IN :assignedToFilter ';
    }
    soql +=
      'WITH USER_MODE ORDER BY Start_Date__c DESC NULLS LAST LIMIT ' +
      MAX_PRIOR_VISITS;

    List<PriorVisitRow> rows = new List<PriorVisitRow>();
    for (Visit__c prior : Database.query(soql)) {
      PriorVisitRow row = new PriorVisitRow();
      row.visitId = prior.Id;
      row.visitName = prior.Name;
      row.startDateTime = prior.Start_Date__c;
      row.repName = prior.Assigned_To__r?.Name;
      row.objective = prior.Visit_Objective__c;
      row.notesSnippet = snippet(prior.Visit_Notes__c);
      row.productsDiscussed = prior.Products_Discussed__c;
      rows.add(row);
    }
    return rows;
  }

  private static Set<Id> getTerritoryPeerUserIds(Id assignedToId) {
    Set<Id> userIds = new Set<Id>();
    if (assignedToId == null) {
      return userIds;
    }

    Set<Id> territoryIds = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :assignedToId
      WITH USER_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    if (territoryIds.isEmpty()) {
      userIds.add(assignedToId);
      return userIds;
    }

    for (UserTerritory2Association peer : [
      SELECT UserId
      FROM UserTerritory2Association
      WHERE Territory2Id IN :territoryIds
      WITH USER_MODE
    ]) {
      userIds.add(peer.UserId);
    }
    return userIds;
  }

  private static Id resolvePharmacyRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
      WITH USER_MODE
      LIMIT 1
    ];
    return types.isEmpty() ? null : types[0].Id;
  }

  private static String snippet(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.length() <= NOTES_SNIPPET_LEN
      ? trimmed
      : trimmed.substring(0, NOTES_SNIPPET_LEN) + '…';
  }

  @TestVisible
  public static Decimal distanceKm(
    Decimal lat1,
    Decimal lng1,
    Decimal lat2,
    Decimal lng2
  ) {
    return haversineKm(lat1, lng1, lat2, lng2);
  }

  private static Decimal haversineKm(
    Decimal lat1,
    Decimal lng1,
    Decimal lat2,
    Decimal lng2
  ) {
    Double r = 6371.0;
    Double dLat = toRadians(lat2 - lat1);
    Double dLng = toRadians(lng2 - lng1);
    Double a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
    Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Decimal.valueOf(r * c);
  }

  private static Double toRadians(Decimal value) {
    return (value == null ? 0 : value.doubleValue()) * Math.PI / 180.0;
  }

  public class PharmacyDistanceComparator implements System.Comparator<PharmacyRow> {
    public Integer compare(PharmacyRow a, PharmacyRow b) {
      if (a.distanceKm == b.distanceKm) {
        return 0;
      }
      return a.distanceKm < b.distanceKm ? -1 : 1;
    }
  }
}