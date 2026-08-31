@IsTest
private class AccountVisitInsightsControllerTest {

  private static final String CENTER_LABEL = 'Dr Center HCP';
  private static final String NEIGHBOR_LABEL = 'Dr Nearby HCP';
  private static final String FAR_LABEL = 'Dr Far HCP';

  @TestSetup
  static void setupData() {
    Account center = buildHcpAccount(
      CENTER_LABEL,
      'Cairo',
      '1 Nile St',
      30.0444,
      31.2357
    );
    Account neighbor = buildHcpAccount(
      NEIGHBOR_LABEL,
      'Cairo',
      '2 Nile St',
      30.0450,
      31.2360
    );
    Account farAway = buildHcpAccount(
      FAR_LABEL,
      'Alexandria',
      '99 Corniche',
      31.2001,
      29.9187
    );
    insert new List<Account>{ center, neighbor, farAway };

    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Id employeeId = UserInfo.getUserId();

    Employee_Time_Card__c card = new Employee_Time_Card__c(
      Employee__c = employeeId,
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthEnd,
      Unique_Identifier__c = employeeId + ':' + String.valueOf(monthStart),
      Active_Time_Card__c = true
    );
    Database.insert(card, AccessLevel.SYSTEM_MODE);

    Database.insert(
      new List<Employee_Time_Card_Account_Target__c>{
        new Employee_Time_Card_Account_Target__c(
          Employee_Time_Card__c = card.Id,
          Account__c = center.Id,
          Potentiality__c = 'A',
          Target_Visit_Frequency__c = 4,
          Actual_Visits__c = 1,
          Unique_Key__c = card.Id + ':' + center.Id,
          Rep__c = employeeId
        ),
        new Employee_Time_Card_Account_Target__c(
          Employee_Time_Card__c = card.Id,
          Account__c = neighbor.Id,
          Potentiality__c = 'B',
          Target_Visit_Frequency__c = 2,
          Actual_Visits__c = 0,
          Unique_Key__c = card.Id + ':' + neighbor.Id,
          Rep__c = employeeId
        ),
        new Employee_Time_Card_Account_Target__c(
          Employee_Time_Card__c = card.Id,
          Account__c = farAway.Id,
          Potentiality__c = 'C',
          Target_Visit_Frequency__c = 2,
          Actual_Visits__c = 0,
          Unique_Key__c = card.Id + ':' + farAway.Id,
          Rep__c = employeeId
        )
      },
      AccessLevel.SYSTEM_MODE
    );

    Database.insert(
      new List<Employee_Time_Card_Day_Entry__c>{
        new Employee_Time_Card_Day_Entry__c(
          Employee_Time_Card__c = card.Id,
          Date__c = monthStart,
          Calendar_Working_Days__c = 10
        ),
        new Employee_Time_Card_Day_Entry__c(
          Employee_Time_Card__c = card.Id,
          Date__c = monthStart.addDays(15),
          Calendar_Working_Days__c = 10
        )
      },
      AccessLevel.SYSTEM_MODE
    );

    DateTime futureStart = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(10, 0, 0, 0));
    Database.insert(
      new Visit__c(
        Account__c = center.Id,
        Assigned_To__c = employeeId,
        Start_Date__c = futureStart,
        End_Date__c = futureStart.addHours(1),
        Visit_Date__c = futureStart,
        Status__c = 'Scheduled',
        Visit_Type__c = 'Planned (Automatically)'
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static Account buildHcpAccount(
    String label,
    String city,
    String street,
    Decimal latitude,
    Decimal longitude
  ) {
    Account account = new Account(
      Name = label,
      BillingCity = city,
      BillingStreet = street,
      BillingLatitude = latitude,
      BillingLongitude = longitude
    );
    Id hcpRecordTypeId = getHcpRecordTypeId();
    if (hcpRecordTypeId != null) {
      account.RecordTypeId = hcpRecordTypeId;
    }
    return account;
  }

  private static Id getHcpRecordTypeId() {
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName = 'Medical_Professional_HCP'
      LIMIT 1
    ];
    return hcpTypes.isEmpty() ? null : hcpTypes[0].Id;
  }

  private static Account getCenterAccount() {
    return [
      SELECT Id, Name
      FROM Account
      WHERE BillingLatitude = 30.0444
      LIMIT 1
    ];
  }

  private static Account getNeighborAccount() {
    return [
      SELECT Id, Name
      FROM Account
      WHERE BillingLatitude = 30.0450
      LIMIT 1
    ];
  }

  @IsTest
  static void getAccountVisitContext_returnsPaceAndFutureVisits() {
    Account center = getCenterAccount();

    Test.startTest();
    AccountVisitInsightsController.AccountVisitContext context =
      AccountVisitInsightsController.getAccountVisitContext(center.Id);
    Test.stopTest();

    System.assertEquals(true, context.hasPlanTarget);
    System.assertEquals(true, context.hasGeo);
    System.assertEquals(4, context.targetVisits);
    System.assertEquals(1, context.actualVisits);
    System.assertEquals(1, context.futureVisits.size());
    System.assertEquals(2, context.committedVisits);
    System.assert(context.elapsedWorkingDays >= 0);
    System.assert(context.totalWorkingDays >= context.elapsedWorkingDays);
    System.assert(context.projectedVisits > 0);
    System.assertNotEquals('not_applicable', context.paceStatus);
  }

  @IsTest
  static void getAccountVisitContext_noPlanTarget() {
    Account account = buildHcpAccount('No Plan HCP', 'Cairo', '3 Nile St', 30.0460, 31.2370);
    insert account;

    Test.startTest();
    AccountVisitInsightsController.AccountVisitContext context =
      AccountVisitInsightsController.getAccountVisitContext(account.Id);
    Test.stopTest();

    System.assertEquals(false, context.hasPlanTarget);
  }

  @IsTest
  static void getNearbyPlanTargets_filtersByRadius() {
    Account center = getCenterAccount();

    Test.startTest();
    AccountVisitInsightsController.NearbyPlanTargetsResult nearby =
      AccountVisitInsightsController.getNearbyPlanTargets(center.Id, 10);
    Test.stopTest();

    System.assertEquals(true, nearby.hasGeo);
    System.assert(!nearby.targets.isEmpty());

    Boolean foundCenter = false;
    Boolean foundNeighbor = false;
    Boolean foundFar = false;
    for (AccountVisitInsightsController.NearbyPlanTarget row : nearby.targets) {
      if (row.accountId == center.Id) {
        foundCenter = true;
        System.assertEquals(true, row.isCenterAccount);
      }
      if (row.name == NEIGHBOR_LABEL || (row.name != null && row.name.contains(NEIGHBOR_LABEL))) {
        foundNeighbor = true;
      }
      if (row.name == FAR_LABEL || (row.name != null && row.name.contains(FAR_LABEL))) {
        foundFar = true;
      }
    }
    System.assert(foundCenter, 'Center account should be included');
    System.assert(foundNeighbor, 'Nearby account should be included');
    System.assertEquals(false, foundFar, 'Far account should be excluded by radius');
  }

  @IsTest
  static void getNearbyPlanTargets_expandsRadiusToNearestNeighbor() {
    Account center = getCenterAccount();

    Test.startTest();
    AccountVisitInsightsController.NearbyPlanTargetsResult nearby =
      AccountVisitInsightsController.getNearbyPlanTargets(center.Id, 0.001);
    Test.stopTest();

    Boolean foundNeighbor = false;
    for (AccountVisitInsightsController.NearbyPlanTarget row : nearby.targets) {
      if (!row.isCenterAccount) {
        foundNeighbor = true;
      }
    }
    System.assert(foundNeighbor, 'Expected nearest neighbor when initial radius is too small.');
    System.assert(
      nearby.searchRadiusKm > 0.001,
      'Search radius should expand to include the nearest neighbor.'
    );
  }

  @IsTest
  static void bulkCreateDraftVisits_createsStaggeredDrafts() {
    Account center = getCenterAccount();
    Account neighbor = getNeighborAccount();
    Date visitDate = Date.today().addDays(3);

    Test.startTest();
    List<AccountVisitInsightsController.DraftVisitSummary> created =
      AccountVisitInsightsController.bulkCreateDraftVisits(
        new List<Id>{ center.Id, neighbor.Id },
        visitDate,
        9
      );
    Test.stopTest();

    System.assertEquals(2, created.size());
    System.assertEquals('Draft', [SELECT Status__c FROM Visit__c WHERE Id = :created[0].id].Status__c);
    System.assertEquals(
      visitDate,
      created[0].startDateTime.date()
    );
    System.assertEquals(
      10,
      created[1].startDateTime.hour()
    );
  }

  @IsTest
  static void getNearbyPlanTargets_returnsRecordTypeForCenterAccount() {
    Account center = getCenterAccount();

    Test.startTest();
    AccountVisitInsightsController.NearbyPlanTargetsResult nearby =
      AccountVisitInsightsController.getNearbyPlanTargets(center.Id, 10);
    Test.stopTest();

    AccountVisitInsightsController.NearbyPlanTarget centerRow = null;
    for (AccountVisitInsightsController.NearbyPlanTarget row : nearby.targets) {
      if (row.isCenterAccount) {
        centerRow = row;
        break;
      }
    }

    System.assertNotEquals(null, centerRow, 'Center account should be included');
    System.assertNotEquals(null, centerRow.recordTypeDeveloperName);
    System.assertNotEquals(null, centerRow.recordTypeName);
  }

  @IsTest
  static void getNearbyPlanTargets_includesInstitutionHcoRecordType() {
    Id hcoRecordTypeId = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Institution_HCO'
      LIMIT 1
    ]
    .Id;

    Account hco = new Account(
      Name = 'Dar Al Fouad Nasr City',
      RecordTypeId = hcoRecordTypeId,
      BillingCity = 'Cairo',
      BillingStreet = '4 Nile St',
      BillingLatitude = 30.0448,
      BillingLongitude = 31.2359,
      Institution_Type__c = 'Clinic'
    );
    insert hco;

    Date monthStart = Date.today().toStartOfMonth();
    Id employeeId = UserInfo.getUserId();
    Employee_Time_Card__c card = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE Employee__c = :employeeId AND Time_Card_Month_Start_Date__c = :monthStart
      LIMIT 1
    ];

    Database.insert(
      new Employee_Time_Card_Account_Target__c(
        Employee_Time_Card__c = card.Id,
        Account__c = hco.Id,
        Potentiality__c = 'A',
        Target_Visit_Frequency__c = 3,
        Actual_Visits__c = 0,
        Unique_Key__c = card.Id + ':' + hco.Id,
        Rep__c = employeeId
      ),
      AccessLevel.SYSTEM_MODE
    );

    Test.startTest();
    AccountVisitInsightsController.NearbyPlanTargetsResult nearby =
      AccountVisitInsightsController.getNearbyPlanTargets(hco.Id, 10);
    Test.stopTest();

    AccountVisitInsightsController.NearbyPlanTarget centerRow = null;
    for (AccountVisitInsightsController.NearbyPlanTarget row : nearby.targets) {
      if (row.isCenterAccount) {
        centerRow = row;
        break;
      }
    }

    System.assertNotEquals(null, centerRow, 'Center HCO account should be included');
    System.assertEquals('Institution_HCO', centerRow.recordTypeDeveloperName);
    System.assert(
      centerRow.recordTypeName == 'Institution (HCO)' || centerRow.recordTypeName == 'HCO',
      'Unexpected HCO record type label: ' + centerRow.recordTypeName
    );
  }

  @IsTest
  static void bulkCreateDraftVisits_rejectsPastDate() {
    Account center = getCenterAccount();

    Boolean threw = false;
    Test.startTest();
    try {
      AccountVisitInsightsController.bulkCreateDraftVisits(
        new List<Id>{ center.Id },
        Date.today().addDays(-1),
        9
      );
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }
}