public with sharing class VisitCallReportService {

  private static final Integer ATTENDEE_PAGE_SIZE = 25;
  private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
  };

  private static Boolean productImageUrlReadable;

  public class TerritoryProductOption {
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public String productType;
    @AuraEnabled public Id parentProductId;
    @AuraEnabled public String brandName;
    @AuraEnabled public String strength;
    @AuraEnabled public String form;
    @AuraEnabled public String adoption;
    @AuraEnabled public String loyalty;
    @AuraEnabled public String productMatrixRating;
    @AuraEnabled public String targetVisitFrequency;
    @AuraEnabled public Decimal rxPerWeek;
  }

  public class AttendeeCandidate {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String specialty;
    @AuraEnabled public String recordTypeDeveloperName;
    @AuraEnabled public String accountTypeLabel;
    @AuraEnabled public String source;
  }

  public class AttendeeRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String specialty;
    @AuraEnabled public String recordTypeDeveloperName;
    @AuraEnabled public String accountTypeLabel;
    @AuraEnabled public String role;
    @AuraEnabled public Boolean isPrimary;
    @AuraEnabled public Integer displayOrder;
  }

  public class ProductMessageRow {
    @AuraEnabled public Id id;
    @AuraEnabled public String topic;
    @AuraEnabled public String sentiment;
    @AuraEnabled public String response;
  }

  public class ProductDetailRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public String productType;
    @AuraEnabled public Id parentProductId;
    @AuraEnabled public String brandName;
    @AuraEnabled public String strength;
    @AuraEnabled public String form;
    @AuraEnabled public Integer displayOrder;
    @AuraEnabled public String detailType;
    @AuraEnabled public String notes;
    @AuraEnabled public List<ProductMessageRow> messages;
  }

  public class SampleRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public Id visitAttendeeId;
    @AuraEnabled public String attendeeName;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public String lotNumber;
    @AuraEnabled public Id sampleInventoryId;
    @AuraEnabled public Decimal inventoryOnHand;
    @AuraEnabled public Date inventoryExpiry;
  }

  public class SampleInventoryOption {
    @AuraEnabled public Id id;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public String lotNumber;
    @AuraEnabled public Decimal quantityOnHand;
    @AuraEnabled public Date expiryDate;
  }

  public class ClmSessionRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id presentationId;
    @AuraEnabled public String presentationName;
    @AuraEnabled public String status;
    @AuraEnabled public DateTime startedAt;
    @AuraEnabled public DateTime endedAt;
    @AuraEnabled public Integer slidesPresentedCount;
    @AuraEnabled public Integer totalDurationSeconds;
  }

  public class VisitHeader {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String status;
    @AuraEnabled public String visitType;
    @AuraEnabled public DateTime startDateTime;
    @AuraEnabled public DateTime endDateTime;
    @AuraEnabled public String durationLabel;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String accountRecordTypeName;
    @AuraEnabled public String accountRecordTypeDeveloperName;
    @AuraEnabled public String accountSpecialty;
    @AuraEnabled public String accountCity;
    @AuraEnabled public String assignedToName;
    @AuraEnabled public String visitObjective;
    @AuraEnabled public String visitNotes;
    @AuraEnabled public String clmPresentation;
    @AuraEnabled public Date nextVisitDate;
    @AuraEnabled public String cancellationReason;
    @AuraEnabled public Boolean isLocked;
    @AuraEnabled public Boolean isDoubleVisit;
    @AuraEnabled public Id coachingEventId;
  }

  public class CallReportPayload {
    @AuraEnabled public VisitHeader visit;
    @AuraEnabled public List<AttendeeRow> attendees;
    @AuraEnabled public List<ProductDetailRow> products;
    @AuraEnabled public List<SampleRow> samples;
    @AuraEnabled public List<ClmSessionRow> clmSessions;
    @AuraEnabled public Boolean legacyMigrated;
  }

  public class SaveRequest {
    @AuraEnabled public Id visitId;
    @AuraEnabled public String status;
    @AuraEnabled public String visitObjective;
    @AuraEnabled public String visitNotes;
    @AuraEnabled public String clmPresentation;
    @AuraEnabled public Date nextVisitDate;
    @AuraEnabled public String cancellationReason;
    @AuraEnabled public List<AttendeeRow> attendees;
    @AuraEnabled public List<ProductDetailRow> products;
    @AuraEnabled public List<SampleRow> samples;
    @AuraEnabled public List<ClmSessionRow> clmSessions;
  }

  public static CallReportPayload getCallReportPayload(Id visitId) {
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }

    Visit__c visit = queryVisit(visitId);
    CallReportPayload payload = new CallReportPayload();
    payload.visit = mapVisitHeader(visit);
    payload.attendees = queryAttendees(visitId);
    payload.products = queryProductDetails(visitId);
    payload.samples = querySamples(visitId);
    payload.clmSessions = queryClmSessions(visitId);
    payload.legacyMigrated = false;

    if (payload.attendees.isEmpty() && visit.Account__c != null) {
      payload.attendees.add(buildPrimaryAttendeeFromVisit(visit));
    }

    if (payload.products.isEmpty() && String.isNotBlank(visit.Products_Discussed__c)) {
      payload.products = migrateLegacyProducts(visit);
      payload.legacyMigrated = !payload.products.isEmpty();
    }

    return payload;
  }

  public static List<TerritoryProductOption> getTerritoryProducts(Id visitId) {
    Visit__c visit = queryVisit(visitId);
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    Set<Id> ptaProductIds = getPtaProductIds(territoryIds);
    Set<Id> scopedIds = intersectWithAtpf(visit.Account__c, territoryIds, ptaProductIds);

    if (scopedIds.isEmpty() && !ptaProductIds.isEmpty()) {
      scopedIds = ptaProductIds;
    }
    if (scopedIds.isEmpty()) {
      // Do not fall back to all active products — PTA / ATPF scope is required.
      return new List<TerritoryProductOption>();
    }

    Map<Id, Account_Territory_Product_Fields__c> atpfByProduct = getAtpfByProduct(
      visit.Account__c,
      territoryIds,
      scopedIds
    );

    List<TerritoryProductOption> options = new List<TerritoryProductOption>();
    for (Product2 product : queryProductsByIds(scopedIds)) {
      TerritoryProductOption option = mapTerritoryProductOption(product);
      if (atpfByProduct.containsKey(product.Id)) {
        Account_Territory_Product_Fields__c atpf = atpfByProduct.get(product.Id);
        option.adoption = atpf.Adoption__c;
        option.loyalty = atpf.Loyalty__c;
        option.productMatrixRating = atpf.Product_Matrix_Rating__c;
        option.targetVisitFrequency = atpf.Target_Visit_Frequency__c;
        option.rxPerWeek = atpf.Rx_Per_Week__c;
      }
      options.add(option);
    }
    return options;
  }

  public static List<AttendeeCandidate> searchAttendeeCandidates(
    Id visitId,
    String searchTerm,
    Integer offset
  ) {
    Visit__c visit = queryVisit(visitId);
    Integer resolvedOffset = offset == null || offset < 0 ? 0 : offset;
    Set<Id> existingAccountIds = getExistingAttendeeAccountIds(visitId);
    Set<Id> affiliationCandidateIds = new Set<Id>();
    List<AttendeeCandidate> results = new List<AttendeeCandidate>();

    if (visit.Account__c != null) {
      Id visitAccountId = visit.Account__c;
      try {
        for (Account_Affiliation__c aff : Database.query(
          'SELECT Primary_Account__c, Related_Account__c ' +
          'FROM Account_Affiliation__c ' +
          'WHERE (Primary_Account__c = :visitAccountId OR Related_Account__c = :visitAccountId) ' +
          'AND Is_Active__c = TRUE AND Outside_Territory__c = FALSE ' +
          'WITH USER_MODE LIMIT 200'
        )) {
          Id relatedId = aff.Primary_Account__c == visitAccountId
            ? aff.Related_Account__c
            : aff.Primary_Account__c;
          if (relatedId != null) {
            affiliationCandidateIds.add(relatedId);
          }
        }
      } catch (Exception ex) {
        // Affiliation schema or bind edge cases should not block attendee search.
      }
    }

    String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
    Integer pageSize = ATTENDEE_PAGE_SIZE;
    Integer limitBind = pageSize;
    Integer offsetBind = resolvedOffset;
    String likeTerm = term;

    Set<Id> scopedAccountIds;
    if (likeTerm != null) {
      scopedAccountIds = findTerritoryAccountIdsByName(likeTerm, pageSize + resolvedOffset + 50);
    } else if (!affiliationCandidateIds.isEmpty()) {
      scopedAccountIds = affiliationCandidateIds;
    } else {
      scopedAccountIds = getTerritoryAccountIdsCapped(500);
    }

    if (scopedAccountIds.isEmpty()) {
      return results;
    }

    Set<Id> scopedIdsBind = scopedAccountIds;
    String accountSelect = 'Id, Name';
    if (isFieldAccessible(Account.SObjectType, 'Specialty_1__c')) {
      accountSelect += ', Specialty_1__c';
    }
    if (isFieldAccessible(Account.SObjectType, 'RecordTypeId')) {
      accountSelect += ', RecordType.DeveloperName, RecordType.Name';
    }

    List<Account> accounts;
    if (likeTerm != null) {
      accounts = Database.query(
        'SELECT ' +
          accountSelect +
          ' FROM Account WHERE Id IN :scopedIdsBind AND Name LIKE :likeTerm ' +
          'WITH USER_MODE ORDER BY Name ASC LIMIT :limitBind OFFSET :offsetBind'
      );
    } else {
      accounts = Database.query(
        'SELECT ' +
          accountSelect +
          ' FROM Account WHERE Id IN :scopedIdsBind ' +
          'WITH USER_MODE ORDER BY Name ASC LIMIT :limitBind OFFSET :offsetBind'
      );
    }

    for (Account account : accounts) {
      if (existingAccountIds.contains(account.Id)) {
        continue;
      }
      AttendeeCandidate candidate = mapAttendeeCandidate(
        account,
        likeTerm == null && affiliationCandidateIds.contains(account.Id) ? 'Affiliation' : 'Search'
      );
      results.add(candidate);
    }
    return results;
  }

  public static List<SampleInventoryOption> getSampleInventoryForUser() {
    List<SampleInventoryOption> options = new List<SampleInventoryOption>();
    if (!canQuerySampleInventory()) {
      return options;
    }
    Id userId = UserInfo.getUserId();
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    String inventoryFields = 'Lot_Number__c, Quantity_On_Hand__c';
    if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
      inventoryFields += ', Expiry_Date__c';
    }
    String typeFilter = isFieldAccessible(Product2.SObjectType, 'Product_Type__c')
      ? ' AND Product2__r.Product_Type__c IN (\'Sample\', \'Brand Reminder\') '
      : ' ';
    for (Sample_Inventory__c inv : Database.query(
      'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      ', ' + inventoryFields + ' ' +
      'FROM Sample_Inventory__c ' +
      'WHERE Owner_User__c = :userId AND Quantity_On_Hand__c > 0' +
      typeFilter +
      'WITH USER_MODE ORDER BY Product2__r.Name ASC, Lot_Number__c ASC'
    )) {
      SampleInventoryOption option = new SampleInventoryOption();
      option.id = inv.Id;
      option.productId = inv.Product2__c;
      option.productName = inv.Product2__r != null ? inv.Product2__r.Name : null;
      option.imageUrl = inv.Product2__r != null
        ? getProductImageUrl(inv.Product2__r)
        : null;
      option.lotNumber = inv.Lot_Number__c;
      option.quantityOnHand = inv.Quantity_On_Hand__c;
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
        option.expiryDate = (Date) inv.get('Expiry_Date__c');
      }
      options.add(option);
    }
    return options;
  }

  public static List<ClmSessionRow> getClmPresentationsForVisit(Id visitId) {
    return queryClmSessions(visitId);
  }

  public static CallReportPayload saveCallReport(SaveRequest request) {
    if (request == null || request.visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }

    List<String> visitSelect = new List<String>{
      'Id',
      'Status__c',
      'Visit_Type__c',
      'Start_Date__c',
      'Assigned_To__c',
      'End_Date__c',
      'Account__c',
      'Products_Discussed__c',
      'Product_Details__c',
      'Is_Double_Visit__c'
    };
    if (isFieldAccessible(Visit__c.SObjectType, 'Coaching_Event__c')) {
      visitSelect.add('Coaching_Event__c');
    }
    if (isFieldAccessible(Visit__c.SObjectType, 'Call_Report_Score__c')) {
      visitSelect.add('Call_Report_Score__c');
    }
    String visitSoql =
      'SELECT ' +
      String.join(visitSelect, ', ') +
      ' FROM Visit__c WHERE Id = :requestVisitId WITH USER_MODE LIMIT 1';
    Id requestVisitId = request.visitId;
    List<Visit__c> visits = Database.query(visitSoql);
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    Visit__c visit = visits[0];

    Boolean amendingCompleted =
      (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') &&
      FeatureManagement.checkPermission('Amend_Completed_Visits');
    if (
      (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') &&
      !amendingCompleted
    ) {
      throw new AuraHandledException('Completed or cancelled visits cannot be edited.');
    }

    validateSaveRequest(request, visit);

    visit.Status__c = request.status;
    visit.Visit_Objective__c = request.visitObjective;
    visit.Visit_Notes__c = request.visitNotes;
    visit.CLM_Presentation__c = request.clmPresentation;
    visit.Next_Visit_Date__c = request.nextVisitDate;
    visit.Cancellation_Reason__c = 'Cancelled' == request.status ? request.cancellationReason : null;
    if (isFieldAccessible(Visit__c.SObjectType, 'Coaching_Event__c')) {
      visit.Is_Double_Visit__c = visit.get('Coaching_Event__c') != null;
    }
    if ('Completed' == request.status && VisitStatusHelper.isUnplannedVisitType(visit.Visit_Type__c)) {
      VisitStatusHelper.applyUnplannedCompletionValidation(visit);
    }

    rollupLegacyProductFields(visit, request.products);
    update as user visit;

    saveAttendees(request.visitId, request.attendees);
    Map<Id, Id> attendeeIdByAccountId = getAttendeeIdByAccountId(request.visitId);
    resolveSampleAttendeeIds(request.samples, attendeeIdByAccountId);
    saveProductDetails(request.visitId, request.products);
    saveSamples(request.visitId, request.samples);

    if ('Completed' == request.status) {
      processSampleDistribution(request.visitId, request.samples);
      applyCallReportScore(request.visitId);
    }

    return getCallReportPayload(request.visitId);
  }

  private static void applyCallReportScore(Id visitId) {
    if (!hasObjectField(Visit__c.SObjectType, 'Call_Report_Score__c')) {
      return;
    }
    Decimal score = 0;

    if (visitSampleSchemaReady() && isFieldAccessible(Product2.SObjectType, 'Product_Type__c')) {
      for (SObject sample : Database.query(
        'SELECT Id, Product2__r.Product_Type__c FROM Visit_Sample__c ' +
        'WHERE Visit__c = :visitId WITH SYSTEM_MODE'
      )) {
        String productType = sample.getSObject('Product2__r') == null
          ? null
          : (String) sample.getSObject('Product2__r').get('Product_Type__c');
        if (productType == 'Brand Reminder') {
          score += 2;
        }
      }
    }

    Decimal clmSeconds = 0;
    for (AggregateResult ar : [
      SELECT SUM(Total_Duration_Seconds__c) totalSeconds
      FROM CLM_Presentation_Session__c
      WHERE Visit__c = :visitId AND Status__c = 'Completed'
      WITH SYSTEM_MODE
    ]) {
      Decimal total = (Decimal) ar.get('totalSeconds');
      if (total != null) {
        clmSeconds = total;
      }
    }
    if (clmSeconds > 0) {
      Integer bands = Integer.valueOf(clmSeconds.divide(60, 0, System.RoundingMode.DOWN));
      score += Math.min(5, bands);
    }

    Visit__c scoreUpdate = new Visit__c(Id = visitId);
    scoreUpdate.put('Call_Report_Score__c', score);
    update as system scoreUpdate;
  }

  private static void validateSaveRequest(SaveRequest request, Visit__c visit) {
    VisitStatusHelper.assertTransitionAllowed(
      visit.Status__c,
      request.status,
      visit.Visit_Type__c,
      false
    );
    VisitStatusHelper.validateStatusChange(
      request.status,
      visit.Start_Date__c,
      request.cancellationReason
    );
    if ('Completed' == request.status) {
      if (request.attendees == null || request.attendees.isEmpty()) {
        throw new AuraHandledException('Add at least one attendee before completing the visit.');
      }
      if (request.products == null || request.products.isEmpty()) {
        throw new AuraHandledException('Select at least one product before completing the visit.');
      }
      validateSamples(request.samples);
    }
  }

  private static void validateSamples(List<SampleRow> samples) {
    if (samples == null || samples.isEmpty()) {
      return;
    }
    for (SampleRow row : samples) {
      if (row.productId == null) {
        throw new AuraHandledException('Select a product for each dispense line.');
      }
      if (row.quantity == null || row.quantity <= 0) {
        throw new AuraHandledException('Dispense quantity must be greater than zero.');
      }
    }
    // Inventory / lot tracking is optional — only validate stock when an inventory row is linked.
    Set<Id> inventoryIds = new Set<Id>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId != null) {
        inventoryIds.add(row.sampleInventoryId);
      }
    }
    if (inventoryIds.isEmpty()) {
      return;
    }
    String inventorySoql = 'SELECT Id, Quantity_On_Hand__c, Lot_Number__c';
    Boolean hasExpiry = isFieldAccessible(Sample_Inventory__c.SObjectType, 'Expiry_Date__c');
    if (hasExpiry) {
      inventorySoql += ', Expiry_Date__c';
    }
    inventorySoql += ' FROM Sample_Inventory__c WHERE Id IN :inventoryIds WITH USER_MODE';
    Map<Id, Sample_Inventory__c> inventoryById = new Map<Id, Sample_Inventory__c>(
      (List<Sample_Inventory__c>) Database.query(inventorySoql)
    );
    Map<Id, Decimal> requestedByInventory = new Map<Id, Decimal>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId == null) {
        continue;
      }
      Sample_Inventory__c inv = inventoryById.get(row.sampleInventoryId);
      if (inv == null) {
        throw new AuraHandledException('Sample inventory record not found.');
      }
      if (hasExpiry) {
        Date expiryDate = (Date) inv.get('Expiry_Date__c');
        if (expiryDate != null && expiryDate < Date.today()) {
          throw new AuraHandledException('Cannot distribute expired sample lot ' + inv.Lot_Number__c + '.');
        }
      }
      Decimal total = requestedByInventory.containsKey(row.sampleInventoryId)
        ? requestedByInventory.get(row.sampleInventoryId)
        : 0;
      total += row.quantity;
      requestedByInventory.put(row.sampleInventoryId, total);
      if (total > inv.Quantity_On_Hand__c) {
        throw new AuraHandledException('Insufficient sample inventory for lot ' + inv.Lot_Number__c + '.');
      }
    }
  }

  private static void processSampleDistribution(Id visitId, List<SampleRow> samples) {
    if (samples == null || samples.isEmpty()) {
      return;
    }
    Set<Id> inventoryIds = new Set<Id>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId != null) {
        inventoryIds.add(row.sampleInventoryId);
      }
    }
    if (inventoryIds.isEmpty()) {
      return;
    }

    Map<Id, Sample_Inventory__c> inventoryById = new Map<Id, Sample_Inventory__c>([
      SELECT Id, Quantity_On_Hand__c, Lot_Number__c
      FROM Sample_Inventory__c
      WHERE Id IN :inventoryIds
      WITH USER_MODE
      FOR UPDATE
    ]);

    List<Sample_Transaction__c> transactions = new List<Sample_Transaction__c>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId == null || row.quantity == null) {
        continue;
      }
      Sample_Inventory__c inv = inventoryById.get(row.sampleInventoryId);
      if (inv == null) {
        continue;
      }
      inv.Quantity_On_Hand__c = inv.Quantity_On_Hand__c - row.quantity;
      transactions.add(new Sample_Transaction__c(
        Visit__c = visitId,
        Sample_Inventory__c = inv.Id,
        Quantity__c = row.quantity,
        Transaction_Type__c = 'Distribute'
      ));
    }
    update as user inventoryById.values();
    insert as user transactions;
  }

  private static void rollupLegacyProductFields(Visit__c visit, List<ProductDetailRow> products) {
    if (products == null || products.isEmpty()) {
      visit.Products_Discussed__c = null;
      visit.Product_Details__c = null;
      return;
    }
    List<String> names = new List<String>();
    List<String> notes = new List<String>();
    for (ProductDetailRow row : products) {
      if (String.isNotBlank(row.productName)) {
        names.add(row.productName);
      }
      if (String.isNotBlank(row.notes)) {
        notes.add(row.productName + ': ' + row.notes);
      }
    }
    visit.Products_Discussed__c = String.join(names, '; ');
    visit.Product_Details__c = notes.isEmpty() ? null : String.join(notes, '\n');
  }

  private static Map<Id, Id> getAttendeeIdByAccountId(Id visitId) {
    Map<Id, Id> result = new Map<Id, Id>();
    for (Visit_Attendee__c attendee : [
      SELECT Id, Account__c
      FROM Visit_Attendee__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
    ]) {
      if (attendee.Account__c != null) {
        result.put(attendee.Account__c, attendee.Id);
      }
    }
    return result;
  }

  private static void resolveSampleAttendeeIds(
    List<SampleRow> samples,
    Map<Id, Id> attendeeIdByAccountId
  ) {
    if (samples == null || attendeeIdByAccountId.isEmpty()) {
      return;
    }
    for (SampleRow row : samples) {
      if (row.visitAttendeeId == null) {
        continue;
      }
      if (attendeeIdByAccountId.containsKey(row.visitAttendeeId)) {
        row.visitAttendeeId = attendeeIdByAccountId.get(row.visitAttendeeId);
      }
    }
  }

  private static void saveAttendees(Id visitId, List<AttendeeRow> rows) {
    Map<Id, Visit_Attendee__c> existing = new Map<Id, Visit_Attendee__c>([
      SELECT Id FROM Visit_Attendee__c WHERE Visit__c = :visitId WITH USER_MODE
    ]);
    Set<Id> keepIds = new Set<Id>();
    List<Visit_Attendee__c> toInsert = new List<Visit_Attendee__c>();
    List<Visit_Attendee__c> toUpdate = new List<Visit_Attendee__c>();
    Set<Id> attendeeAccountIds = new Set<Id>();

    if (rows != null) {
      for (AttendeeRow row : rows) {
        if (row.accountId == null) {
          continue;
        }
        attendeeAccountIds.add(row.accountId);

        // Visit__c is Master-Detail (not reparentable) — set only on insert.
        if (row.id != null && existing.containsKey(row.id)) {
          Visit_Attendee__c record = new Visit_Attendee__c(
            Id = row.id,
            Account__c = row.accountId
          );
          keepIds.add(row.id);
          toUpdate.add(record);
        } else {
          toInsert.add(
            new Visit_Attendee__c(
              Visit__c = visitId,
              Account__c = row.accountId
            )
          );
        }
      }
    }

    List<Visit_Attendee__c> toDelete = new List<Visit_Attendee__c>();
    for (Visit_Attendee__c record : existing.values()) {
      if (!keepIds.contains(record.Id)) {
        toDelete.add(record);
      }
    }
    if (!toDelete.isEmpty()) {
      delete as user toDelete;
    }
    if (!toInsert.isEmpty()) {
      insert as user toInsert;
    }
    if (!toUpdate.isEmpty()) {
      update as user toUpdate;
    }

    strengthenAffiliationsForAttendees(visitId, attendeeAccountIds);
  }

  private static void strengthenAffiliationsForAttendees(Id visitId, Set<Id> attendeeAccountIds) {
    if (visitId == null || attendeeAccountIds == null || attendeeAccountIds.isEmpty()) {
      return;
    }
    List<Visit__c> visits = [
      SELECT Id, Account__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty() || visits[0].Account__c == null) {
      return;
    }
    AccountAffiliationStrengthService.strengthenVisitAttendees(
      visits[0].Account__c,
      attendeeAccountIds
    );
  }

  private static void saveProductDetails(Id visitId, List<ProductDetailRow> rows) {
    if (!visitDetailSchemaReady()) {
      return;
    }
    Map<Id, Visit_Product_Detail__c> existingDetails = new Map<Id, Visit_Product_Detail__c>([
      SELECT Id FROM Visit_Product_Detail__c WHERE Visit__c = :visitId WITH USER_MODE
    ]);
    Set<Id> keepDetailIds = new Set<Id>();
    List<Visit_Product_Detail__c> detailUpserts = new List<Visit_Product_Detail__c>();

    if (rows != null) {
      Integer order = 1;
      for (ProductDetailRow row : rows) {
        Visit_Product_Detail__c detail = new Visit_Product_Detail__c();
        if (row.id != null && existingDetails.containsKey(row.id)) {
          detail.Id = row.id;
          keepDetailIds.add(row.id);
        } else {
          detail.put('Visit__c', visitId);
        }
        detail.put('Product2__c', row.productId);
        detail.put('Display_Order__c', row.displayOrder != null ? row.displayOrder : order);
        detail.put('Detail_Type__c', String.isBlank(row.detailType) ? 'Detail' : row.detailType);
        detail.put('Notes__c', row.notes);
        detailUpserts.add(detail);
        order++;
      }
    }

    List<Visit_Product_Detail__c> detailsToDelete = new List<Visit_Product_Detail__c>();
    for (Visit_Product_Detail__c detail : existingDetails.values()) {
      if (!keepDetailIds.contains(detail.Id)) {
        detailsToDelete.add(detail);
      }
    }
    if (!detailsToDelete.isEmpty()) {
      delete as user detailsToDelete;
    }
    if (!detailUpserts.isEmpty()) {
      upsert as user detailUpserts;
    }

    if (!visitMessageSchemaReady()) {
      return;
    }

    Map<Integer, Id> detailIdByOrder = new Map<Integer, Id>();
    for (SObject saved : Database.query(buildProductDetailOrderQuery(visitId))) {
      Object orderValue = saved.get('Display_Order__c');
      if (orderValue == null) {
        continue;
      }
      detailIdByOrder.put(Integer.valueOf(String.valueOf(orderValue)), (Id) saved.get('Id'));
    }

    Map<Id, Visit_Product_Message__c> existingMessages = new Map<Id, Visit_Product_Message__c>();
    for (Visit_Product_Message__c msg : [
      SELECT Id, Visit_Product_Detail__c
      FROM Visit_Product_Message__c
      WHERE Visit_Product_Detail__r.Visit__c = :visitId
      WITH USER_MODE
    ]) {
      existingMessages.put(msg.Id, msg);
    }
    Set<Id> keepMessageIds = new Set<Id>();
    List<Visit_Product_Message__c> messageUpserts = new List<Visit_Product_Message__c>();

    if (rows != null) {
      Integer order = 1;
      for (ProductDetailRow row : rows) {
        Id detailId = row.id;
        if (detailId == null && detailIdByOrder.containsKey(order)) {
          detailId = detailIdByOrder.get(order);
        }
        if (detailId == null || row.messages == null) {
          order++;
          continue;
        }
        for (ProductMessageRow msgRow : row.messages) {
          if (String.isBlank(msgRow.topic)) {
            continue;
          }
          Visit_Product_Message__c msg = new Visit_Product_Message__c();
          if (msgRow.id != null && existingMessages.containsKey(msgRow.id)) {
            msg.Id = msgRow.id;
            keepMessageIds.add(msgRow.id);
          } else {
            msg.put('Visit_Product_Detail__c', detailId);
          }
          msg.put('Topic__c', msgRow.topic);
          msg.put('Sentiment__c', String.isBlank(msgRow.sentiment) ? 'Neutral' : msgRow.sentiment);
          msg.put('Response__c', msgRow.response);
          messageUpserts.add(msg);
        }
        order++;
      }
    }

    List<Visit_Product_Message__c> messagesToDelete = new List<Visit_Product_Message__c>();
    for (Visit_Product_Message__c msg : existingMessages.values()) {
      if (!keepMessageIds.contains(msg.Id)) {
        messagesToDelete.add(msg);
      }
    }
    if (!messagesToDelete.isEmpty()) {
      delete as user messagesToDelete;
    }
    if (!messageUpserts.isEmpty()) {
      upsert as user messageUpserts;
    }
  }

  private static void saveSamples(Id visitId, List<SampleRow> rows) {
    if (!visitSampleSchemaReady()) {
      return;
    }
    Map<Id, Visit_Sample__c> existing = new Map<Id, Visit_Sample__c>([
      SELECT Id FROM Visit_Sample__c WHERE Visit__c = :visitId WITH USER_MODE
    ]);
    Set<Id> keepIds = new Set<Id>();
    List<Visit_Sample__c> toUpsert = new List<Visit_Sample__c>();

    if (rows != null) {
      for (SampleRow row : rows) {
        Visit_Sample__c record = new Visit_Sample__c();
        if (row.id != null && existing.containsKey(row.id)) {
          record.Id = row.id;
          keepIds.add(row.id);
        } else {
          record.put('Visit__c', visitId);
        }
        record.put('Product2__c', row.productId);
        record.put('Visit_Attendee__c', row.visitAttendeeId);
        record.put('Quantity__c', row.quantity);
        record.put('Lot_Number__c', row.lotNumber);
        record.put('Sample_Inventory__c', row.sampleInventoryId);
        toUpsert.add(record);
      }
    }

    List<Visit_Sample__c> toDelete = new List<Visit_Sample__c>();
    for (Visit_Sample__c record : existing.values()) {
      if (!keepIds.contains(record.Id)) {
        toDelete.add(record);
      }
    }
    if (!toDelete.isEmpty()) {
      delete as user toDelete;
    }
    if (!toUpsert.isEmpty()) {
      upsert as user toUpsert;
    }
  }

  private static Visit__c queryVisit(Id visitId) {
    List<String> selectFields = new List<String>{
      'Id',
      'Name',
      'Status__c',
      'Visit_Type__c',
      'Start_Date__c',
      'End_Date__c',
      'Visit_Objective__c',
      'Visit_Notes__c',
      'Products_Discussed__c',
      'Product_Details__c',
      'CLM_Presentation__c',
      'Next_Visit_Date__c',
      'Cancellation_Reason__c',
      'Is_Double_Visit__c',
      'Account__c',
      'Account__r.Name',
      'Account__r.BillingCity',
      'Assigned_To__r.Name'
    };
    if (isFieldAccessible(Account.SObjectType, 'Specialty_1__c')) {
      selectFields.add('Account__r.Specialty_1__c');
    }
    if (isFieldAccessible(Account.SObjectType, 'RecordTypeId')) {
      selectFields.add('Account__r.RecordType.Name');
      selectFields.add('Account__r.RecordType.DeveloperName');
    }
    if (isFieldAccessible(Visit__c.SObjectType, 'Coaching_Event__c')) {
      selectFields.add('Coaching_Event__c');
    }

    String soql =
      'SELECT ' +
      String.join(selectFields, ', ') +
      ' FROM Visit__c WHERE Id = :visitId WITH USER_MODE LIMIT 1';

    List<Visit__c> visits = Database.query(soql);
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    return visits[0];
  }

  private static VisitHeader mapVisitHeader(Visit__c visit) {
    VisitHeader header = new VisitHeader();
    header.id = visit.Id;
    header.name = visit.Name;
    header.status = visit.Status__c;
    header.visitType = visit.Visit_Type__c;
    header.startDateTime = visit.Start_Date__c;
    header.endDateTime = visit.End_Date__c;
    header.durationLabel = formatDurationLabel(visit.Start_Date__c, visit.End_Date__c);
    header.visitObjective = visit.Visit_Objective__c;
    header.visitNotes = visit.Visit_Notes__c;
    header.clmPresentation = visit.CLM_Presentation__c;
    header.nextVisitDate = visit.Next_Visit_Date__c;
    header.cancellationReason = visit.Cancellation_Reason__c;
    header.isLocked =
      (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') &&
      !FeatureManagement.checkPermission('Amend_Completed_Visits');
    header.isDoubleVisit = visit.Is_Double_Visit__c == true;
    header.coachingEventId = isFieldAccessible(Visit__c.SObjectType, 'Coaching_Event__c')
      ? (Id) visit.get('Coaching_Event__c')
      : null;
    header.accountId = visit.Account__c;
    if (visit.Account__r != null) {
      header.accountName = visit.Account__r.Name;
      header.accountCity = visit.Account__r.BillingCity;
      if (isFieldAccessible(Account.SObjectType, 'Specialty_1__c')) {
        header.accountSpecialty = MedicalSpecialtyPicklist.getLabel(
          (String) visit.Account__r.get('Specialty_1__c')
        );
      }
      header.accountRecordTypeName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.Name
        : null;
      header.accountRecordTypeDeveloperName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.DeveloperName
        : null;
    }
    header.assignedToName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
    return header;
  }

  private static List<AttendeeRow> queryAttendees(Id visitId) {
    List<AttendeeRow> rows = new List<AttendeeRow>();
    Integer order = 0;
    List<String> selectFields = new List<String>{
      'Id',
      'Account__c',
      'Account__r.Name'
    };
    if (isFieldAccessible(Account.SObjectType, 'Specialty_1__c')) {
      selectFields.add('Account__r.Specialty_1__c');
    }
    if (isFieldAccessible(Account.SObjectType, 'RecordTypeId')) {
      selectFields.add('Account__r.RecordType.DeveloperName');
    }
    String soql =
      'SELECT ' +
      String.join(selectFields, ', ') +
      ' FROM Visit_Attendee__c WHERE Visit__c = :visitId WITH USER_MODE ORDER BY CreatedDate ASC';
    for (Visit_Attendee__c record : Database.query(soql)) {
      order++;
      AttendeeRow row = new AttendeeRow();
      row.id = record.Id;
      row.accountId = record.Account__c;
      row.accountName = record.Account__r != null ? record.Account__r.Name : null;
      row.specialty = record.Account__r != null && isFieldAccessible(Account.SObjectType, 'Specialty_1__c')
        ? MedicalSpecialtyPicklist.getLabel((String) record.Account__r.get('Specialty_1__c'))
        : null;
      row.recordTypeDeveloperName = record.Account__r != null &&
        record.Account__r.RecordType != null
        ? record.Account__r.RecordType.DeveloperName
        : null;
      row.accountTypeLabel = resolveAccountTypeLabel(row.recordTypeDeveloperName);
      row.role = 'Attendee';
      row.isPrimary = order == 1;
      row.displayOrder = order;
      rows.add(row);
    }
    return rows;
  }

  private static List<ProductDetailRow> queryProductDetails(Id visitId) {
    if (!visitDetailSchemaReady()) {
      return new List<ProductDetailRow>();
    }
    List<ProductDetailRow> rows = new List<ProductDetailRow>();
    Map<Id, ProductDetailRow> rowByDetailId = new Map<Id, ProductDetailRow>();

    List<SObject> detailRecords;
    try {
      detailRecords = Database.query(buildProductDetailQuery(visitId));
    } catch (QueryException e) {
      return rows;
    }

    for (SObject detail : detailRecords) {
      ProductDetailRow row = new ProductDetailRow();
      row.id = (Id) detail.get('Id');
      row.productId = (Id) detail.get('Product2__c');
      SObject product = detail.getSObject('Product2__r');
      row.productName = product != null ? (String) product.get('Name') : null;
      row.imageUrl = product != null ? getProductImageUrl((Product2) product) : null;
      applyProductHierarchyFields(row, product);
      Object displayOrder = detail.get('Display_Order__c');
      row.displayOrder = displayOrder != null ? Integer.valueOf(String.valueOf(displayOrder)) : null;
      row.detailType = (String) detail.get('Detail_Type__c');
      row.notes = (String) detail.get('Notes__c');
      row.messages = new List<ProductMessageRow>();
      rows.add(row);
      rowByDetailId.put(row.id, row);
    }

    if (!visitMessageSchemaReady()) {
      return rows;
    }

    List<SObject> messageRecords;
    try {
      messageRecords = Database.query(buildProductMessageQuery(visitId));
    } catch (QueryException e) {
      return rows;
    }

    for (SObject msg : messageRecords) {
      Id detailId = (Id) msg.get('Visit_Product_Detail__c');
      if (!rowByDetailId.containsKey(detailId)) {
        continue;
      }
      ProductMessageRow msgRow = new ProductMessageRow();
      msgRow.id = (Id) msg.get('Id');
      msgRow.topic = (String) msg.get('Topic__c');
      msgRow.sentiment = (String) msg.get('Sentiment__c');
      msgRow.response = (String) msg.get('Response__c');
      rowByDetailId.get(detailId).messages.add(msgRow);
    }
    return rows;
  }

  private static List<SampleRow> querySamples(Id visitId) {
    if (!visitSampleSchemaReady()) {
      return new List<SampleRow>();
    }
    List<SampleRow> rows = new List<SampleRow>();
    List<SObject> sampleRecords;
    try {
      sampleRecords = Database.query(buildSampleQuery(visitId));
    } catch (QueryException e) {
      return rows;
    }
    for (SObject record : sampleRecords) {
      SampleRow row = new SampleRow();
      row.id = (Id) record.get('Id');
      row.productId = (Id) record.get('Product2__c');
      SObject product = record.getSObject('Product2__r');
      row.productName = product != null ? (String) product.get('Name') : null;
      row.imageUrl = product != null ? getProductImageUrl((Product2) product) : null;
      row.visitAttendeeId = (Id) record.get('Visit_Attendee__c');
      SObject attendee = record.getSObject('Visit_Attendee__r');
      SObject attendeeAccount = attendee != null ? attendee.getSObject('Account__r') : null;
      row.attendeeName = attendeeAccount != null ? (String) attendeeAccount.get('Name') : null;
      row.quantity = (Decimal) record.get('Quantity__c');
      row.lotNumber = (String) record.get('Lot_Number__c');
      row.sampleInventoryId = (Id) record.get('Sample_Inventory__c');
      SObject inventory = record.getSObject('Sample_Inventory__r');
      row.inventoryOnHand = inventory != null ? (Decimal) inventory.get('Quantity_On_Hand__c') : null;
      row.inventoryExpiry = inventory != null ? (Date) inventory.get('Expiry_Date__c') : null;
      rows.add(row);
    }
    return rows;
  }

  private static List<ClmSessionRow> queryClmSessions(Id visitId) {
    List<ClmSessionRow> rows = new List<ClmSessionRow>();
    for (CLM_Presentation_Session__c session : [
      SELECT
        Id,
        CLM_Presentation__c,
        CLM_Presentation__r.Name,
        Status__c,
        Started_At__c,
        Ended_At__c,
        Slides_Presented_Count__c,
        Total_Duration_Seconds__c
      FROM CLM_Presentation_Session__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
      ORDER BY Started_At__c DESC NULLS LAST
    ]) {
      ClmSessionRow row = new ClmSessionRow();
      row.id = session.Id;
      row.presentationId = session.CLM_Presentation__c;
      row.presentationName = session.CLM_Presentation__r != null
        ? session.CLM_Presentation__r.Name
        : null;
      row.status = session.Status__c;
      row.startedAt = session.Started_At__c;
      row.endedAt = session.Ended_At__c;
      row.slidesPresentedCount = session.Slides_Presented_Count__c != null
        ? Integer.valueOf(session.Slides_Presented_Count__c)
        : null;
      row.totalDurationSeconds = session.Total_Duration_Seconds__c != null
        ? Integer.valueOf(session.Total_Duration_Seconds__c)
        : null;
      rows.add(row);
    }
    return rows;
  }

  private static AttendeeRow buildPrimaryAttendeeFromVisit(Visit__c visit) {
    AttendeeRow row = new AttendeeRow();
    row.accountId = visit.Account__c;
    row.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
    row.specialty = visit.Account__r != null && isFieldAccessible(Account.SObjectType, 'Specialty_1__c')
      ? MedicalSpecialtyPicklist.getLabel((String) visit.Account__r.get('Specialty_1__c'))
      : null;
    row.recordTypeDeveloperName = visit.Account__r != null &&
      visit.Account__r.RecordType != null
      ? visit.Account__r.RecordType.DeveloperName
      : null;
    row.accountTypeLabel = resolveAccountTypeLabel(row.recordTypeDeveloperName);
    row.role = 'Attendee';
    row.isPrimary = true;
    row.displayOrder = 1;
    return row;
  }

  private static List<ProductDetailRow> migrateLegacyProducts(Visit__c visit) {
    List<ProductDetailRow> rows = new List<ProductDetailRow>();
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    Set<Id> ptaProductIds = getPtaProductIds(territoryIds);
    Set<Id> scopedIds = intersectWithAtpf(visit.Account__c, territoryIds, ptaProductIds);
    if (scopedIds.isEmpty()) {
      scopedIds = ptaProductIds;
    }

    Map<String, Product2> productByName = new Map<String, Product2>();
    if (!scopedIds.isEmpty()) {
      for (Product2 product : queryProductsByIds(scopedIds)) {
        productByName.put(product.Name.toLowerCase(), product);
      }
    }

    Integer order = 1;
    for (String token : visit.Products_Discussed__c.split(';')) {
      String name = token != null ? token.trim() : null;
      if (String.isBlank(name)) {
        continue;
      }
      ProductDetailRow row = new ProductDetailRow();
      row.productName = name;
      row.displayOrder = order;
      row.detailType = 'Detail';
      row.messages = new List<ProductMessageRow>();
      if (productByName.containsKey(name.toLowerCase())) {
        Product2 matchedProduct = productByName.get(name.toLowerCase());
        row.productId = matchedProduct.Id;
        row.imageUrl = getProductImageUrl(matchedProduct);
      }
      rows.add(row);
      order++;
    }
    return rows;
  }

  private static Set<Id> getPtaProductIds(Set<Id> territoryIds) {
    Set<Id> productIds = new Set<Id>();
    if (territoryIds.isEmpty()) {
      return productIds;
    }
    Date today = Date.today();
    for (Product_Territory_Alignment__c alignment : [
      SELECT Product2_Id__c
      FROM Product_Territory_Alignment__c
      WHERE
        Territory2_Id__c IN :territoryIds
        AND Product2_Id__c != NULL
        AND Is_Active__c = TRUE
        AND (Effective_Start_Date__c = NULL OR Effective_Start_Date__c <= :today)
        AND (Effective_End_Date__c = NULL OR Effective_End_Date__c >= :today)
      WITH USER_MODE
    ]) {
      try {
        productIds.add((Id) alignment.Product2_Id__c);
      } catch (Exception ex) {
        // Skip invalid ids.
      }
    }
    return productIds;
  }

  private static Set<Id> intersectWithAtpf(
    Id accountId,
    Set<Id> territoryIds,
    Set<Id> ptaProductIds
  ) {
    if (accountId == null || territoryIds.isEmpty() || ptaProductIds.isEmpty()) {
      return new Set<Id>();
    }
    Set<String> territoryKeys = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryKeys.add(String.valueOf(territoryId));
    }
    Set<Id> atpfProductIds = new Set<Id>();
    for (Account_Territory_Product_Fields__c atpf : [
      SELECT Product2_Id__c
      FROM Account_Territory_Product_Fields__c
      WHERE
        Account__c = :accountId
        AND Territory2_Id__c IN :territoryKeys
        AND Is_Active__c = TRUE
        AND Product2_Id__c != NULL
      WITH USER_MODE
    ]) {
      try {
        Id productId = (Id) atpf.Product2_Id__c;
        if (ptaProductIds.contains(productId)) {
          atpfProductIds.add(productId);
        }
      } catch (Exception ex) {
        // Skip invalid ids.
      }
    }
    return atpfProductIds.isEmpty() ? ptaProductIds : atpfProductIds;
  }

  private static Map<Id, Account_Territory_Product_Fields__c> getAtpfByProduct(
    Id accountId,
    Set<Id> territoryIds,
    Set<Id> productIds
  ) {
    Map<Id, Account_Territory_Product_Fields__c> result = new Map<Id, Account_Territory_Product_Fields__c>();
    if (accountId == null || territoryIds.isEmpty() || productIds.isEmpty()) {
      return result;
    }
    Set<String> territoryKeys = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryKeys.add(String.valueOf(territoryId));
    }
    Set<String> productKeys = new Set<String>();
    for (Id productId : productIds) {
      productKeys.add(String.valueOf(productId));
    }
    for (Account_Territory_Product_Fields__c atpf : [
      SELECT Product2_Id__c, Adoption__c, Loyalty__c, Product_Matrix_Rating__c, Target_Visit_Frequency__c, Rx_Per_Week__c
      FROM Account_Territory_Product_Fields__c
      WHERE
        Account__c = :accountId
        AND Territory2_Id__c IN :territoryKeys
        AND Product2_Id__c IN :productKeys
        AND Is_Active__c = TRUE
      WITH USER_MODE
    ]) {
      try {
        result.put((Id) atpf.Product2_Id__c, atpf);
      } catch (Exception ex) {
        // Skip invalid ids.
      }
    }
    return result;
  }

  private static List<TerritoryProductOption> fallbackActiveProducts() {
    List<TerritoryProductOption> options = new List<TerritoryProductOption>();
    for (Product2 product : queryActiveProducts(50)) {
      options.add(mapTerritoryProductOption(product));
    }
    return options;
  }

  private static TerritoryProductOption mapTerritoryProductOption(Product2 product) {
    TerritoryProductOption option = new TerritoryProductOption();
    option.productId = product.Id;
    option.productName = product.Name;
    option.imageUrl = getProductImageUrl(product);
    applyProductHierarchyFields(option, product);
    return option;
  }

  private static void applyProductHierarchyFields(TerritoryProductOption option, Product2 product) {
    if (option == null || product == null) {
      return;
    }
    if (isFieldAccessible(Product2.SObjectType, 'Product_Type__c')) {
      option.productType = (String) product.get('Product_Type__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Parent_Product__c')) {
      option.parentProductId = (Id) product.get('Parent_Product__c');
      SObject parent = product.getSObject('Parent_Product__r');
      if (parent != null) {
        option.brandName = (String) parent.get('Name');
      }
    }
    if (String.isBlank(option.brandName) && isFieldAccessible(Product2.SObjectType, 'Primary_Brand__c')) {
      option.brandName = (String) product.get('Primary_Brand__c');
    }
    if (String.isBlank(option.brandName)) {
      option.brandName = product.Name;
    }
    if (isFieldAccessible(Product2.SObjectType, 'Strength__c')) {
      option.strength = (String) product.get('Strength__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Form__c')) {
      option.form = (String) product.get('Form__c');
    }
  }

  private static void applyProductHierarchyFields(ProductDetailRow row, SObject product) {
    if (row == null || product == null) {
      return;
    }
    if (isFieldAccessible(Product2.SObjectType, 'Product_Type__c')) {
      row.productType = (String) product.get('Product_Type__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Parent_Product__c')) {
      row.parentProductId = (Id) product.get('Parent_Product__c');
      SObject parent = product.getSObject('Parent_Product__r');
      if (parent != null) {
        row.brandName = (String) parent.get('Name');
      }
    }
    if (String.isBlank(row.brandName) && isFieldAccessible(Product2.SObjectType, 'Primary_Brand__c')) {
      row.brandName = (String) product.get('Primary_Brand__c');
    }
    if (String.isBlank(row.brandName)) {
      row.brandName = (String) product.get('Name');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Strength__c')) {
      row.strength = (String) product.get('Strength__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Form__c')) {
      row.form = (String) product.get('Form__c');
    }
  }

  private static String buildProductHierarchySelect(String alias) {
    String prefix = String.isBlank(alias) ? '' : alias + '.';
    List<String> fields = new List<String>();
    if (isFieldAccessible(Product2.SObjectType, 'Product_Type__c')) {
      fields.add(prefix + 'Product_Type__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Parent_Product__c')) {
      fields.add(prefix + 'Parent_Product__c');
      fields.add(prefix + 'Parent_Product__r.Name');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Primary_Brand__c')) {
      fields.add(prefix + 'Primary_Brand__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Strength__c')) {
      fields.add(prefix + 'Strength__c');
    }
    if (isFieldAccessible(Product2.SObjectType, 'Form__c')) {
      fields.add(prefix + 'Form__c');
    }
    return fields.isEmpty() ? '' : ', ' + String.join(fields, ', ');
  }

  private static Set<Id> getExistingAttendeeAccountIds(Id visitId) {
    Set<Id> ids = new Set<Id>();
    for (Visit_Attendee__c record : [
      SELECT Account__c FROM Visit_Attendee__c WHERE Visit__c = :visitId WITH USER_MODE
    ]) {
      if (record.Account__c != null) {
        ids.add(record.Account__c);
      }
    }
    return ids;
  }

  private static AttendeeCandidate mapAttendeeCandidate(Account accountRecord, String source) {
    AttendeeCandidate candidate = new AttendeeCandidate();
    candidate.accountId = accountRecord.Id;
    candidate.accountName = accountRecord.Name;
    candidate.specialty = isFieldAccessible(Schema.Account.SObjectType, 'Specialty_1__c')
      ? MedicalSpecialtyPicklist.getLabel((String) accountRecord.get('Specialty_1__c'))
      : null;
    candidate.recordTypeDeveloperName = accountRecord.RecordType != null
      ? accountRecord.RecordType.DeveloperName
      : null;
    candidate.accountTypeLabel = resolveAccountTypeLabel(candidate.recordTypeDeveloperName);
    candidate.source = source;
    return candidate;
  }

  private static String resolveAccountTypeLabel(String developerName) {
    if (HCP_RECORD_TYPES.contains(developerName)) {
      return 'HCP';
    }
    if (developerName == 'Institution_HCO') {
      return 'HCO';
    }
    return 'Account';
  }

  private static String formatDurationLabel(DateTime startDateTime, DateTime endDateTime) {
    if (startDateTime == null || endDateTime == null) {
      return null;
    }
    Long minutes = (endDateTime.getTime() - startDateTime.getTime()) / (1000 * 60);
    if (minutes < 60) {
      return minutes + ' min';
    }
    Long hours = minutes / 60;
    Long remainder = Math.mod(minutes, 60);
    return remainder == 0 ? hours + ' hr' : hours + ' hr ' + remainder + ' min';
  }

  private static Set<Id> getUserTerritoryIds() {
    Set<Id> territoryIds = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId()
      WITH USER_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    return territoryIds;
  }

  private static Set<Id> expandTerritoryHierarchy(Set<Id> seedTerritoryIds) {
    Set<Id> allTerritoryIds = new Set<Id>(seedTerritoryIds);
    Boolean addedChildren = true;
    while (addedChildren) {
      addedChildren = false;
      List<Territory2> children = [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :allTerritoryIds AND Id NOT IN :allTerritoryIds
        WITH USER_MODE
      ];
      for (Territory2 child : children) {
        allTerritoryIds.add(child.Id);
        addedChildren = true;
      }
    }
    return allTerritoryIds;
  }

  private static Set<Id> getTerritoryAccountIds() {
    return getTerritoryAccountIdsCapped(2000);
  }

  /**
   * Caps ObjectTerritory2Association rows so large territories do not hit the 50k query-row limit.
   */
  private static Set<Id> getTerritoryAccountIdsCapped(Integer maxRows) {
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    if (territoryIds.isEmpty()) {
      return new Set<Id>();
    }
    Integer rowCap = maxRows == null || maxRows <= 0 ? 500 : maxRows;
    Set<Id> accountIds = new Set<Id>();
    for (ObjectTerritory2Association association : [
      SELECT ObjectId
      FROM ObjectTerritory2Association
      WHERE Territory2Id IN :territoryIds
      WITH USER_MODE
      LIMIT :rowCap
    ]) {
      accountIds.add(association.ObjectId);
    }
    return accountIds;
  }

  /**
   * Name-first search: query a small Account page by Name, then keep only those in the user's territory.
   * Avoids loading every territory association into memory.
   */
  private static Set<Id> findTerritoryAccountIdsByName(String likeTerm, Integer candidateCap) {
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    if (territoryIds.isEmpty() || String.isBlank(likeTerm)) {
      return new Set<Id>();
    }
    Integer nameLimit = candidateCap == null || candidateCap <= 0 ? 100 : Math.min(candidateCap, 200);
    List<Account> namedAccounts = Database.query(
      'SELECT Id FROM Account WHERE Name LIKE :likeTerm WITH USER_MODE ORDER BY Name ASC LIMIT :nameLimit'
    );
    if (namedAccounts.isEmpty()) {
      return new Set<Id>();
    }
    Set<Id> namedIds = new Map<Id, Account>(namedAccounts).keySet();
    Set<Id> inTerritory = new Set<Id>();
    for (ObjectTerritory2Association association : [
      SELECT ObjectId
      FROM ObjectTerritory2Association
      WHERE Territory2Id IN :territoryIds AND ObjectId IN :namedIds
      WITH USER_MODE
    ]) {
      inTerritory.add(association.ObjectId);
    }
    return inTerritory;
  }

  private static Boolean hasObjectField(Schema.SObjectType token, String fieldApiName) {
    if (token == null || String.isBlank(fieldApiName)) {
      return false;
    }
    Map<String, Schema.SObjectField> fieldMap = token.getDescribe().fields.getMap();
    return fieldMap.containsKey(fieldApiName) ||
      fieldMap.containsKey(fieldApiName.toLowerCase());
  }

  private static Boolean isFieldAccessible(Schema.SObjectType token, String fieldApiName) {
    if (!hasObjectField(token, fieldApiName)) {
      return false;
    }
    Map<String, Schema.SObjectField> fieldMap = token.getDescribe().fields.getMap();
    Schema.SObjectField fieldToken = fieldMap.containsKey(fieldApiName)
      ? fieldMap.get(fieldApiName)
      : fieldMap.get(fieldApiName.toLowerCase());
    return fieldToken != null && fieldToken.getDescribe().isAccessible();
  }

  private static Boolean isProductImageUrlReadable() {
    if (productImageUrlReadable == null) {
      Map<String, Schema.SObjectField> fieldMap = Product2.SObjectType.getDescribe().fields.getMap();
      Schema.SObjectField imageField = fieldMap.containsKey('Product_Image_URL__c')
        ? fieldMap.get('Product_Image_URL__c')
        : fieldMap.get('product_image_url__c');
      productImageUrlReadable = imageField != null && imageField.getDescribe().isAccessible();
    }
    return productImageUrlReadable;
  }

  private static String getProductImageUrl(Product2 product) {
    return isProductImageUrlReadable() && product != null
      ? (String) product.get('Product_Image_URL__c')
      : null;
  }

  private static List<Product2> queryProductsByIds(Set<Id> productIds) {
    if (productIds == null || productIds.isEmpty()) {
      return new List<Product2>();
    }
    String imageSelect = isProductImageUrlReadable() ? ', Product_Image_URL__c' : '';
    String hierarchySelect = buildProductHierarchySelect(null);
    return Database.query(
      'SELECT Id, Name' +
      imageSelect +
      hierarchySelect +
      ' FROM Product2 WHERE Id IN :productIds AND IsActive = TRUE WITH USER_MODE ORDER BY Name ASC'
    );
  }

  private static List<Product2> queryActiveProducts(Integer rowLimit) {
    Integer resolvedLimit = rowLimit == null || rowLimit <= 0 ? 50 : rowLimit;
    String imageSelect = isProductImageUrlReadable() ? ', Product_Image_URL__c' : '';
    String hierarchySelect = buildProductHierarchySelect(null);
    return Database.query(
      'SELECT Id, Name' +
      imageSelect +
      hierarchySelect +
      ' FROM Product2 WHERE IsActive = TRUE WITH USER_MODE ORDER BY Name ASC LIMIT :resolvedLimit'
    );
  }

  private static Boolean visitDetailSchemaReady() {
    return canQueryVisitProductDetails();
  }

  private static Boolean visitMessageSchemaReady() {
    return visitDetailSchemaReady() && canQueryVisitProductMessages();
  }

  private static Boolean visitSampleSchemaReady() {
    return canQueryVisitSamples();
  }

  private static Boolean canQueryVisitProductDetails() {
    try {
      Database.query(
        'SELECT Id, Product2__c, Display_Order__c, Detail_Type__c, Notes__c ' +
        'FROM Visit_Product_Detail__c LIMIT 0'
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Boolean canQueryVisitProductMessages() {
    try {
      Database.query(
        'SELECT Id, Visit_Product_Detail__c, Topic__c, Sentiment__c, Response__c ' +
        'FROM Visit_Product_Message__c LIMIT 0'
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Boolean canQuerySampleInventory() {
    try {
      String fields = 'Id, Product2__c, Lot_Number__c, Quantity_On_Hand__c';
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
        fields += ', Expiry_Date__c';
      }
      Database.query('SELECT ' + fields + ' FROM Sample_Inventory__c LIMIT 0');
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Boolean canQueryVisitSamples() {
    try {
      String inventorySelect = '';
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Quantity_On_Hand__c')) {
        inventorySelect += ', Sample_Inventory__r.Quantity_On_Hand__c';
      }
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
        inventorySelect += ', Sample_Inventory__r.Expiry_Date__c';
      }
      Database.query(
        'SELECT Id, Product2__c, Quantity__c, Visit_Attendee__c, Lot_Number__c, Sample_Inventory__c' +
        inventorySelect +
        ' FROM Visit_Sample__c LIMIT 0'
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static String buildProductDetailQuery(Id visitId) {
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    String hierarchySelect = buildProductHierarchySelect('Product2__r');
    return 'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      hierarchySelect +
      ', Display_Order__c, Detail_Type__c, Notes__c ' +
      'FROM Visit_Product_Detail__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY Display_Order__c ASC, CreatedDate ASC';
  }

  private static String buildProductDetailOrderQuery(Id visitId) {
    return 'SELECT Id, Display_Order__c FROM Visit_Product_Detail__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE';
  }

  private static String buildProductMessageQuery(Id visitId) {
    return 'SELECT Id, Visit_Product_Detail__c, Topic__c, Sentiment__c, Response__c ' +
      'FROM Visit_Product_Message__c WHERE Visit_Product_Detail__r.Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY CreatedDate ASC';
  }

  private static String buildSampleQuery(Id visitId) {
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    String inventorySelect = '';
    if (hasObjectField(Sample_Inventory__c.SObjectType, 'Quantity_On_Hand__c')) {
      inventorySelect += ', Sample_Inventory__r.Quantity_On_Hand__c';
    }
    if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
      inventorySelect += ', Sample_Inventory__r.Expiry_Date__c';
    }
    return 'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      ', Visit_Attendee__c, Visit_Attendee__r.Account__r.Name, Quantity__c, Lot_Number__c, Sample_Inventory__c' +
      inventorySelect +
      ' FROM Visit_Sample__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY CreatedDate ASC';
  }
}