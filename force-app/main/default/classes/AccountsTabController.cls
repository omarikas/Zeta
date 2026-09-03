public with sharing class AccountsTabController {
  private static final Decimal ON_TRACK_THRESHOLD = 90;
  private static final Decimal CRITICAL_THRESHOLD = 50;
  private static final String FILTER_ALL = 'All';
  private static final String SCOPE_IN = 'in';
  private static final String SCOPE_OUT = 'out';
  private static final String SCOPE_BOTH = 'both';
  private static final String SORT_CLASSIFICATION = 'classification';
  private static final String SORT_AGENTFORCE = 'agentforceScore';
  private static final String SORT_NAME = 'name';
  private static final Integer DEFAULT_PAGE_SIZE = 10;
  private static final Integer MAX_PAGE_SIZE = 50;
  private static final Integer MAX_MAP_POINTS = 2000;
  private static final String RECORD_TYPE_HCO = 'Institution_HCO';
  private static final String RECORD_TYPE_HCP = 'HCP';
  private static final String RECORD_TYPE_PHARMACY = 'Pharmacy';
  private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
  };
  private static final Set<String> PLANNER_ACCOUNT_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Institution_HCO',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact',
    'Pharmacy'
  };

  @TestVisible
  private static Boolean forceTerritoryScope = false;

  public class RecordTypeFilterOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public RecordTypeFilterOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class AccountsTabQuery {
    @AuraEnabled
    public String scope;
    @AuraEnabled
    public String searchTerm;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String classification;
    @AuraEnabled
    public String sortBy;
    @AuraEnabled
    public String sortDirection;
    @AuraEnabled
    public Integer offset;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public Id contextUserId;
    @AuraEnabled
    public List<String> accountIds;
  }

  public class AccountsTabPage {
    @AuraEnabled
    public List<AccountsTabRow> rows;
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public Integer inPlanCount;
    @AuraEnabled
    public Integer outPlanCount;
    @AuraEnabled
    public Integer behindPaceCount;
    @AuraEnabled
    public Boolean hasTimeCard;
    @AuraEnabled
    public String monthLabel;
    @AuraEnabled
    public List<FilterCount> recordTypeCounts;
    @AuraEnabled
    public Integer mapEligibleCount;
  }

  public class FilterCount {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public Integer count;
  }

  public class AccountsTabRow {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String accountUrl;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String recordTypeName;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String accountSubtype;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String classification;
    @AuraEnabled
    public String matrixRating;
    @AuraEnabled
    public String potential;
    @AuraEnabled
    public String penetration;
      @AuraEnabled
    public List<AccountBusinessUnitService.LinkDto> businessUnits;
    @AuraEnabled
    public String businessUnitLabel;
    @AuraEnabled
    public Boolean isKol;
    @AuraEnabled
    public Boolean inPlanCycle;
    @AuraEnabled
    public String planCycleLabel;
    @AuraEnabled
    public Decimal targetVisits;
    @AuraEnabled
    public Decimal actualVisits;
    @AuraEnabled
    public Decimal visitGap;
    @AuraEnabled
    public Decimal reachPercent;
    @AuraEnabled
    public Decimal projectedPercent;
    @AuraEnabled
    public String paceStatus;
    @AuraEnabled
    public String paceStatusLabel;
    @AuraEnabled
    public String frequencyStatus;
    @AuraEnabled
    public Decimal agentforceScore;
    @AuraEnabled
    public String agentforceRisk;
    @AuraEnabled
    public Integer classificationRank;
    @AuraEnabled
    public String pinKind;
    @AuraEnabled
    public DateTime lastVisitDate;
    @AuraEnabled
    public DateTime nextVisitDate;
    @AuraEnabled
    public Integer plannedVisits;
    @AuraEnabled
    public String addressLine;
  }

  @AuraEnabled(cacheable=true)
  public static List<RecordTypeFilterOption> getAccountsTabRecordTypeOptions() {
    return new List<RecordTypeFilterOption>{
      new RecordTypeFilterOption('All Record Types', FILTER_ALL),
      new RecordTypeFilterOption('Institution (HCO)', RECORD_TYPE_HCO),
      new RecordTypeFilterOption('Medical Professional (HCP)', RECORD_TYPE_HCP),
      new RecordTypeFilterOption('Pharmacies', RECORD_TYPE_PHARMACY)
    };
  }

  @AuraEnabled
  public static AccountsTabPage getAccountsTabPage(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Integer offset,
    Integer pageSize,
    Date monthStart,
    Id contextUserId,
    List<String> accountIds
  ) {
    return buildPage(
      toQuery(
        scope,
        searchTerm,
        recordTypeDeveloperName,
        classification,
        sortBy,
        sortDirection,
        offset,
        pageSize,
        monthStart,
        contextUserId,
        accountIds
      ),
      false
    );
  }

  @AuraEnabled
  public static AccountsTabPage getAccountsTabMapPoints(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Integer offset,
    Integer pageSize,
    Date monthStart,
    Id contextUserId,
    List<String> accountIds
  ) {
    return buildPage(
      toQuery(
        scope,
        searchTerm,
        recordTypeDeveloperName,
        classification,
        sortBy,
        sortDirection,
        offset,
        pageSize,
        monthStart,
        contextUserId,
        accountIds
      ),
      true
    );
  }

  private static AccountsTabQuery toQuery(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Integer offset,
    Integer pageSize,
    Date monthStart,
    Id contextUserId,
    List<String> accountIds
  ) {
    AccountsTabQuery query = new AccountsTabQuery();
    query.scope = scope;
    query.searchTerm = searchTerm;
    query.recordTypeDeveloperName = recordTypeDeveloperName;
    query.classification = classification;
    query.sortBy = sortBy;
    query.sortDirection = sortDirection;
    query.offset = offset;
    query.pageSize = pageSize;
    query.monthStart = monthStart;
    query.contextUserId = contextUserId;
    query.accountIds = accountIds;
    return query;
  }

  private static AccountsTabPage buildPage(AccountsTabQuery query, Boolean mapMode) {
    AccountsTabPage result = new AccountsTabPage();
    result.rows = new List<AccountsTabRow>();
    result.totalCount = 0;
    result.inPlanCount = 0;
    result.outPlanCount = 0;
    result.behindPaceCount = 0;
    result.hasTimeCard = false;
    result.recordTypeCounts = new List<FilterCount>();

    if (query == null) {
      query = new AccountsTabQuery();
    }

    Id userId = query.contextUserId != null ? query.contextUserId : UserInfo.getUserId();
    Date monthStart = query.monthStart != null
      ? Date.newInstance(query.monthStart.year(), query.monthStart.month(), 1)
      : Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    result.monthLabel = monthStart.format();

    String scope = normalizeScope(query.scope);
    String sortBy = String.isBlank(query.sortBy) ? SORT_AGENTFORCE : query.sortBy;
    Boolean sortAsc = 'asc'.equalsIgnoreCase(query.sortDirection);
    Integer pageSize = Math.min(
      query.pageSize == null ? DEFAULT_PAGE_SIZE : query.pageSize,
      mapMode ? MAX_MAP_POINTS : MAX_PAGE_SIZE
    );
    Integer rowOffset = query.offset == null || query.offset < 0 ? 0 : query.offset;

    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds(userId));
    Set<String> territoryIdStrings = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryIdStrings.add(String.valueOf(territoryId));
    }

    if (territoryIds.isEmpty() && !hasFullAccountAccess()) {
      return result;
    }

    Set<Id> accountIdFilter = resolveAccountIdsFilter(query.accountIds);
    Set<String> recordTypes = resolveRecordTypeFilter(query.recordTypeDeveloperName);
    String classificationFilter = resolveClassificationFilter(query.classification);
    String searchTerm = String.isBlank(query.searchTerm) ? null : query.searchTerm.trim();
    List<String> searchTokens = tokenizeSearch(searchTerm);

    List<Employee_Time_Card__c> cards = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    Id timeCardId = cards.isEmpty() ? null : cards[0].Id;
    result.hasTimeCard = timeCardId != null;

    WorkingDaysSummary workingDays = timeCardId != null
      ? computeWorkingDays(timeCardId, Date.today())
      : new WorkingDaysSummary();

    Integer territoryAtfCount = 0;
    if (!territoryIdStrings.isEmpty()) {
      territoryAtfCount = [
        SELECT COUNT()
        FROM Account_Territory_Fields__c
        WHERE
          Is_Active__c = TRUE
          AND Territory2_Id__c IN :territoryIdStrings
          AND Account__c != NULL
        WITH SYSTEM_MODE
      ];
    }

    // Head Office / admin: page Accounts directly (same as FieldPlanner). Never bulk-load ATF Ids.
    Boolean useFullAccountQuery =
      !forceTerritoryScope &&
      userId == UserInfo.getUserId() &&
      hasFullAccountAccess();

    Set<Id> scopedAccountIds = null;
    if (SCOPE_IN.equals(scope)) {
      scopedAccountIds = loadTimeCardTargetAccountIds(timeCardId);
      if (scopedAccountIds.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
    } else if (!useFullAccountQuery) {
      if (territoryIdStrings.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
      // Cap well under the 50k governor so COUNT + ATF + page queries cannot hit 50001.
      if (territoryAtfCount > 20000) {
        throw new AuraHandledException(
          'This territory has too many accounts to load at once. Assign Head Office access or narrow with a saved list.'
        );
      }
      scopedAccountIds = loadTerritoryAccountIdsCapped(territoryIdStrings, 20000);
      if (scopedAccountIds.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
    }

    if (accountIdFilter != null) {
      if (scopedAccountIds == null) {
        scopedAccountIds = accountIdFilter;
      } else {
        scopedAccountIds.retainAll(accountIdFilter);
        if (scopedAccountIds.isEmpty()) {
          result.recordTypeCounts = emptyRecordTypeCounts(0);
          return result;
        }
      }
    }

    if (classificationFilter != null && !territoryIdStrings.isEmpty()) {
      Set<Id> classifiedIds = loadClassifiedAccountIds(
        territoryIdStrings,
        classificationFilter,
        scopedAccountIds
      );
      scopedAccountIds = classifiedIds;
      if (scopedAccountIds.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
    }

    Integer fetchLimit = pageSize;
    Integer fetchOffset = rowOffset;
    Boolean geocodedOnly = mapMode == true;

    List<Account> pageAccounts = queryAccountsPage(
      recordTypes,
      scopedAccountIds,
      searchTokens,
      geocodedOnly,
      fetchLimit,
      fetchOffset
    );
    result.totalCount = countAccounts(recordTypes, scopedAccountIds, searchTokens, geocodedOnly);
    result.mapEligibleCount = mapMode
      ? result.totalCount
      : countAccounts(recordTypes, scopedAccountIds, searchTokens, true);
    result.recordTypeCounts = buildRecordTypeCountsAggregate(
      recordTypes,
      scopedAccountIds,
      searchTokens
    );

    // Without a time card, every account is out of plan at the territory level.
    if (timeCardId == null) {
      result.outPlanCount = result.totalCount;
      result.inPlanCount = 0;
      result.behindPaceCount = 0;
    }

    if (pageAccounts.isEmpty()) {
      return result;
    }

    Set<Id> pageAccountIds = new Map<Id, Account>(pageAccounts).keySet();
    Map<Id, Account_Territory_Fields__c> bestAtfByAccount = loadAtfForAccounts(
      pageAccountIds,
      territoryIdStrings
    );

    Map<Id, Employee_Time_Card_Account_Target__c> targetByAccount = new Map<Id, Employee_Time_Card_Account_Target__c>();
    if (timeCardId != null) {
      for (Employee_Time_Card_Account_Target__c target : [
        SELECT
          Account__c,
          Target_Visit_Frequency__c,
          Actual_Visits__c,
          Frequency_Status__c,
          Reach_Percent__c,
          Potentiality__c
        FROM Employee_Time_Card_Account_Target__c
        WHERE Employee_Time_Card__c = :timeCardId AND Account__c IN :pageAccountIds
        WITH USER_MODE
      ]) {
        targetByAccount.put(target.Account__c, target);
      }
      // Approximate plan counts from targets when we did not filter to in-plan only.
      if (!SCOPE_IN.equals(scope) && !SCOPE_OUT.equals(scope)) {
        result.inPlanCount = [
          SELECT COUNT()
          FROM Employee_Time_Card_Account_Target__c
          WHERE Employee_Time_Card__c = :timeCardId AND Account__c != NULL
          WITH USER_MODE
        ];
        result.outPlanCount = Math.max(0, result.totalCount - result.inPlanCount);
      } else if (SCOPE_IN.equals(scope)) {
        result.inPlanCount = result.totalCount;
        result.outPlanCount = 0;
      } else if (SCOPE_OUT.equals(scope)) {
        result.inPlanCount = 0;
        result.outPlanCount = result.totalCount;
      }
    }

    Map<Id, Integer> futureVisitsByAccount = loadFutureVisitCounts(pageAccountIds, userId, monthEnd);
    Map<Id, Integer> completedVisitsByAccount = loadCompletedVisitCounts(
      pageAccountIds,
      userId,
      monthStart,
      monthEnd
    );
    Map<Id, DateTime> lastVisitByAccount = loadLastVisitDates(pageAccountIds, userId);
    Map<Id, DateTime> nextVisitByAccount = loadNextVisitDates(pageAccountIds, userId, monthEnd);
    Map<String, Decimal> targetFrequencyByKey = loadTargetFrequencies(bestAtfByAccount.values());

    List<AccountsTabRow> pageRows = new List<AccountsTabRow>();
    for (Account account : pageAccounts) {
      Boolean inPlan = targetByAccount.containsKey(account.Id);
      if (SCOPE_OUT.equals(scope) && inPlan) {
        continue;
      }
      if (SCOPE_IN.equals(scope) && !inPlan) {
        continue;
      }

      Account_Territory_Fields__c atf = bestAtfByAccount.get(account.Id);
      if (atf == null) {
        atf = new Account_Territory_Fields__c(
          Account__c = account.Id,
          Is_Active__c = true
        );
      }

      AccountsTabRow row = buildRow(
        account,
        atf,
        inPlan,
        targetByAccount.get(account.Id),
        targetFrequencyByKey,
        completedVisitsByAccount.get(account.Id),
        futureVisitsByAccount.get(account.Id),
        lastVisitByAccount.get(account.Id),
        nextVisitByAccount.get(account.Id),
        workingDays,
        timeCardId != null
      );
      pageRows.add(row);
      if (timeCardId != null && (row.paceStatus == 'behind' || row.paceStatus == 'critical')) {
        result.behindPaceCount++;
      }
    }

    attachBusinessUnits(pageRows);
    sortRows(pageRows, sortBy, sortAsc);
    result.rows = pageRows;
    return result;
  }

  private static void attachBusinessUnits(List<AccountsTabRow> rows) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    if (!Schema.getGlobalDescribe().containsKey('Account_Business_Unit__c')) {
      return;
    }
    Set<Id> accountIds = new Set<Id>();
    for (AccountsTabRow row : rows) {
      if (row.accountId != null) {
        accountIds.add(row.accountId);
      }
      row.businessUnits = new List<AccountBusinessUnitService.LinkDto>();
      row.businessUnitLabel = '';
    }
    Map<Id, List<AccountBusinessUnitService.LinkDto>> byAccount =
      AccountBusinessUnitService.listForAccounts(accountIds, false);
    for (AccountsTabRow row : rows) {
      List<AccountBusinessUnitService.LinkDto> links = byAccount.get(row.accountId);
      if (links == null || links.isEmpty()) {
        continue;
      }
      row.businessUnits = links;
      List<String> labels = new List<String>();
      for (AccountBusinessUnitService.LinkDto link : links) {
        if (String.isNotBlank(link.chipLabel)) {
          labels.add(link.chipLabel);
        } else if (String.isNotBlank(link.businessUnitName)) {
          labels.add(link.businessUnitName);
        }
      }
      row.businessUnitLabel = String.join(labels, ', ');
    }
  }

  private static final String HEAD_OFFICE_EXTERNAL_ID = 'TERR_HEAD_OFFICE';

  private static Boolean hasFullAccountAccess() {
    if (isSystemAdministrator()) {
      return true;
    }
    Id headOfficeId = getHeadOfficeTerritoryId();
    if (headOfficeId == null) {
      return false;
    }
    for (UserTerritory2Association assignment : [
      SELECT Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :headOfficeId
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      return true;
    }
    return false;
  }

  private static Boolean isSystemAdministrator() {
    User currentUser = [
      SELECT Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH USER_MODE
      LIMIT 1
    ];
    return currentUser.Profile.Name == 'System Administrator';
  }

  private static Id getHeadOfficeTerritoryId() {
    List<Territory2> territories = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = :HEAD_OFFICE_EXTERNAL_ID
      WITH USER_MODE
      LIMIT 1
    ];
    return territories.isEmpty() ? null : territories[0].Id;
  }

  private static Set<Id> loadTimeCardTargetAccountIds(Id timeCardId) {
    Set<Id> accountIds = new Set<Id>();
    if (timeCardId == null) {
      return accountIds;
    }
    for (Employee_Time_Card_Account_Target__c target : [
      SELECT Account__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE Employee_Time_Card__c = :timeCardId AND Account__c != NULL
      WITH USER_MODE
    ]) {
      accountIds.add(target.Account__c);
    }
    return accountIds;
  }

  private static Set<Id> loadTerritoryAccountIdsCapped(
    Set<String> territoryIdStrings,
    Integer rowLimit
  ) {
    Set<Id> accountIds = new Set<Id>();
    if (territoryIdStrings == null || territoryIdStrings.isEmpty()) {
      return accountIds;
    }
    Integer lim = rowLimit == null || rowLimit < 1 ? 20000 : rowLimit;
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c
      FROM Account_Territory_Fields__c
      WHERE
        Is_Active__c = TRUE
        AND Territory2_Id__c IN :territoryIdStrings
        AND Account__c != NULL
      WITH SYSTEM_MODE
      LIMIT :lim
    ]) {
      accountIds.add(atf.Account__c);
    }
    return accountIds;
  }

  private static Set<Id> loadClassifiedAccountIds(
    Set<String> territoryIdStrings,
    String classificationFilter,
    Set<Id> scopedAccountIds
  ) {
    Set<Id> classifiedIds = new Set<Id>();
    // Never scan the full 92k ATF set — page-safe classification uses a hard cap.
    Integer lim = scopedAccountIds != null ? Math.min(20000, scopedAccountIds.size() + 1) : 20000;
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c, Matrix_Rating__c, Classification__c, Potential__c
      FROM Account_Territory_Fields__c
      WHERE
        Is_Active__c = TRUE
        AND Territory2_Id__c IN :territoryIdStrings
        AND Account__c != NULL
      WITH SYSTEM_MODE
      LIMIT :lim
    ]) {
      if (scopedAccountIds != null && !scopedAccountIds.contains(atf.Account__c)) {
        continue;
      }
      if (matchesClassification(atf, classificationFilter)) {
        classifiedIds.add(atf.Account__c);
      }
    }
    return classifiedIds;
  }

  private static String appendTokenSearchClauses(String soql, List<String> searchTokens) {
    if (searchTokens == null || searchTokens.isEmpty()) {
      return soql;
    }
    for (String token : searchTokens) {
      String esc = String.escapeSingleQuotes(token);
      soql +=
        'AND (Name LIKE \'%' +
        esc +
        '%\' OR BillingCity LIKE \'%' +
        esc +
        '%\' OR Specialty_1__c LIKE \'%' +
        esc +
        '%\') ';
    }
    return soql;
  }

  private static List<Account> queryAccountsPage(
    Set<String> recordTypes,
    Set<Id> scopedAccountIds,
    List<String> searchTokens,
    Boolean geocodedOnly,
    Integer lim,
    Integer rowOffset
  ) {
    String soql =
      'SELECT Id, Name, Specialty_1__c, Institution_Type__c, BillingStreet, BillingCity, BillingLatitude, BillingLongitude, ' +
      'RecordType.Name, RecordType.DeveloperName FROM Account ' +
      'WHERE RecordType.DeveloperName IN :recordTypes ';
    if (scopedAccountIds != null) {
      soql += 'AND Id IN :scopedAccountIds ';
    }
    soql = appendTokenSearchClauses(soql, searchTokens);
    if (geocodedOnly == true) {
      soql += 'AND BillingLatitude != NULL AND BillingLongitude != NULL ';
    }
    soql += 'ORDER BY Name ASC LIMIT :lim OFFSET :rowOffset';
    return Database.query(soql, AccessLevel.USER_MODE);
  }

  private static Integer countAccounts(
    Set<String> recordTypes,
    Set<Id> scopedAccountIds,
    List<String> searchTokens,
    Boolean geocodedOnly
  ) {
    String soql = 'SELECT COUNT() FROM Account WHERE RecordType.DeveloperName IN :recordTypes ';
    if (scopedAccountIds != null) {
      soql += 'AND Id IN :scopedAccountIds ';
    }
    soql = appendTokenSearchClauses(soql, searchTokens);
    if (geocodedOnly == true) {
      soql += 'AND BillingLatitude != NULL AND BillingLongitude != NULL ';
    }
    return Database.countQuery(soql, AccessLevel.USER_MODE);
  }

  private static Map<Id, Account_Territory_Fields__c> loadAtfForAccounts(
    Set<Id> accountIds,
    Set<String> territoryIdStrings
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new Map<Id, Account_Territory_Fields__c>();
    }
    List<Account_Territory_Fields__c> atfRecords;
    if (territoryIdStrings == null || territoryIdStrings.isEmpty()) {
      atfRecords = [
        SELECT
          Id,
          Account__c,
          Classification__c,
          Matrix_Rating__c,
          Potential__c,
          Penetration__c,
          Is_KOL__c,
          Territory2_Id__c
        FROM Account_Territory_Fields__c
        WHERE Is_Active__c = TRUE AND Account__c IN :accountIds
        WITH SYSTEM_MODE
      ];
    } else {
      atfRecords = [
        SELECT
          Id,
          Account__c,
          Classification__c,
          Matrix_Rating__c,
          Potential__c,
          Penetration__c,
          Is_KOL__c,
          Territory2_Id__c
        FROM Account_Territory_Fields__c
        WHERE
          Is_Active__c = TRUE
          AND Account__c IN :accountIds
          AND Territory2_Id__c IN :territoryIdStrings
        WITH SYSTEM_MODE
      ];
    }
    return pickBestAtfPerAccount(atfRecords);
  }

  private static List<FilterCount> emptyRecordTypeCounts(Integer total) {
    List<FilterCount> counts = new List<FilterCount>();
    FilterCount allEntry = new FilterCount();
    allEntry.label = 'All';
    allEntry.value = FILTER_ALL;
    allEntry.count = total;
    counts.add(allEntry);
    return counts;
  }

  private static List<FilterCount> buildRecordTypeCountsAggregate(
    Set<String> recordTypes,
    Set<Id> scopedAccountIds,
    List<String> searchTokens
  ) {
    String soql =
      'SELECT RecordType.DeveloperName developerName, COUNT(Id) cnt FROM Account ' +
      'WHERE RecordType.DeveloperName IN :recordTypes ';
    if (scopedAccountIds != null) {
      soql += 'AND Id IN :scopedAccountIds ';
    }
    soql = appendTokenSearchClauses(soql, searchTokens);
    soql += 'GROUP BY RecordType.DeveloperName';

    Map<String, Integer> countsByKey = new Map<String, Integer>();
    Integer total = 0;
    for (AggregateResult agg : Database.query(soql, AccessLevel.USER_MODE)) {
      String developerName = (String) agg.get('developerName');
      Integer cnt = Integer.valueOf(agg.get('cnt'));
      String key = canonicalRecordTypeFilterKey(developerName);
      countsByKey.put(key, (countsByKey.containsKey(key) ? countsByKey.get(key) : 0) + cnt);
      total += cnt;
    }

    List<FilterCount> counts = emptyRecordTypeCounts(total);
    for (String key : new List<String>{ RECORD_TYPE_HCO, RECORD_TYPE_HCP, RECORD_TYPE_PHARMACY }) {
      if (countsByKey.containsKey(key)) {
        FilterCount entry = new FilterCount();
        entry.label = canonicalRecordTypeFilterLabel(key);
        entry.value = key;
        entry.count = countsByKey.get(key);
        counts.add(entry);
      }
    }
    return counts;
  }

  private static AccountsTabRow buildRow(
    Account account,
    Account_Territory_Fields__c atf,
    Boolean inPlan,
    Employee_Time_Card_Account_Target__c target,
    Map<String, Decimal> targetFrequencyByKey,
    Integer completedVisits,
    Integer futureVisits,
    DateTime lastVisitDate,
    DateTime nextVisitDate,
    WorkingDaysSummary workingDays,
    Boolean hasTimeCard
  ) {
    AccountsTabRow row = new AccountsTabRow();
    row.accountId = account.Id;
    row.accountName = account.Name;
    row.accountUrl = '/' + String.valueOf(account.Id);
    row.specialty = MedicalSpecialtyPicklist.getLabel(account.Specialty_1__c);
    row.city = account.BillingCity;
    row.addressLine = buildAddressLine(account.BillingStreet, account.BillingCity);
    row.recordTypeName = account.RecordType?.Name;
    row.recordTypeDeveloperName = account.RecordType?.DeveloperName;
    row.accountSubtype = account.Institution_Type__c;
    row.latitude = account.BillingLatitude;
    row.longitude = account.BillingLongitude;
    row.classification = String.isNotBlank(atf.Classification__c)
      ? atf.Classification__c
      : resolvePotentiality(atf);
    row.matrixRating = atf.Matrix_Rating__c;
    row.potential = atf.Potential__c;
    row.penetration = atf.Penetration__c;
    row.isKol = atf.Is_KOL__c == true;
    row.inPlanCycle = inPlan;
    row.planCycleLabel = inPlan ? 'In' : 'Out';
    row.classificationRank = classificationRank(row.classification);
    row.pinKind = resolvePinKind(row.recordTypeDeveloperName, row.recordTypeName);

    Integer completed = completedVisits == null ? 0 : completedVisits;
    Integer future = futureVisits == null ? 0 : futureVisits;
    row.plannedVisits = future;
    row.lastVisitDate = lastVisitDate;
    row.nextVisitDate = nextVisitDate;

    if (inPlan && target != null) {
      row.targetVisits = nvl(target.Target_Visit_Frequency__c);
      row.actualVisits = nvl(target.Actual_Visits__c);
      row.reachPercent = toDisplayPercent(target.Reach_Percent__c);
      row.frequencyStatus = target.Frequency_Status__c;
    } else if (!inPlan) {
      row.targetVisits = null;
      row.actualVisits = completed;
      row.reachPercent = null;
      row.frequencyStatus = null;
    } else {
      String freqKey = String.valueOf(account.Id) + ':' + atf.Territory2_Id__c;
      row.targetVisits = targetFrequencyByKey.containsKey(freqKey)
        ? targetFrequencyByKey.get(freqKey)
        : 1;
      row.actualVisits = completed;
      row.reachPercent = row.targetVisits > 0
        ? (row.actualVisits / row.targetVisits) * 100
        : 0;
      row.frequencyStatus = null;
    }

    if (!inPlan) {
      row.visitGap = null;
      row.projectedPercent = null;
      row.paceStatus = 'na';
      row.paceStatusLabel = paceStatusLabel(row.paceStatus);
      applyAgentforceScore(row);
      return row;
    }

    row.visitGap = Math.max(0, nvl(row.targetVisits) - nvl(row.actualVisits));

    if (hasTimeCard && workingDays.paceRatio > 0 && row.targetVisits > 0) {
      Decimal projectedVisits = row.actualVisits / workingDays.paceRatio;
      row.projectedPercent = (projectedVisits / row.targetVisits) * 100;
      row.paceStatus = paceStatusFromProjected(row.projectedPercent);
    } else if (hasTimeCard && row.targetVisits > 0 && row.actualVisits > 0) {
      row.projectedPercent = 100;
      row.paceStatus = 'ahead';
    } else if (!hasTimeCard) {
      row.projectedPercent = null;
      row.paceStatus = 'na';
    } else {
      row.projectedPercent = 0;
      row.paceStatus = row.targetVisits > 0 ? 'critical' : 'na';
    }

    row.paceStatusLabel = paceStatusLabel(row.paceStatus);
    applyAgentforceScore(row);
    return row;
  }

  private static void applyAgentforceScore(AccountsTabRow row) {
    Decimal visitGapRatio = row.targetVisits > 0
      ? Math.max(0, row.visitGap) / row.targetVisits
      : 0;
    Decimal projected = row.projectedPercent == null ? 100 : row.projectedPercent;
    Decimal paceRiskRatio = Math.max(0, Math.min(1, (100 - projected) / 100));
    row.agentforceScore =
      Decimal.valueOf(row.classificationRank) * 100 +
      visitGapRatio * 50 +
      paceRiskRatio * 50;
    row.agentforceRisk = agentforceRiskLabel(row.paceStatus);
  }

  private static String agentforceRiskLabel(String paceStatus) {
    if (paceStatus == 'critical') {
      return 'High';
    }
    if (paceStatus == 'behind') {
      return 'Med';
    }
    if (paceStatus == 'na') {
      return 'Low';
    }
    return 'Low';
  }

  private static String paceStatusLabel(String paceStatus) {
    if (paceStatus == 'ahead') {
      return 'Ahead';
    }
    if (paceStatus == 'on_track') {
      return 'On Track';
    }
    if (paceStatus == 'behind') {
      return 'Behind';
    }
    if (paceStatus == 'critical') {
      return 'Critical';
    }
    return 'N/A';
  }

  private static Map<Id, Account_Territory_Fields__c> pickBestAtfPerAccount(
    List<Account_Territory_Fields__c> atfRecords
  ) {
    Map<Id, Account_Territory_Fields__c> bestByAccount = new Map<Id, Account_Territory_Fields__c>();
    for (Account_Territory_Fields__c atf : atfRecords) {
      if (atf.Account__c == null) {
        continue;
      }
      if (!bestByAccount.containsKey(atf.Account__c)) {
        bestByAccount.put(atf.Account__c, atf);
        continue;
      }
      Account_Territory_Fields__c existing = bestByAccount.get(atf.Account__c);
      if (classificationRank(resolvePotentiality(atf)) >
          classificationRank(resolvePotentiality(existing))) {
        bestByAccount.put(atf.Account__c, atf);
      }
    }
    return bestByAccount;
  }

  private static Map<String, Decimal> loadTargetFrequencies(
    List<Account_Territory_Fields__c> atfRecords
  ) {
    Set<String> accountIdStrings = new Set<String>();
    Set<String> territoryIds = new Set<String>();
    for (Account_Territory_Fields__c atf : atfRecords) {
      accountIdStrings.add(String.valueOf(atf.Account__c));
      territoryIds.add(atf.Territory2_Id__c);
    }
    Map<String, Decimal> result = new Map<String, Decimal>();
    if (territoryIds.isEmpty()) {
      return result;
    }
    for (Account_Territory_Product_Fields__c atpf : [
      SELECT Account__c, Territory2_Id__c, Target_Visit_Frequency__c
      FROM Account_Territory_Product_Fields__c
      WHERE Territory2_Id__c IN :territoryIds AND Is_Active__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      String key = String.valueOf(atpf.Account__c) + ':' + atpf.Territory2_Id__c;
      if (!accountIdStrings.contains(String.valueOf(atpf.Account__c))) {
        continue;
      }
      Decimal mapped = EmployeeTimeCardService.mapFrequencyPicklist(
        atpf.Target_Visit_Frequency__c
      );
      if (!result.containsKey(key) || mapped > result.get(key)) {
        result.put(key, mapped);
      }
    }
    return result;
  }

  private static Map<Id, Integer> loadFutureVisitCounts(
    Set<Id> accountIds,
    Id userId,
    Date monthEnd
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult agg : [
      SELECT Account__c accountId, COUNT(Id) visitCount
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0))
        AND Start_Date__c <= :DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0))
        AND Status__c IN ('Draft', 'Scheduled', 'Rescheduled')
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      counts.put((Id) agg.get('accountId'), (Integer) agg.get('visitCount'));
    }
    return counts;
  }

  private static Map<Id, Integer> loadCompletedVisitCounts(
    Set<Id> accountIds,
    Id userId,
    Date monthStart,
    Date monthEnd
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult agg : [
      SELECT Account__c accountId, COUNT(Id) visitCount
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
        AND Start_Date__c <= :DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0))
        AND Status__c = 'Completed'
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      counts.put((Id) agg.get('accountId'), (Integer) agg.get('visitCount'));
    }
    return counts;
  }

  private static void sortRows(List<AccountsTabRow> rows, String sortBy, Boolean sortAsc) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    if (SORT_NAME.equals(sortBy)) {
      rows.sort(new NameComparator(sortAsc));
    } else if (SORT_CLASSIFICATION.equals(sortBy)) {
      rows.sort(new ClassificationComparator(sortAsc));
    } else {
      rows.sort(new AgentforceScoreComparator(sortAsc));
    }
  }

  private static List<FilterCount> buildRecordTypeCountsFromRows(List<AccountsTabRow> rows) {
    Map<String, FilterCount> countsByKey = new Map<String, FilterCount>();
    Integer totalCount = rows == null ? 0 : rows.size();
    if (rows != null) {
      for (AccountsTabRow row : rows) {
        String filterKey = canonicalRecordTypeFilterKey(row.recordTypeDeveloperName);
        if (!countsByKey.containsKey(filterKey)) {
          FilterCount entry = new FilterCount();
          entry.label = canonicalRecordTypeFilterLabel(filterKey);
          entry.value = filterKey;
          entry.count = 0;
          countsByKey.put(filterKey, entry);
        }
        countsByKey.get(filterKey).count++;
      }
    }

    List<FilterCount> counts = new List<FilterCount>();
    FilterCount allEntry = new FilterCount();
    allEntry.label = 'All';
    allEntry.value = FILTER_ALL;
    allEntry.count = totalCount;
    counts.add(allEntry);

    for (String key : new List<String>{
      RECORD_TYPE_HCO,
      RECORD_TYPE_HCP,
      RECORD_TYPE_PHARMACY
    }) {
      if (countsByKey.containsKey(key)) {
        counts.add(countsByKey.get(key));
      }
    }
    return counts;
  }

  private static String canonicalRecordTypeFilterKey(String developerName) {
    if (RECORD_TYPE_HCO.equals(developerName)) {
      return RECORD_TYPE_HCO;
    }
    if (RECORD_TYPE_PHARMACY.equals(developerName)) {
      return RECORD_TYPE_PHARMACY;
    }
    if (HCP_RECORD_TYPES.contains(developerName)) {
      return RECORD_TYPE_HCP;
    }
    return String.isBlank(developerName) ? 'Unknown' : developerName;
  }

  private static String canonicalRecordTypeFilterLabel(String filterKey) {
    if (RECORD_TYPE_HCO.equals(filterKey)) {
      return 'Institution (HCO)';
    }
    if (RECORD_TYPE_HCP.equals(filterKey)) {
      return 'Medical Professional (HCP)';
    }
    if (RECORD_TYPE_PHARMACY.equals(filterKey)) {
      return 'Pharmacies';
    }
    return filterKey;
  }

  private static Map<Id, DateTime> loadLastVisitDates(Set<Id> accountIds, Id userId) {
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (accountIds == null || accountIds.isEmpty()) {
      return result;
    }
    for (AggregateResult agg : [
      SELECT Account__c accountId, MAX(Start_Date__c) lastVisit
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Status__c = 'Completed'
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      result.put((Id) agg.get('accountId'), (DateTime) agg.get('lastVisit'));
    }
    return result;
  }

  private static Map<Id, DateTime> loadNextVisitDates(
    Set<Id> accountIds,
    Id userId,
    Date monthEnd
  ) {
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (accountIds == null || accountIds.isEmpty()) {
      return result;
    }
    DateTime rangeStart = DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
    for (AggregateResult agg : [
      SELECT Account__c accountId, MIN(Start_Date__c) nextVisit
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :rangeStart
        AND Start_Date__c <= :rangeEnd
        AND Status__c IN ('Draft', 'Scheduled', 'Rescheduled')
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      result.put((Id) agg.get('accountId'), (DateTime) agg.get('nextVisit'));
    }
    return result;
  }

  private static String buildAddressLine(String street, String city) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(street)) {
      parts.add(street.trim());
    }
    if (String.isNotBlank(city)) {
      parts.add(city.trim());
    }
    return String.join(parts, ', ');
  }

  private static String normalizeScope(String scope) {
    if (String.isBlank(scope)) {
      return SCOPE_BOTH;
    }
    String normalized = scope.toLowerCase();
    if (normalized == SCOPE_IN || normalized == SCOPE_OUT || normalized == SCOPE_BOTH) {
      return normalized;
    }
    return SCOPE_BOTH;
  }

  private static Set<String> resolveRecordTypeFilter(String recordTypeDeveloperName) {
    if (String.isBlank(recordTypeDeveloperName) || FILTER_ALL.equals(recordTypeDeveloperName)) {
      return PLANNER_ACCOUNT_RECORD_TYPES;
    }
    if (
      RECORD_TYPE_HCP.equals(recordTypeDeveloperName) ||
      HCP_RECORD_TYPES.contains(recordTypeDeveloperName)
    ) {
      return HCP_RECORD_TYPES;
    }
    if (RECORD_TYPE_HCO.equals(recordTypeDeveloperName)) {
      return new Set<String>{ RECORD_TYPE_HCO };
    }
    if (RECORD_TYPE_PHARMACY.equals(recordTypeDeveloperName)) {
      return new Set<String>{ RECORD_TYPE_PHARMACY };
    }
    if (PLANNER_ACCOUNT_RECORD_TYPES.contains(recordTypeDeveloperName)) {
      return new Set<String>{ recordTypeDeveloperName };
    }
    return PLANNER_ACCOUNT_RECORD_TYPES;
  }

  private static String resolveClassificationFilter(String classification) {
    if (String.isBlank(classification) || FILTER_ALL.equals(classification)) {
      return null;
    }
    return classification;
  }

  private static Set<Id> resolveAccountIdsFilter(List<String> rawAccountIds) {
    if (rawAccountIds == null || rawAccountIds.isEmpty()) {
      return null;
    }
    Set<Id> accountIds = new Set<Id>();
    for (String rawAccountId : rawAccountIds) {
      if (String.isBlank(rawAccountId)) {
        continue;
      }
      try {
        accountIds.add((Id) rawAccountId.trim());
      } catch (Exception ex) {
        continue;
      }
    }
    return accountIds.isEmpty() ? null : accountIds;
  }

  private static Boolean matchesRecordType(String developerName, Set<String> recordTypes) {
    return developerName != null && recordTypes.contains(developerName);
  }

  private static Boolean matchesClassification(
    Account_Territory_Fields__c atf,
    String classification
  ) {
    if (classification.length() == 1) {
      return classification.equalsIgnoreCase(resolvePotentiality(atf));
    }
    return classification.equalsIgnoreCase(atf.Matrix_Rating__c);
  }

  private static Boolean matchesSearch(
    Account account,
    Account_Territory_Fields__c atf,
    String rawTerm
  ) {
    List<String> tokens = tokenizeSearch(rawTerm);
    if (tokens.isEmpty()) {
      return true;
    }
    String haystack = buildSearchHaystack(account, atf);
    for (String token : tokens) {
      if (!haystack.contains(token)) {
        return false;
      }
    }
    return true;
  }

  private static List<String> tokenizeSearch(String rawTerm) {
    List<String> tokens = new List<String>();
    if (String.isBlank(rawTerm)) {
      return tokens;
    }
    for (String part : rawTerm.trim().toLowerCase().split('\\s+')) {
      if (String.isNotBlank(part)) {
        tokens.add(part);
      }
    }
    return tokens;
  }

  private static String buildSearchHaystack(
    Account account,
    Account_Territory_Fields__c atf
  ) {
    List<String> parts = new List<String>();
    if (account.Name != null) {
      parts.add(account.Name.toLowerCase());
    }
    if (account.BillingCity != null) {
      parts.add(account.BillingCity.toLowerCase());
    }
    if (account.BillingStreet != null) {
      parts.add(account.BillingStreet.toLowerCase());
    }
    if (account.Specialty_1__c != null) {
      parts.addAll(MedicalSpecialtyPicklist.getSearchTokens(account.Specialty_1__c));
    }
    if (account.RecordType?.Name != null) {
      parts.add(account.RecordType.Name.toLowerCase());
    }
    if (account.RecordType?.DeveloperName != null) {
      parts.add(account.RecordType.DeveloperName.toLowerCase());
    }
    if (atf != null) {
      if (atf.Classification__c != null) {
        parts.add(atf.Classification__c.toLowerCase());
      }
      if (atf.Matrix_Rating__c != null) {
        parts.add(atf.Matrix_Rating__c.toLowerCase());
      }
      if (atf.Potential__c != null) {
        parts.add(atf.Potential__c.toLowerCase());
      }
    }
    return String.join(parts, ' ');
  }

  private static String resolvePotentiality(Account_Territory_Fields__c atf) {
    if (String.isNotBlank(atf.Classification__c)) {
      return atf.Classification__c;
    }
    if (String.isNotBlank(atf.Potential__c)) {
      return atf.Potential__c;
    }
    return 'Not Rated';
  }

  private static Integer classificationRank(String classification) {
    if (classification == 'A') {
      return 3;
    }
    if (classification == 'B') {
      return 2;
    }
    if (classification == 'C') {
      return 1;
    }
    return 0;
  }

  private static String resolvePinKind(String recordTypeDeveloperName, String recordTypeName) {
    Set<String> hcpTypes = new Set<String>{
      'SDO_PersonAccounts',
      'Medical_Professional_HCP',
      'PersonAccount',
      'Business_Contact'
    };
    Set<String> hcoTypes = new Set<String>{ 'Institution_HCO', 'Pharmacy' };
    if (hcpTypes.contains(recordTypeDeveloperName)) {
      return 'hcp';
    }
    if (hcoTypes.contains(recordTypeDeveloperName)) {
      return 'hco';
    }
    String label = (recordTypeName == null ? '' : recordTypeName).toLowerCase();
    if (
      label.contains('hcp') ||
      label.contains('professional') ||
      label.contains('person')
    ) {
      return 'hcp';
    }
    if (
      label.contains('hco') ||
      label.contains('institution') ||
      label.contains('pharmacy')
    ) {
      return 'hco';
    }
    return 'hcp';
  }

  private static Set<Id> getUserTerritoryIds(Id userId) {
    Set<Id> territoryIds = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :userId
      WITH SYSTEM_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    return territoryIds;
  }

  private static Set<Id> expandTerritoryHierarchy(Set<Id> rootTerritoryIds) {
    Set<Id> expanded = new Set<Id>();
    if (rootTerritoryIds == null || rootTerritoryIds.isEmpty()) {
      return expanded;
    }
    expanded.addAll(rootTerritoryIds);
    List<Id> frontier = new List<Id>(rootTerritoryIds);
    while (!frontier.isEmpty()) {
      List<Id> nextFrontier = new List<Id>();
      for (Territory2 child : [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :frontier
        WITH SYSTEM_MODE
      ]) {
        if (!expanded.contains(child.Id)) {
          expanded.add(child.Id);
          nextFrontier.add(child.Id);
        }
      }
      frontier = nextFrontier;
    }
    return expanded;
  }

  private static String paceStatusFromProjected(Decimal projectedPercent) {
    if (projectedPercent >= 100) {
      return 'ahead';
    }
    if (projectedPercent >= ON_TRACK_THRESHOLD) {
      return 'on_track';
    }
    if (projectedPercent >= CRITICAL_THRESHOLD) {
      return 'behind';
    }
    return 'critical';
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static Decimal toDisplayPercent(Decimal percentFieldValue) {
    if (percentFieldValue == null) {
      return null;
    }
    if (percentFieldValue > 100) {
      return percentFieldValue / 100;
    }
    if (percentFieldValue <= 1) {
      return percentFieldValue * 100;
    }
    return percentFieldValue;
  }

  private class WorkingDaysSummary {
    public Integer elapsedWorkingDays = 0;
    public Integer totalWorkingDays = 0;
    public Decimal paceRatio = 0;
  }

  private static WorkingDaysSummary computeWorkingDays(Id timeCardId, Date asOfDate) {
    WorkingDaysSummary summary = new WorkingDaysSummary();
    for (Employee_Time_Card_Day_Entry__c entry : [
      SELECT Date__c, Calendar_Working_Days__c
      FROM Employee_Time_Card_Day_Entry__c
      WHERE Employee_Time_Card__c = :timeCardId
      WITH USER_MODE
      ORDER BY Date__c ASC
    ]) {
      Integer calDays = nvl(entry.Calendar_Working_Days__c).intValue();
      summary.totalWorkingDays += calDays;
      if (entry.Date__c != null && entry.Date__c <= asOfDate) {
        summary.elapsedWorkingDays += calDays;
      }
    }
    if (summary.totalWorkingDays > 0) {
      summary.paceRatio =
        Decimal.valueOf(summary.elapsedWorkingDays) /
        Decimal.valueOf(summary.totalWorkingDays);
    }
    return summary;
  }

  private class NameComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;

    NameComparator(Boolean ascending) {
      this.ascending = ascending == true;
    }

    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      String nameA = a.accountName == null ? '' : a.accountName;
      String nameB = b.accountName == null ? '' : b.accountName;
      Integer result = nameA.compareTo(nameB);
      return ascending ? result : -result;
    }
  }

  private class ClassificationComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;

    ClassificationComparator(Boolean ascending) {
      this.ascending = ascending == true;
    }

    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Integer rankA = a.classificationRank == null ? 0 : a.classificationRank;
      Integer rankB = b.classificationRank == null ? 0 : b.classificationRank;
      if (rankA == rankB) {
        String nameA = a.accountName == null ? '' : a.accountName;
        String nameB = b.accountName == null ? '' : b.accountName;
        return nameA.compareTo(nameB);
      }
      return ascending ? rankA - rankB : rankB - rankA;
    }
  }

  private class AgentforceScoreComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;

    AgentforceScoreComparator(Boolean ascending) {
      this.ascending = ascending == true;
    }

    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Decimal scoreA = a.agentforceScore == null ? 0 : a.agentforceScore;
      Decimal scoreB = b.agentforceScore == null ? 0 : b.agentforceScore;
      if (scoreA == scoreB) {
        String nameA = a.accountName == null ? '' : a.accountName;
        String nameB = b.accountName == null ? '' : b.accountName;
        return nameA.compareTo(nameB);
      }
      if (scoreA > scoreB) {
        return ascending ? 1 : -1;
      }
      return ascending ? -1 : 1;
    }
  }
}