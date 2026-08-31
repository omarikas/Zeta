@IsTest
private class AccountsTabControllerTest {

  private static final String ROLE = 'Medical Rep';

  private static Territory2 testTerritory;
  private static Id timeCardId;

  @TestSetup
  static void setup() {
    Id userId = UserInfo.getUserId();
    testTerritory = getOrCreateTestTerritory('TERR_TEST_ACCOUNTS_TAB');

    if (testTerritory == null) {
      // If territory foundation is missing in this org, fail early.
      System.assert(false, 'Expected Territory2 foundation records to exist.');
    }

    insert new UserTerritory2Association(
      UserId = userId,
      Territory2Id = testTerritory.Id,
      RoleInTerritory2 = ROLE
    );

    assignPermissionSet('Field_Planner_Module');
    assignPermissionSet('Account_Master_Load_Fields');

    User runAsUser = [SELECT Id FROM User WHERE Id = :userId];
    Id recordTypeId = resolveFirstAccountRecordTypeId(new Set<String>{
      'Medical_Professional_HCP',
      'SDO_PersonAccounts',
      'Institution_HCO'
    });

    Account ahead;
    Account onTrack;
    Account behind;
    Account critical;
    Account outOfPlan;
    System.runAs(runAsUser) {
      ahead = buildAccount('Dr Account Ahead', recordTypeId, 30.0444, 31.2357, 'Cairo');
      onTrack = buildAccount('Dr Account On Track', recordTypeId, 30.0450, 31.2360, 'Cairo');
      behind = buildAccount('Dr Account Behind', recordTypeId, 30.0460, 31.2370, 'Cairo');
      critical = buildAccount('Dr Account Critical', recordTypeId, 30.0470, 31.2380, 'Cairo');
      outOfPlan = buildAccount('Dr Account Out Of Plan', recordTypeId, 30.0480, 31.2390, 'Cairo');
      insert new List<Account>{ ahead, onTrack, behind, critical, outOfPlan };

      Date monthStart = Date.today().toStartOfMonth();
      Date monthEnd = monthStart.addMonths(1).addDays(-1);

      Employee_Time_Card__c card = new Employee_Time_Card__c(
        Employee__c = userId,
        Time_Card_Month_Start_Date__c = monthStart,
        Time_Card_Month_End_Date__c = monthEnd,
        Active_Time_Card__c = true,
        Unique_Identifier__c = userId + ':' + String.valueOf(monthStart),
        Territory__c = 'Test Territory'
      );
      Database.insert(card, AccessLevel.SYSTEM_MODE);
      timeCardId = card.Id;

      Database.insert(
        new Employee_Time_Card_Day_Entry__c(
          Employee_Time_Card__c = timeCardId,
          Date__c = monthStart,
          Calendar_Working_Days__c = 10
        ),
        AccessLevel.SYSTEM_MODE
      );

      Database.insert(
        new List<Account_Territory_Fields__c>{
          buildAtf(ahead.Id, testTerritory.Id, 'A', 'A1', '1', true, false),
          buildAtf(onTrack.Id, testTerritory.Id, 'B', 'B2', '2', true, false),
          buildAtf(behind.Id, testTerritory.Id, 'C', 'C3', '3', true, false),
          buildAtf(critical.Id, testTerritory.Id, 'B', 'B1', '3', true, false),
          buildAtf(outOfPlan.Id, testTerritory.Id, 'C', 'C2', '3', true, false)
        },
        AccessLevel.SYSTEM_MODE
      );

      Decimal target = 10;
      Database.insert(
        new List<Employee_Time_Card_Account_Target__c>{
          buildTarget(timeCardId, ahead.Id, target, 10, 'A'),
          buildTarget(timeCardId, onTrack.Id, target, 9, 'B'),
          buildTarget(timeCardId, behind.Id, target, 6, 'C'),
          buildTarget(timeCardId, critical.Id, target, 3, 'B')
        },
        AccessLevel.SYSTEM_MODE
      );

      Product2 product = new Product2(
        Name = 'Test Product',
        IsActive = true
      );
      insert product;

      insert new Account_Territory_Product_Fields__c(
        Account__c = outOfPlan.Id,
        Territory2_Id__c = testTerritory.Id,
        Product2_Id__c = product.Id,
        Rx_Per_Week__c = 1,
        Adoption__c = 'H',
        Target_Visit_Frequency__c = 'Monthly',
        Is_Active__c = true
      );
    }
  }

  @IsTest
  static void getAccountsTabRecordTypeOptions_includesPharmacies() {
    List<AccountsTabController.RecordTypeFilterOption> options =
      AccountsTabController.getAccountsTabRecordTypeOptions();

    System.assertEquals(4, options.size(), 'Expected All plus three record type filters.');
    System.assertEquals('All Record Types', options[0].label);
    System.assertEquals('Institution (HCO)', options[1].label);
    System.assertEquals('Medical Professional (HCP)', options[2].label);
    System.assertEquals('Pharmacies', options[3].label);
    System.assertEquals('Pharmacy', options[3].value);
  }

  @IsTest
  static void getAccountsTabPage_membership_and_paceLabels() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'classification';
    q.sortDirection = 'desc';
    q.offset = 0;
    q.pageSize = 50;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(5, page.rows.size(), 'Expected 5 territory-scoped accounts.');

    Map<String, AccountsTabController.AccountsTabRow> byName = new Map<String, AccountsTabController.AccountsTabRow>();
    for (AccountsTabController.AccountsTabRow r : page.rows) {
      byName.put(r.accountName, r);
    }

    System.assertEquals(true, byName.get('Dr Account Ahead').inPlanCycle);
    System.assertEquals(true, byName.get('Dr Account On Track').inPlanCycle);
    System.assertEquals(true, byName.get('Dr Account Behind').inPlanCycle);
    System.assertEquals(true, byName.get('Dr Account Critical').inPlanCycle);

    System.assertEquals(false, byName.get('Dr Account Out Of Plan').inPlanCycle);
    System.assertEquals('Out', byName.get('Dr Account Out Of Plan').planCycleLabel);
    System.assertEquals(null, byName.get('Dr Account Out Of Plan').targetVisits);
    System.assertEquals('N/A', byName.get('Dr Account Out Of Plan').paceStatusLabel);
  }

  @IsTest
  static void getAccountsTabPage_paceStatusThresholds() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'in';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'classification';
    q.sortDirection = 'desc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    Map<String, String> paceLabelByName = new Map<String, String>();
    for (AccountsTabController.AccountsTabRow r : page.rows) {
      paceLabelByName.put(r.accountName, r.paceStatusLabel);
    }

    System.assertEquals('Ahead', paceLabelByName.get('Dr Account Ahead'));
    System.assertEquals('On Track', paceLabelByName.get('Dr Account On Track'));
    System.assertEquals('Behind', paceLabelByName.get('Dr Account Behind'));
    System.assertEquals('Critical', paceLabelByName.get('Dr Account Critical'));
  }

  @IsTest
  static void getAccountsTabPage_agentforceScoreOrdering() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'in';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'agentforceScore';
    q.sortDirection = 'desc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assert(!page.rows.isEmpty(), 'Expected rows for in-plan accounts.');
    System.assertEquals(
      'Dr Account Ahead',
      page.rows[0].accountName,
      'Expected highest Agentforce score to be first.'
    );
  }

  @IsTest
  static void getAccountsTabPage_oceFieldsAndNameSort() {
    Account ahead = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    Id userId = UserInfo.getUserId();
    DateTime completedVisit = DateTime.newInstance(
      Date.today().addDays(-14),
      Time.newInstance(11, 0, 0, 0)
    );
    Date monthEnd = Date.today().toStartOfMonth().addMonths(1).addDays(-1);
    Date futureDay = Date.today().addDays(1) <= monthEnd
      ? Date.today().addDays(1)
      : Date.today();
    DateTime futureVisit = DateTime.newInstance(
      futureDay,
      Time.newInstance(14, 0, 0, 0)
    );
    insert new List<Visit__c>{
      new Visit__c(
        Account__c = ahead.Id,
        Assigned_To__c = userId,
        Visit_Date__c = completedVisit.date(),
        Start_Date__c = completedVisit,
        End_Date__c = completedVisit.addMinutes(30),
        Status__c = 'Completed',
        Visit_Type__c = 'Planned (Automatically)',
        CLM_Presentation__c = 'CLM1'
      ),
      new Visit__c(
        Account__c = ahead.Id,
        Assigned_To__c = userId,
        Visit_Date__c = futureVisit.date(),
        Start_Date__c = futureVisit,
        End_Date__c = futureVisit.addMinutes(30),
        Status__c = 'Scheduled',
        Visit_Type__c = 'Planned (Automatically)',
        CLM_Presentation__c = 'CLM1'
      )
    };

    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assert(!page.recordTypeCounts.isEmpty(), 'Expected record type counts.');
    System.assertEquals('All', page.recordTypeCounts[0].value);
    System.assertEquals(5, page.recordTypeCounts[0].count);

    Map<String, AccountsTabController.AccountsTabRow> byName = new Map<String, AccountsTabController.AccountsTabRow>();
    for (AccountsTabController.AccountsTabRow r : page.rows) {
      byName.put(r.accountName, r);
    }

    AccountsTabController.AccountsTabRow aheadRow = byName.get('Dr Account Ahead');
    System.assertNotEquals(null, aheadRow, 'Expected ahead account row.');
    System.assertNotEquals(null, aheadRow.lastVisitDate, 'Expected last visit date.');
    System.assertNotEquals(null, aheadRow.nextVisitDate, 'Expected next planned visit date.');
    System.assertEquals(1, aheadRow.plannedVisits, 'Expected one planned visit.');
    System.assert(aheadRow.addressLine.contains('Cairo'), 'Expected address line with city.');

    System.assertEquals('Dr Account Ahead', page.rows[0].accountName, 'Expected name sort ascending.');
  }

  @IsTest
  static void getAccountsTabPage_tokenizedSearch() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = 'Ahead Cairo';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(1, page.rows.size(), 'Expected one account matching all tokens.');
    System.assertEquals('Dr Account Ahead', page.rows[0].accountName);
  }

  @IsTest
  static void getAccountsTabPage_classificationFilter() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.classification = 'A';
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(1, page.totalCount, 'Expected one A-class account.');
    System.assertEquals(1, page.rows.size());
    System.assertEquals('Dr Account Ahead', page.rows[0].accountName);
    System.assertEquals('A', page.rows[0].classification);
  }

  @IsTest
  static void getAccountsTabPage_classificationFilter_usesPotentialFallback() {
    Account potentialOnly = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Behind'
      LIMIT 1
    ];
    Account_Territory_Fields__c atf = [
      SELECT Id
      FROM Account_Territory_Fields__c
      WHERE Account__c = :potentialOnly.Id
      LIMIT 1
    ];
    atf.Classification__c = null;
    atf.Potential__c = 'C';
    update atf;

    AccountsTabController.AccountsTabQuery q = newQuery();
    q.classification = 'C';
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assert(
      page.totalCount >= 1,
      'Expected classification filter to match Potential__c fallback.'
    );
    Boolean foundBehind = false;
    for (AccountsTabController.AccountsTabRow row : page.rows) {
      if (row.accountName == 'Dr Account Behind') {
        foundBehind = true;
        break;
      }
    }
    System.assert(foundBehind, 'Expected Dr Account Behind via Potential__c fallback.');
  }

  @IsTest
  static void getAccountsTabPage_recordTypeFilter() {
    Account sample = [
      SELECT RecordType.DeveloperName
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    String setupDeveloperName = sample.RecordType.DeveloperName;
    Set<String> hcpTypes = new Set<String>{
      'SDO_PersonAccounts',
      'Medical_Professional_HCP',
      'PersonAccount',
      'Business_Contact'
    };
    String matchingFilter = hcpTypes.contains(setupDeveloperName)
      ? 'HCP'
      : setupDeveloperName;

    AccountsTabController.AccountsTabQuery matchQuery = newQuery();
    matchQuery.recordTypeDeveloperName = matchingFilter;
    matchQuery.sortBy = 'name';
    matchQuery.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage matchingPage =
      invokePage(matchQuery);

    System.assertEquals(
      5,
      matchingPage.totalCount,
      'Expected all setup accounts for the matching record type filter.'
    );
    for (AccountsTabController.AccountsTabRow row : matchingPage.rows) {
      if (matchingFilter == 'HCP') {
        System.assert(
          hcpTypes.contains(row.recordTypeDeveloperName),
          'Expected HCP-grouped record types only.'
        );
      } else {
        System.assertEquals(
          matchingFilter,
          row.recordTypeDeveloperName,
          'Expected matching record type only.'
        );
      }
    }

    AccountsTabController.AccountsTabQuery missQuery = newQuery();
    missQuery.recordTypeDeveloperName = 'Pharmacy';
    missQuery.sortBy = 'name';
    missQuery.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage missingPage =
      invokePage(missQuery);

    System.assertEquals(
      0,
      missingPage.totalCount,
      'Expected no accounts for a non-matching record type filter.'
    );
  }

  @IsTest
  static void getAccountsTabPage_pagination() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 2;
    q.offset = 0;

    AccountsTabController.AccountsTabPage firstPage =
      invokePage(q);

    System.assertEquals(5, firstPage.totalCount);
    System.assertEquals(2, firstPage.rows.size());

    q.offset = 2;
    AccountsTabController.AccountsTabPage secondPage =
      invokePage(q);

    System.assertEquals(5, secondPage.totalCount);
    System.assertEquals(2, secondPage.rows.size());
    System.assertNotEquals(
      firstPage.rows[0].accountId,
      secondPage.rows[0].accountId,
      'Expected a different page of accounts.'
    );
  }

  @IsTest
  static void getAccountsTabMapPoints_pagination() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 2;
    q.offset = 0;

    AccountsTabController.AccountsTabPage firstPage =
      invokeMapPoints(q);

    System.assertEquals(5, firstPage.totalCount);
    System.assertEquals(5, firstPage.mapEligibleCount);
    System.assertEquals(2, firstPage.rows.size());

    q.offset = 2;
    AccountsTabController.AccountsTabPage secondPage =
      invokeMapPoints(q);

    System.assertEquals(5, secondPage.mapEligibleCount);
    System.assertEquals(2, secondPage.rows.size());
    System.assertNotEquals(
      firstPage.rows[0].accountId,
      secondPage.rows[0].accountId,
      'Expected a different page of map points.'
    );
  }

  @IsTest
  static void getAccountsTabPage_recordTypeCounts_respectFilters() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.classification = 'A';
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(1, page.totalCount, 'Expected one A-class account.');
    System.assert(!page.recordTypeCounts.isEmpty(), 'Expected record type counts.');
    System.assertEquals('All', page.recordTypeCounts[0].value);
    System.assertEquals(
      1,
      page.recordTypeCounts[0].count,
      'Type counts should reflect classification filter.'
    );
  }

  @IsTest
  static void getAccountsTabPage_accountIdsFilter() {
    Account ahead = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    Account onTrack = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account On Track'
      LIMIT 1
    ];

    AccountsTabController.AccountsTabQuery q = newQuery();
    q.accountIds = new List<String>{
      String.valueOf(ahead.Id),
      String.valueOf(onTrack.Id)
    };
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(2, page.totalCount, 'Expected only accounts in the collection filter.');
    System.assertEquals(2, page.rows.size());
    System.assertEquals('Dr Account Ahead', page.rows[0].accountName);
    System.assertEquals('Dr Account On Track', page.rows[1].accountName);
  }

  private static AccountsTabController.AccountsTabQuery newQuery() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'agentforceScore';
    q.sortDirection = 'desc';
    q.offset = 0;
    q.pageSize = 50;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();
    return q;
  }

  private static AccountsTabController.AccountsTabPage invokePage(
    AccountsTabController.AccountsTabQuery q
  ) {
    AccountsTabController.forceTerritoryScope = true;
    return AccountsTabController.getAccountsTabPage(
      q.scope,
      q.searchTerm,
      q.recordTypeDeveloperName,
      q.classification,
      q.sortBy,
      q.sortDirection,
      q.offset,
      q.pageSize,
      q.monthStart,
      q.contextUserId,
      q.accountIds
    );
  }

  private static AccountsTabController.AccountsTabPage invokeMapPoints(
    AccountsTabController.AccountsTabQuery q
  ) {
    AccountsTabController.forceTerritoryScope = true;
    return AccountsTabController.getAccountsTabMapPoints(
      q.scope,
      q.searchTerm,
      q.recordTypeDeveloperName,
      q.classification,
      q.sortBy,
      q.sortDirection,
      q.offset,
      q.pageSize,
      q.monthStart,
      q.contextUserId,
      q.accountIds
    );
  }

  private static Account buildAccount(
    String name,
    Id recordTypeId,
    Decimal lat,
    Decimal lon,
    String city
  ) {
    Account acct = new Account(
      Name = name,
      BillingStreet = '123 Main St',
      BillingLatitude = lat,
      BillingLongitude = lon,
      BillingCity = city,
      RecordTypeId = recordTypeId
    );
    if (isHcpRecordType(recordTypeId)) {
      acct.Specialty_1__c = 'Cardiology';
    }
    return acct;
  }

  private static Boolean isHcpRecordType(Id recordTypeId) {
    if (recordTypeId == null) {
      return false;
    }
    List<RecordType> types = [
      SELECT DeveloperName
      FROM RecordType
      WHERE Id = :recordTypeId
      LIMIT 1
    ];
    if (types.isEmpty()) {
      return false;
    }
    Set<String> hcpTypes = new Set<String>{
      'Medical_Professional_HCP',
      'SDO_PersonAccounts',
      'PersonAccount',
      'Business_Contact'
    };
    return hcpTypes.contains(types[0].DeveloperName);
  }

  private static Account_Territory_Fields__c buildAtf(
    Id accountId,
    Id territory2Id,
    String classification,
    String matrixRating,
    String penetration,
    Boolean isActive,
    Boolean isKOL
  ) {
    return new Account_Territory_Fields__c(
      Account__c = accountId,
      Territory2_Id__c = territory2Id,
      Classification__c = classification,
      Matrix_Rating__c = matrixRating,
      Potential__c = classification,
      Penetration__c = penetration,
      Is_KOL__c = isKOL,
      Is_Active__c = isActive
    );
  }

  private static Employee_Time_Card_Account_Target__c buildTarget(
    Id timeCardId,
    Id accountId,
    Decimal targetVisits,
    Decimal actualVisits,
    String potentiality
  ) {
    // Frequency_Status__c, Reach_Percent__c and Is_Visited__c are formula fields
    // derived from Actual_Visits__c / Target_Visit_Frequency__c, so they are not set here.
    String uniqueKey = timeCardId + ':' + accountId;
    return new Employee_Time_Card_Account_Target__c(
      Employee_Time_Card__c = timeCardId,
      Account__c = accountId,
      Target_Visit_Frequency__c = targetVisits,
      Actual_Visits__c = actualVisits,
      Potentiality__c = potentiality,
      Rep__c = UserInfo.getUserId(),
      Unique_Key__c = uniqueKey
    );
  }

  private static Territory2 getOrCreateTestTerritory(String externalId) {
    List<Territory2> existing = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = :externalId
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }

    List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
    if (types.isEmpty()) {
      return null;
    }

    List<Territory2Model> models = [
      SELECT Id
      FROM Territory2Model
      WHERE DeveloperName = 'Current_FY'
      LIMIT 1
    ];
    if (models.isEmpty()) {
      return null;
    }

    Territory2 territory = new Territory2(
      Name = 'Accounts Tab Test Territory',
      DeveloperName = 'Accounts_Tab_Test_Territory',
      Territory2ModelId = models[0].Id,
      Territory2TypeId = types[0].Id,
      External_ID__c = externalId
    );
    insert territory;
    return territory;
  }

  @IsTest
  static void getAccountsTabPage_includesActiveBusinessUnits() {
    if (!AccountBusinessUnitService.isLinkSchemaReady()) {
      return;
    }
    Territory2 businessUnit = getOrCreateBuTerritory('TERR_BU_ACCOUNTS_TAB_TEST');
    if (businessUnit == null) {
      System.assert(false, 'Expected Business Unit Territory2.');
    }

    Account ahead = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];

    AccountBusinessUnitService.UpsertRequest request = new AccountBusinessUnitService.UpsertRequest();
    request.accountId = ahead.Id;
    request.businessUnitTerritory2Id = String.valueOf(businessUnit.Id);
    request.potentiality = 'A';
    request.propensity = '2';
    request.isActive = true;
    AccountBusinessUnitService.upsertLink(request);

    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = 'Dr Account Ahead';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.offset = 0;
    q.pageSize = 10;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page = invokePage(q);
    System.assert(!page.rows.isEmpty(), 'Expected account row.');
    AccountsTabController.AccountsTabRow row = page.rows[0];
    System.assertEquals(1, row.businessUnits.size(), 'Expected one active BU chip.');
    System.assert(String.isNotBlank(row.businessUnitLabel));
    System.assertEquals('A', row.businessUnits[0].potentiality);
  }

  private static Territory2 getOrCreateBuTerritory(String externalId) {
    List<Territory2> existing = [
      SELECT Id, Territory_Type__c
      FROM Territory2
      WHERE External_ID__c = :externalId
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      Territory2 territory = existing[0];
      if (
        Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c') &&
        territory.Territory_Type__c != 'Business_Unit'
      ) {
        territory.Territory_Type__c = 'Business_Unit';
        update territory;
      }
      return territory;
    }

    List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
    if (types.isEmpty()) {
      return null;
    }
    List<Territory2Model> models = [
      SELECT Id
      FROM Territory2Model
      WHERE DeveloperName = 'Current_FY'
      LIMIT 1
    ];
    if (models.isEmpty()) {
      return null;
    }

    Territory2 territory = new Territory2(
      Name = 'Accounts Tab BU Test',
      DeveloperName = 'Accounts_Tab_BU_Test',
      Territory2ModelId = models[0].Id,
      Territory2TypeId = types[0].Id,
      External_ID__c = externalId
    );
    if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
      territory.put('Territory_Type__c', 'Business_Unit');
    }
    insert territory;
    return territory;
  }

  private static Id resolveFirstAccountRecordTypeId(Set<String> devNames) {
    if (devNames == null || devNames.isEmpty()) {
      return null;
    }
    List<RecordType> types = [
      SELECT Id, DeveloperName
      FROM RecordType
      WHERE SObjectType = 'Account'
      AND IsActive = TRUE
      AND DeveloperName IN :devNames
      LIMIT 10
    ];
    System.assert(!types.isEmpty(), 'Expected at least one planner-compatible Account record type.');
    return types[0].Id;
  }

  private static void assignPermissionSet(String developerName) {
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :developerName
      LIMIT 1
    ];
    if (sets.isEmpty()) {
      return;
    }
    List<PermissionSetAssignment> existing = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :sets[0].Id
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return;
    }
    insert new PermissionSetAssignment(
      AssigneeId = UserInfo.getUserId(),
      PermissionSetId = sets[0].Id
    );
  }
}