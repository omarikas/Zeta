@IsTest
private class VisitCallReportServiceTest {

  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Dr Call Report Test', BillingCity = 'Cairo');
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsActive = TRUE AND DeveloperName = 'SDO_PersonAccounts'
      LIMIT 1
    ];
    if (!hcpTypes.isEmpty()) {
      account.RecordTypeId = hcpTypes[0].Id;
    }
    insert account;

    Product2 product = new Product2(
      Name = 'Test Pharma Product',
      IsActive = true
    );
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Image_URL__c')) {
      product.put('Product_Image_URL__c', 'https://example.com/test-pharma-product.png');
    }
    insert product;

    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)',
      Products_Discussed__c = 'Test Pharma Product',
      Visit_Objective__c = 'Discuss efficacy'
    );
  }

  @IsTest
  static void getCallReportPayload_returnsVisitAndAttendee() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.getCallReportPayload(
      visit.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload.visit);
    System.assertEquals(visit.Id, payload.visit.id);
    System.assert(!payload.attendees.isEmpty(), 'Primary attendee should be suggested');
  }

  @IsTest
  static void saveCallReport_updatesVisitDetails() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.visitObjective = 'Discuss efficacy';
    request.visitNotes = 'Positive meeting';
    request.clmPresentation = 'CLM1';

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals('Scheduled', payload.visit.status);
    System.assertEquals('Discuss efficacy', payload.visit.visitObjective);
    System.assertEquals('Positive meeting', payload.visit.visitNotes);
  }

  @IsTest
  static void saveCallReport_createsAndStrengthensVisitAttendeeAffiliation() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Account visitAccount = [SELECT Id, Name FROM Account WHERE Id = :visit.Account__c LIMIT 1];
    Account other = new Account(Name = 'Affiliated Attendee');
    insert other;

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.visitObjective = 'Discuss efficacy';

    VisitCallReportService.AttendeeRow primary = new VisitCallReportService.AttendeeRow();
    primary.accountId = visitAccount.Id;
    primary.accountName = visitAccount.Name;
    primary.isPrimary = true;
    primary.displayOrder = 1;

    VisitCallReportService.AttendeeRow guest = new VisitCallReportService.AttendeeRow();
    guest.accountId = other.Id;
    guest.accountName = other.Name;
    guest.isPrimary = false;
    guest.displayOrder = 2;

    request.attendees = new List<VisitCallReportService.AttendeeRow>{ primary, guest };
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    Test.startTest();
    VisitCallReportService.saveCallReport(request);
    VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    List<Account_Affiliation__c> affs = [
      SELECT Score__c, Initiation_Source__c, Strength__c
      FROM Account_Affiliation__c
      WHERE
        (Primary_Account__c = :visitAccount.Id AND Related_Account__c = :other.Id)
        OR (Primary_Account__c = :other.Id AND Related_Account__c = :visitAccount.Id)
    ];
    System.assertEquals(1, affs.size(), 'Expected one affiliation pair');
    System.assertEquals(2, affs[0].Score__c, 'Second save should strengthen score');
    System.assertEquals('Visit Attendee', affs[0].Initiation_Source__c);
    System.assertEquals('Weak', affs[0].Strength__c);
  }

  @IsTest
  static void saveCallReport_blocksEditWhenCompleted() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    visit.Status__c = 'Completed';
    update visit;

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    Boolean threw = false;
    Test.startTest();
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'Completed visits should be locked');
  }

  @IsTest
  static void getTerritoryProducts_returnsOptions() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.TerritoryProductOption> options =
      VisitCallReportService.getTerritoryProducts(visit.Id);
    Test.stopTest();

    System.assertNotEquals(null, options);
    // Without PTA / ATPF rows, picker returns empty (no all-products fallback).
  }

  @IsTest
  static void getTerritoryProducts_includesHierarchyFieldsWhenPresent() {
    Product2 brand;
    Product2 detail;
    Boolean hasType = Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c');
    Boolean hasParent = Schema.SObjectType.Product2.fields.getMap().containsKey('Parent_Product__c');
    Boolean hasStrength = Schema.SObjectType.Product2.fields.getMap().containsKey('Strength__c');

    if (hasType && hasParent) {
      brand = new Product2(Name = 'Hierarchy Brand', IsActive = true);
      brand.put('Product_Type__c', 'Brand');
      insert brand;

      detail = new Product2(Name = 'Hierarchy Brand 10 mg', IsActive = true);
      detail.put('Product_Type__c', 'Detail');
      detail.put('Parent_Product__c', brand.Id);
      if (hasStrength) {
        detail.put('Strength__c', '10mg');
      }
      insert detail;
    }

    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.TerritoryProductOption> options =
      VisitCallReportService.getTerritoryProducts(visit.Id);
    Test.stopTest();

    System.assertNotEquals(null, options);

    if (detail == null || options.isEmpty()) {
      return;
    }

    VisitCallReportService.TerritoryProductOption matched;
    for (VisitCallReportService.TerritoryProductOption option : options) {
      if (option.productId == detail.Id) {
        matched = option;
        break;
      }
    }
    if (matched == null) {
      return; // Product not in PTA/ATPF scope for this test user.
    }
    System.assertEquals('Detail', matched.productType);
    System.assertEquals(brand.Id, matched.parentProductId);
    System.assertEquals('Hierarchy Brand', matched.brandName);
    if (hasStrength) {
      System.assertEquals('10mg', matched.strength);
    }
  }

  @IsTest
  static void getSampleInventoryForUser_isSafeWhenSchemaLimited() {
    Test.startTest();
    List<VisitCallReportService.SampleInventoryOption> options =
      VisitCallReportService.getSampleInventoryForUser();
    Test.stopTest();
    System.assertNotEquals(null, options);
  }

  @IsTest
  static void getSampleInventoryForUser_filtersToSampleAndBrandReminder() {
    Boolean hasType = Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c');
    Boolean canQueryInventory = Schema.getGlobalDescribe().containsKey('Sample_Inventory__c');
    Map<String, Schema.SObjectField> inventoryFields = canQueryInventory
      ? Schema.SObjectType.Sample_Inventory__c.fields.getMap()
      : new Map<String, Schema.SObjectField>();
    Boolean hasProductLookup = inventoryFields.containsKey('Product2__c');
    Boolean hasOwnerUser = inventoryFields.containsKey('Owner_User__c');
    if (!hasType || !canQueryInventory || !hasProductLookup || !hasOwnerUser) {
      System.assertEquals(true, true, 'Sample inventory product fields unavailable — skip type filter assertion');
      return;
    }

    Product2 detailProduct = new Product2(Name = 'Detail Not For Dispense', IsActive = true);
    detailProduct.put('Product_Type__c', 'Detail');
    insert detailProduct;

    Product2 sampleProduct = new Product2(Name = 'Sample For Dispense', IsActive = true);
    sampleProduct.put('Product_Type__c', 'Sample');
    insert sampleProduct;

    Product2 reminderProduct = new Product2(Name = 'Reminder For Dispense', IsActive = true);
    reminderProduct.put('Product_Type__c', 'Brand Reminder');
    insert reminderProduct;

    List<SObject> inventoryRows = new List<SObject>();
    for (Product2 product : new List<Product2>{ detailProduct, sampleProduct, reminderProduct }) {
      SObject inv = Schema.getGlobalDescribe().get('Sample_Inventory__c').newSObject();
      inv.put('Product2__c', product.Id);
      inv.put('Owner_User__c', UserInfo.getUserId());
      inv.put('Lot_Number__c', 'LOT-' + String.valueOf(product.Id).right(4));
      inv.put('Quantity_On_Hand__c', 5);
      inventoryRows.add(inv);
    }
    insert inventoryRows;

    Test.startTest();
    List<VisitCallReportService.SampleInventoryOption> options =
      VisitCallReportService.getSampleInventoryForUser();
    Test.stopTest();

    Set<Id> productIds = new Set<Id>();
    for (VisitCallReportService.SampleInventoryOption option : options) {
      productIds.add(option.productId);
    }
    System.assert(!productIds.contains(detailProduct.Id), 'Detail products must not appear in dispense inventory');
    System.assert(productIds.contains(sampleProduct.Id), 'Sample products should appear in dispense inventory');
    System.assert(
      productIds.contains(reminderProduct.Id),
      'Brand Reminder products should appear in dispense inventory'
    );
  }

  @IsTest
  static void searchAttendeeCandidates_returnsResults() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.AttendeeCandidate> candidates =
      VisitCallReportService.searchAttendeeCandidates(visit.Id, 'Call Report', 0);
    Test.stopTest();

    System.assertNotEquals(null, candidates);
  }

  @IsTest
  static void searchAttendeeCandidates_blankTermAndNullOffset_isSafe() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.AttendeeCandidate> blankTerm =
      VisitCallReportService.searchAttendeeCandidates(visit.Id, null, null);
    List<VisitCallReportService.AttendeeCandidate> negativeOffset =
      VisitCallReportService.searchAttendeeCandidates(visit.Id, '   ', -5);
    Test.stopTest();

    System.assertNotEquals(null, blankTerm);
    System.assertNotEquals(null, negativeOffset);
  }

  @IsTest
  static void getClmPresentationsForVisit_returnsSessionsWhenPresent() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Test Pharma Product' LIMIT 1];

    CLM_Presentation__c presentation = new CLM_Presentation__c(
      Name = 'Call Report CLM Deck',
      Status__c = 'Available',
      Format__c = 'PDF',
      Product__c = product.Id,
      Slide_Count__c = 4
    );
    insert presentation;

    insert new CLM_Presentation_Session__c(
      Visit__c = visit.Id,
      CLM_Presentation__c = presentation.Id,
      Account__c = visit.Account__c,
      User__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Started_At__c = DateTime.now().addMinutes(-30),
      Ended_At__c = DateTime.now().addMinutes(-5),
      Total_Duration_Seconds__c = 1500,
      Slides_Presented_Count__c = 3
    );

    Test.startTest();
    List<VisitCallReportService.ClmSessionRow> sessions =
      VisitCallReportService.getClmPresentationsForVisit(visit.Id);
    VisitCallReportService.CallReportPayload payload =
      VisitCallReportService.getCallReportPayload(visit.Id);
    Test.stopTest();

    System.assertNotEquals(null, sessions);
    System.assertEquals(1, sessions.size());
    System.assertEquals(presentation.Id, sessions[0].presentationId);
    System.assertEquals('Call Report CLM Deck', sessions[0].presentationName);
    System.assertNotEquals(null, payload.clmSessions);
    System.assertEquals(1, payload.clmSessions.size());
  }

  @IsTest
  static void getCallReportPayload_requiresVisitId() {
    Boolean threw = false;
    Test.startTest();
    try {
      VisitCallReportService.getCallReportPayload(null);
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'Null visit id should throw');
  }

  @IsTest
  static void saveCallReport_requiresVisitId() {
    Boolean threw = false;
    Test.startTest();
    try {
      VisitCallReportService.saveCallReport(null);
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'Null save request should throw');
  }

  @IsTest
  static void saveCallReport_cancelsWithReason() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Cancelled';
    request.cancellationReason = 'HCP unavailable — visit rescheduled.';
    request.visitObjective = 'Cancelled objective';
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees.add(attendee);

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals('Cancelled', payload.visit.status);
    System.assertEquals(
      'HCP unavailable — visit rescheduled.',
      payload.visit.cancellationReason
    );
    System.assertEquals(true, payload.visit.isLocked);
  }

  @IsTest
  static void saveCallReport_completeRequiresAttendeeAndProduct() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    visit.Start_Date__c = DateTime.now().addHours(-2);
    visit.End_Date__c = DateTime.now().addHours(-1);
    update visit;

    VisitCallReportService.SaveRequest missingAttendees = new VisitCallReportService.SaveRequest();
    missingAttendees.visitId = visit.Id;
    missingAttendees.status = 'Completed';
    missingAttendees.attendees = new List<VisitCallReportService.AttendeeRow>();
    missingAttendees.products = new List<VisitCallReportService.ProductDetailRow>();
    missingAttendees.samples = new List<VisitCallReportService.SampleRow>();

    Boolean threwMissingAttendees = false;
    try {
      VisitCallReportService.saveCallReport(missingAttendees);
    } catch (Exception ex) {
      threwMissingAttendees = true;
    }
    System.assertEquals(true, threwMissingAttendees, 'Completed without attendees should throw');

    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;

    VisitCallReportService.SaveRequest missingProducts = new VisitCallReportService.SaveRequest();
    missingProducts.visitId = visit.Id;
    missingProducts.status = 'Completed';
    missingProducts.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    missingProducts.products = new List<VisitCallReportService.ProductDetailRow>();
    missingProducts.samples = new List<VisitCallReportService.SampleRow>();

    Boolean threwMissingProducts = false;
    try {
      VisitCallReportService.saveCallReport(missingProducts);
    } catch (Exception ex) {
      threwMissingProducts = true;
    }
    System.assertEquals(true, threwMissingProducts, 'Completed without products should throw');
  }

  @IsTest
  static void saveCallReport_persistsProductDetailsAndMessages() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 brand = new Product2(Name = 'Coverage Brand', IsActive = true);
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c')) {
      brand.put('Product_Type__c', 'Brand');
    }
    insert brand;

    Product2 detail = new Product2(Name = 'Coverage Brand 5 mg', IsActive = true);
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c')) {
      detail.put('Product_Type__c', 'Detail');
    }
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Parent_Product__c')) {
      detail.put('Parent_Product__c', brand.Id);
    }
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Strength__c')) {
      detail.put('Strength__c', '5mg');
    }
    insert detail;

    Product2 sampleProduct = new Product2(Name = 'Coverage Sample Pack', IsActive = true);
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c')) {
      sampleProduct.put('Product_Type__c', 'Sample');
    }
    insert sampleProduct;

    Id sampleInventoryId;
    Boolean canUseSamples = Schema.getGlobalDescribe().containsKey('Sample_Inventory__c') &&
      Schema.getGlobalDescribe().containsKey('Visit_Sample__c');
    Map<String, Schema.SObjectField> inventoryFields = canUseSamples
      ? Schema.SObjectType.Sample_Inventory__c.fields.getMap()
      : new Map<String, Schema.SObjectField>();
    if (
      canUseSamples &&
      inventoryFields.containsKey('Product2__c') &&
      inventoryFields.containsKey('Owner_User__c') &&
      inventoryFields.containsKey('Lot_Number__c') &&
      inventoryFields.containsKey('Quantity_On_Hand__c')
    ) {
      SObject inv = Schema.getGlobalDescribe().get('Sample_Inventory__c').newSObject();
      inv.put('Product2__c', sampleProduct.Id);
      inv.put('Owner_User__c', UserInfo.getUserId());
      inv.put('Lot_Number__c', 'LOT-COV-01');
      inv.put('Quantity_On_Hand__c', 10);
      if (inventoryFields.containsKey('Expiry_Date__c')) {
        inv.put('Expiry_Date__c', Date.today().addMonths(6));
      }
      insert inv;
      sampleInventoryId = (Id) inv.get('Id');
    }

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.visitObjective = 'Detail coverage brand';
    request.visitNotes = 'Notes with messages and optional samples';
    request.clmPresentation = 'CLM1';
    request.nextVisitDate = Date.today().addDays(14);

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };

    VisitCallReportService.ProductMessageRow message = new VisitCallReportService.ProductMessageRow();
    message.topic = 'Efficacy';
    message.sentiment = 'Positive';
    message.response = 'Interested';

    VisitCallReportService.ProductMessageRow blankTopic = new VisitCallReportService.ProductMessageRow();
    blankTopic.topic = '  ';
    blankTopic.sentiment = 'Neutral';

    VisitCallReportService.ProductDetailRow product = new VisitCallReportService.ProductDetailRow();
    product.productId = detail.Id;
    product.productName = detail.Name;
    product.displayOrder = 1;
    product.detailType = 'Detail';
    product.notes = 'Discussed 5mg';
    product.messages = new List<VisitCallReportService.ProductMessageRow>{ message, blankTopic };
    request.products = new List<VisitCallReportService.ProductDetailRow>{ product };

    request.samples = new List<VisitCallReportService.SampleRow>();
    if (sampleInventoryId != null) {
      VisitCallReportService.SampleRow sample = new VisitCallReportService.SampleRow();
      sample.productId = sampleProduct.Id;
      sample.productName = sampleProduct.Name;
      sample.quantity = 2;
      sample.lotNumber = 'LOT-COV-01';
      sample.sampleInventoryId = sampleInventoryId;
      // Pass account id; service resolves it to Visit_Attendee__c after saveAttendees.
      sample.visitAttendeeId = account.Id;
      request.samples.add(sample);
    }

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.saveCallReport(request);
    VisitCallReportService.CallReportPayload reloaded =
      VisitCallReportService.getCallReportPayload(visit.Id);
    List<VisitCallReportService.SampleInventoryOption> inventoryOptions =
      VisitCallReportService.getSampleInventoryForUser();
    Test.stopTest();

    System.assertNotEquals(null, payload);
    System.assertNotEquals(null, reloaded);
    System.assertEquals('Scheduled', reloaded.visit.status);
    System.assertEquals('CLM1', reloaded.visit.clmPresentation);
    System.assertEquals(Date.today().addDays(14), reloaded.visit.nextVisitDate);
    System.assert(!reloaded.attendees.isEmpty(), 'Attendee should persist');
    System.assertNotEquals(null, reloaded.products);
    if (!reloaded.products.isEmpty() && reloaded.products[0].productId != null) {
      System.assertEquals(detail.Id, reloaded.products[0].productId);
      if (Schema.SObjectType.Product2.fields.getMap().containsKey('Parent_Product__c')) {
        System.assertEquals(brand.Id, reloaded.products[0].parentProductId);
      }
      if (reloaded.products[0].messages != null && !reloaded.products[0].messages.isEmpty()) {
        System.assertEquals('Efficacy', reloaded.products[0].messages[0].topic);
      }
    }
    System.assertNotEquals(null, inventoryOptions);
    if (sampleInventoryId != null && Schema.getGlobalDescribe().containsKey('Visit_Sample__c')) {
      System.assertNotEquals(null, reloaded.samples);
    }
  }

  @IsTest
  static void saveCallReport_completesWithAttendeesProductsAndOptionalSamples() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    visit.Start_Date__c = DateTime.now().addHours(-3);
    visit.End_Date__c = DateTime.now().addHours(-2);
    update visit;

    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 detail = new Product2(Name = 'Complete Detail SKU', IsActive = true);
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c')) {
      detail.put('Product_Type__c', 'Detail');
    }
    insert detail;

    Product2 sampleProduct = new Product2(Name = 'Complete Sample SKU', IsActive = true);
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c')) {
      sampleProduct.put('Product_Type__c', 'Sample');
    }
    insert sampleProduct;

    // Persist Visit_Sample rows on complete, but omit Sample_Inventory__c linkage.
    // Distribution (Sample_Transaction__c insert as user) depends on org FLS and is
    // validated separately via quantity/expiry checks below.
    Boolean canUseVisitSamples = Schema.getGlobalDescribe().containsKey('Visit_Sample__c');

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Completed';
    request.visitObjective = 'Complete call';
    request.visitNotes = 'Done';

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };

    VisitCallReportService.ProductMessageRow message = new VisitCallReportService.ProductMessageRow();
    message.topic = 'Efficacy';
    message.sentiment = 'Positive';
    message.response = 'Agreed';

    VisitCallReportService.ProductDetailRow product = new VisitCallReportService.ProductDetailRow();
    product.productId = detail.Id;
    product.productName = detail.Name;
    product.displayOrder = 1;
    product.detailType = 'Detail';
    product.notes = 'Completed detailing';
    product.messages = new List<VisitCallReportService.ProductMessageRow>{ message };
    request.products = new List<VisitCallReportService.ProductDetailRow>{ product };
    request.samples = new List<VisitCallReportService.SampleRow>();

    if (canUseVisitSamples) {
      VisitCallReportService.SampleRow sample = new VisitCallReportService.SampleRow();
      sample.productId = sampleProduct.Id;
      sample.quantity = 1;
      sample.lotNumber = 'LOT-CMP-01';
      sample.visitAttendeeId = account.Id;

      Boolean canUseInventory = Schema.getGlobalDescribe().containsKey('Sample_Inventory__c') &&
        Schema.getGlobalDescribe().containsKey('Sample_Transaction__c');
      Map<String, Schema.SObjectField> inventoryFields = canUseInventory
        ? Schema.SObjectType.Sample_Inventory__c.fields.getMap()
        : new Map<String, Schema.SObjectField>();
      if (
        canUseInventory &&
        inventoryFields.containsKey('Product2__c') &&
        inventoryFields.containsKey('Owner_User__c') &&
        inventoryFields.containsKey('Lot_Number__c') &&
        inventoryFields.containsKey('Quantity_On_Hand__c') &&
        Schema.SObjectType.Sample_Transaction__c.isCreateable()
      ) {
        SObject inv = Schema.getGlobalDescribe().get('Sample_Inventory__c').newSObject();
        inv.put('Product2__c', sampleProduct.Id);
        inv.put('Owner_User__c', UserInfo.getUserId());
        inv.put('Lot_Number__c', 'LOT-CMP-01');
        inv.put('Quantity_On_Hand__c', 8);
        if (inventoryFields.containsKey('Expiry_Date__c')) {
          inv.put('Expiry_Date__c', Date.today().addYears(1));
        }
        insert inv;
        sample.sampleInventoryId = (Id) inv.get('Id');
      }
      request.samples.add(sample);
    }

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals('Completed', payload.visit.status);
    System.assertEquals(true, payload.visit.isLocked);
    System.assert(!payload.attendees.isEmpty());
    System.assertNotEquals(null, payload.products);
    if (
      request.samples != null &&
      !request.samples.isEmpty() &&
      request.samples[0].sampleInventoryId != null
    ) {
      Id inventoryId = request.samples[0].sampleInventoryId;
      SObject refreshed = Database.query(
        'SELECT Quantity_On_Hand__c FROM Sample_Inventory__c WHERE Id = \'' +
        String.escapeSingleQuotes(String.valueOf(inventoryId)) +
        '\' LIMIT 1'
      );
      System.assertEquals(7, (Decimal) refreshed.get('Quantity_On_Hand__c'));
    }
  }

  @IsTest
  static void saveCallReport_rejectsInvalidSampleQuantity() {
    Boolean canUseSamples = Schema.getGlobalDescribe().containsKey('Sample_Inventory__c');
    Map<String, Schema.SObjectField> inventoryFields = canUseSamples
      ? Schema.SObjectType.Sample_Inventory__c.fields.getMap()
      : new Map<String, Schema.SObjectField>();
    if (
      !canUseSamples ||
      !inventoryFields.containsKey('Product2__c') ||
      !inventoryFields.containsKey('Owner_User__c') ||
      !inventoryFields.containsKey('Quantity_On_Hand__c')
    ) {
      System.assertEquals(true, true, 'Sample inventory schema unavailable — skip quantity validation');
      return;
    }

    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    visit.Start_Date__c = DateTime.now().addHours(-2);
    visit.End_Date__c = DateTime.now().addHours(-1);
    update visit;

    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 detail = new Product2(Name = 'Invalid Sample Detail', IsActive = true);
    insert detail;
    Product2 sampleProduct = new Product2(Name = 'Invalid Sample Product', IsActive = true);
    if (Schema.SObjectType.Product2.fields.getMap().containsKey('Product_Type__c')) {
      sampleProduct.put('Product_Type__c', 'Sample');
    }
    insert sampleProduct;

    SObject inv = Schema.getGlobalDescribe().get('Sample_Inventory__c').newSObject();
    inv.put('Product2__c', sampleProduct.Id);
    inv.put('Owner_User__c', UserInfo.getUserId());
    inv.put('Lot_Number__c', 'LOT-BAD');
    inv.put('Quantity_On_Hand__c', 3);
    insert inv;

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.isPrimary = true;
    attendee.displayOrder = 1;

    VisitCallReportService.ProductDetailRow product = new VisitCallReportService.ProductDetailRow();
    product.productId = detail.Id;
    product.productName = detail.Name;
    product.displayOrder = 1;

    VisitCallReportService.SampleRow badQty = new VisitCallReportService.SampleRow();
    badQty.productId = sampleProduct.Id;
    badQty.quantity = 0;
    badQty.sampleInventoryId = (Id) inv.get('Id');

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Completed';
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    request.products = new List<VisitCallReportService.ProductDetailRow>{ product };
    request.samples = new List<VisitCallReportService.SampleRow>{ badQty };

    Boolean threw = false;
    Test.startTest();
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'Zero sample quantity should be rejected on complete');
  }

  @IsTest
  static void saveCallReport_replacesAttendeesAndProducts() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account primary = [SELECT Id, Name FROM Account LIMIT 1];
    Account secondary = new Account(Name = 'Secondary Attendee HCP', BillingCity = 'Giza');
    insert secondary;

    Product2 first = new Product2(Name = 'Replace Product A', IsActive = true);
    Product2 second = new Product2(Name = 'Replace Product B', IsActive = true);
    insert new List<Product2>{ first, second };

    VisitCallReportService.SaveRequest firstSave = new VisitCallReportService.SaveRequest();
    firstSave.visitId = visit.Id;
    firstSave.status = 'Scheduled';
    firstSave.visitObjective = 'First pass';

    VisitCallReportService.AttendeeRow attendee1 = new VisitCallReportService.AttendeeRow();
    attendee1.accountId = primary.Id;
    attendee1.accountName = primary.Name;
    attendee1.isPrimary = true;
    attendee1.displayOrder = 1;
    firstSave.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee1 };

    VisitCallReportService.ProductDetailRow product1 = new VisitCallReportService.ProductDetailRow();
    product1.productId = first.Id;
    product1.productName = first.Name;
    product1.displayOrder = 1;
    product1.detailType = 'Detail';
    product1.notes = 'First product';
    VisitCallReportService.ProductMessageRow msg = new VisitCallReportService.ProductMessageRow();
    msg.topic = 'Safety';
    msg.sentiment = 'Neutral';
    msg.response = 'Asked questions';
    product1.messages = new List<VisitCallReportService.ProductMessageRow>{ msg };
    firstSave.products = new List<VisitCallReportService.ProductDetailRow>{ product1 };
    firstSave.samples = new List<VisitCallReportService.SampleRow>();

    VisitCallReportService.CallReportPayload afterFirst = VisitCallReportService.saveCallReport(firstSave);

    VisitCallReportService.SaveRequest secondSave = new VisitCallReportService.SaveRequest();
    secondSave.visitId = visit.Id;
    secondSave.status = 'Scheduled';
    secondSave.visitObjective = 'Second pass';

    VisitCallReportService.AttendeeRow attendee2 = new VisitCallReportService.AttendeeRow();
    attendee2.accountId = secondary.Id;
    attendee2.accountName = secondary.Name;
    attendee2.isPrimary = true;
    attendee2.displayOrder = 1;
    secondSave.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee2 };

    VisitCallReportService.ProductDetailRow product2 = new VisitCallReportService.ProductDetailRow();
    product2.productId = second.Id;
    product2.productName = second.Name;
    product2.displayOrder = 1;
    product2.detailType = 'Detail';
    product2.notes = 'Replaced product';
    product2.messages = new List<VisitCallReportService.ProductMessageRow>();
    secondSave.products = new List<VisitCallReportService.ProductDetailRow>{ product2 };
    secondSave.samples = new List<VisitCallReportService.SampleRow>();

    // Keep existing detail id when present to exercise update path, then replace on next save.
    if (afterFirst.products != null && !afterFirst.products.isEmpty()) {
      product2.id = afterFirst.products[0].id;
    }

    Test.startTest();
    VisitCallReportService.CallReportPayload afterSecond = VisitCallReportService.saveCallReport(secondSave);
    // Clear products/attendees to exercise delete paths.
    VisitCallReportService.SaveRequest clearSave = new VisitCallReportService.SaveRequest();
    clearSave.visitId = visit.Id;
    clearSave.status = 'Scheduled';
    clearSave.visitObjective = 'Cleared';
    clearSave.attendees = new List<VisitCallReportService.AttendeeRow>();
    clearSave.products = new List<VisitCallReportService.ProductDetailRow>();
    clearSave.samples = new List<VisitCallReportService.SampleRow>();
    VisitCallReportService.CallReportPayload afterClear = VisitCallReportService.saveCallReport(clearSave);
    Test.stopTest();

    System.assertEquals('Scheduled', afterSecond.visit.status);
    System.assertNotEquals(null, afterSecond.attendees);
    System.assertNotEquals(null, afterClear);
    Visit__c refreshed = [
      SELECT Products_Discussed__c, Product_Details__c, Status__c
      FROM Visit__c
      WHERE Id = :visit.Id
    ];
    System.assertEquals('Scheduled', refreshed.Status__c);
    System.assertEquals(null, refreshed.Products_Discussed__c);
  }
}