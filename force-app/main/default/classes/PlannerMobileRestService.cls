@RestResource(urlMapping='/planner/v1/*')
global with sharing class PlannerMobileRestService {
  global class ErrorResponse {
    public String message;
    public ErrorResponse(String message) {
      this.message = message;
    }
  }

  global class OutboxAction {
    public String id;
    public String actionType;
    public String payloadJson;
    public String clientVisitKey;
  }

  global class OutboxRequest {
    public List<OutboxAction> actions;
  }

  global class OutboxResultItem {
    public String id;
    public Boolean success;
    public String error;
    public Map<String, String> visitIdByClientKey;
  }

  global class OutboxResponse {
    public List<OutboxResultItem> results;
  }

  global class SyncPullResponse {
    public List<FieldPlannerController.AccountSummary> accounts;
    public List<FieldPlannerController.VisitSummary> visits;
    public List<FieldPlannerController.TotSummary> timeOff;
    public List<FieldPlannerController.ProjectOption> projects;
    public Map<String, Object> ui;
    public Map<String, String> cursors;
  }

  @HttpGet
  global static void doGet() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = req.requestURI.substringAfter('/planner/v1');
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      Map<String, String> params = req.params;

      if (path == 'week' || path.startsWith('week?')) {
        Date weekStart = Date.valueOf(params.get('weekStart'));
        Date weekEnd = Date.valueOf(params.get('weekEnd'));
        Id contextUserId = blankToNullId(params.get('contextUserId'));
        FieldPlannerController.PlannerPayload payload = FieldPlannerController.getPlannerData(
          weekStart,
          weekEnd,
          contextUserId
        );
        writeJson(
          res,
          200,
          new Map<String, Object>{
            'weekStart' => String.valueOf(weekStart),
            'weekEnd' => String.valueOf(weekEnd),
            'visits' => payload.visits,
            'timeOff' => payload.timeOffBlocks
          }
        );
        return;
      }
      if (path == 'accounts/map') {
        writeJson(res, 200, FieldPlannerController.getMapAccounts(blankToNullId(params.get('contextUserId'))));
        return;
      }
      if (path == 'accounts/filters') {
        writeJson(
          res,
          200,
          FieldPlannerController.getPlannerAccountFilterOptions(blankToNullId(params.get('contextUserId')))
        );
        return;
      }
      if (path == 'accounts/record-types') {
        List<FieldPlannerController.RecordTypeOption> opts = FieldPlannerController.getPlannerAccountRecordTypes();
        List<Object> mapped = new List<Object>();
        if (opts != null) {
          for (FieldPlannerController.RecordTypeOption o : opts) {
            mapped.add(
              new Map<String, Object>{
                'label' => o.label,
                'value' => o.value,
                'developerName' => o.value
              }
            );
          }
        }
        writeJson(res, 200, mapped);
        return;
      }
      if (path == 'projects') {
        List<FieldPlannerController.ProjectOption> opts = FieldPlannerController.getPromotionalProjects(
          blankToNullId(params.get('contextUserId'))
        );
        List<Object> projects = new List<Object>();
        if (opts != null) {
          for (FieldPlannerController.ProjectOption o : opts) {
            projects.add(
              new Map<String, Object>{
                'id' => o.value,
                'name' => o.label,
                'status' => null,
                'campaignType' => null
              }
            );
          }
        }
        writeJson(res, 200, projects);
        return;
      }
      if (path == 'targets') {
        writeJson(
          res,
          200,
          FieldPlannerController.getAccountVisitTargets(blankToNullId(params.get('contextUserId')))
        );
        return;
      }
      if (path == 'ui-metadata') {
        writeJson(res, 200, buildUiMetadata());
        return;
      }
      if (path == 'sync/pull') {
        writeJson(res, 200, buildSyncPull(params.get('since')));
        return;
      }
      if (path == 'home/dashboard') {
        writeJson(res, 200, buildHomeDashboard(blankToNullId(params.get('contextUserId'))));
        return;
      }
      if (path == 'home/today-plan') {
        writeJson(
          res,
          200,
          buildTodayPlan(blankToNullId(params.get('contextUserId')), parseDate(params.get('planDate')))
        );
        return;
      }
      if (path == 'home/next-best-customers') {
        writeJson(
          res,
          200,
          buildNextBestCustomers(
            blankToNullId(params.get('contextUserId')),
            toInteger(params.get('limitSize'), 5)
          )
        );
        return;
      }
      if (path == 'home/monthly-timecard') {
        writeJson(
          res,
          200,
          FieldRepHomeController.getMonthlyTimecardSummary(blankToNullId(params.get('contextUserId')))
        );
        return;
      }
      if (path == 'accounts-tab/page') {
        writeJson(res, 200, AccountsTabController.getAccountsTabPage(
          params.get('scope'),
          params.get('searchTerm'),
          params.get('recordTypeDeveloperName'),
          params.get('classification'),
          params.get('sortBy'),
          params.get('sortDirection'),
          toInteger(params.get('offset'), 0),
          toInteger(params.get('pageSize'), 10),
          parseDate(params.get('monthStart')),
          blankToNullId(params.get('contextUserId')),
          commaSeparatedToList(params.get('accountIds')),
          blankToNullId(params.get('brickId')),
          params.get('specialtyFilter')
        ));
        return;
      }
      if (path == 'accounts-tab/map-points') {
        writeJson(res, 200, AccountsTabController.getAccountsTabMapPoints(
          params.get('scope'),
          params.get('searchTerm'),
          params.get('recordTypeDeveloperName'),
          params.get('classification'),
          params.get('sortBy'),
          params.get('sortDirection'),
          toInteger(params.get('offset'), 0),
          toInteger(params.get('pageSize'), 5),
          parseDate(params.get('monthStart')),
          blankToNullId(params.get('contextUserId')),
          commaSeparatedToList(params.get('accountIds')),
          blankToNullId(params.get('brickId')),
          params.get('specialtyFilter')
        ));
        return;
      }
      if (path == 'accounts-tab/record-type-options') {
        writeJson(res, 200, AccountsTabController.getAccountsTabRecordTypeOptions());
        return;
      }
      writeJson(res, 404, new ErrorResponse('Unknown GET path: ' + path));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  /**
   * Lightning LWC entry point. Browser fetch to /services/apexrest returns 401
   * because a Lightning UI session is not an API session. PWA/mobile keep using REST.
   */
  @AuraEnabled
  public static Map<String, Object> getHomeDashboard(Id contextUserId) {
    try {
      return buildHomeDashboard(contextUserId);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> getTodayPlanPayload(Id contextUserId, Date planDate) {
    try {
      return buildTodayPlan(contextUserId, planDate);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> getNextBestCustomersPayload(Id contextUserId, Integer limitSize) {
    try {
      return buildNextBestCustomers(contextUserId, limitSize);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static AccountsTabController.AccountsTabPage getAccountsTabPage(
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
    try {
      return AccountsTabController.getAccountsTabPage(
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
        accountIds,
        null,
        null
      );
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static AccountsTabController.AccountsTabPage getAccountsTabMapPoints(
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
    try {
      return AccountsTabController.getAccountsTabMapPoints(
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
        accountIds,
        null,
        null
      );
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static List<AccountsTabController.RecordTypeFilterOption> getAccountsTabRecordTypeOptions() {
    try {
      return AccountsTabController.getAccountsTabRecordTypeOptions();
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @HttpPost
  global static void doPost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = req.requestURI.substringAfter('/planner/v1');
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      String body = req.requestBody == null ? '{}' : req.requestBody.toString();

      if (path == 'accounts/search') {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        String recordType = firstOrBlank(toStringList(m.get('recordTypeDeveloperNames')));
        Integer pageSize = toInteger(m.get('pageSize'), 50);
        Integer offset = 0;
        if (m.get('pageToken') != null && String.isNotBlank(String.valueOf(m.get('pageToken')))) {
          offset = Integer.valueOf(String.valueOf(m.get('pageToken')));
        }
        FieldPlannerController.AccountPageResult page = FieldPlannerController.searchAccountsPage(
          (String) m.get('searchTerm'),
          recordType,
          (String) m.get('specialty'),
          (String) m.get('classification'),
          blankToNullId((String) m.get('brickId')),
          offset,
          pageSize,
          blankToNullId((String) m.get('contextUserId'))
        );
        String nextToken = page != null && page.hasMore == true ? String.valueOf(offset + pageSize) : null;
        writeJson(
          res,
          200,
          new Map<String, Object>{
            'accounts' => page == null ? new List<Object>() : page.accounts,
            'hasMore' => page != null && page.hasMore == true,
            'totalCount' => page == null ? 0 : page.totalCount,
            'nextPageToken' => nextToken,
            'totalSize' => page == null ? 0 : page.totalCount
          }
        );
        return;
      }
      if (path == 'visits/upsert') {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        writeJson(
          res,
          200,
          FieldPlannerController.upsertVisit(
            blankToNullId((String) m.get('visitId')),
            blankToNullId((String) m.get('accountId')),
            parseDt((String) m.get('startDateTime')),
            parseDt((String) m.get('endDateTime')),
            (String) m.get('status'),
            (String) m.get('visitType'),
            (String) m.get('cancellationReason'),
            blankToNullId((String) m.get('zetaProjectId')),
            (String) m.get('visitObjective')
          )
        );
        return;
      }
      if (path == 'visits/reschedule') {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        List<Object> moves = (List<Object>) m.get('moves');
        List<Id> visitIds = new List<Id>();
        List<DateTime> starts = new List<DateTime>();
        List<DateTime> ends = new List<DateTime>();
        if (moves != null) {
          for (Object o : moves) {
            Map<String, Object> move = (Map<String, Object>) o;
            visitIds.add((Id) String.valueOf(move.get('visitId')));
            starts.add(parseDt((String) move.get('startDateTime')));
            ends.add(parseDt((String) move.get('endDateTime')));
          }
        }
        writeJson(res, 200, FieldPlannerController.rescheduleVisits(visitIds, starts, ends));
        return;
      }
      if (path == 'visits/delete') {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        FieldPlannerController.deleteVisit(blankToNullId((String) m.get('visitId')));
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }
      if (path == 'time-off') {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        writeJson(
          res,
          200,
          FieldPlannerController.createTimeOff(
            (String) m.get('typeValue'),
            (String) m.get('spanType'),
            (String) m.get('durationHours'),
            parseDt((String) m.get('startDateTime')),
            (String) m.get('comments'),
            (String) m.get('stage')
          )
        );
        return;
      }
      if (path == 'outbox') {
        writeJson(res, 200, drainOutbox(body));
        return;
      }
      writeJson(res, 404, new ErrorResponse('Unknown POST path: ' + path));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  private static OutboxResponse drainOutbox(String body) {
    OutboxRequest req = (OutboxRequest) JSON.deserialize(body, OutboxRequest.class);
    OutboxResponse response = new OutboxResponse();
    response.results = new List<OutboxResultItem>();
    if (req == null || req.actions == null) {
      return response;
    }
    for (OutboxAction action : req.actions) {
      OutboxResultItem item = new OutboxResultItem();
      item.id = action.id;
      item.visitIdByClientKey = new Map<String, String>();
      try {
        processOutboxAction(action, item);
        item.success = true;
      } catch (Exception e) {
        item.success = false;
        item.error = e.getMessage();
      }
      response.results.add(item);
    }
    return response;
  }

  private static void processOutboxAction(OutboxAction action, OutboxResultItem item) {
    Map<String, Object> payload = String.isBlank(action.payloadJson)
      ? new Map<String, Object>()
      : (Map<String, Object>) JSON.deserializeUntyped(action.payloadJson);

    if (action.actionType == 'UPSERT_VISIT') {
      FieldPlannerController.VisitSummary saved = FieldPlannerController.upsertVisit(
        blankToNullId((String) payload.get('visitId')),
        blankToNullId((String) payload.get('accountId')),
        parseDt((String) payload.get('startDateTime')),
        parseDt((String) payload.get('endDateTime')),
        (String) payload.get('status'),
        (String) payload.get('visitType'),
        (String) payload.get('cancellationReason'),
        blankToNullId((String) payload.get('zetaProjectId')),
        (String) payload.get('visitObjective')
      );
      if (saved != null && saved.id != null && String.isNotBlank(action.clientVisitKey)) {
        item.visitIdByClientKey.put(action.clientVisitKey, String.valueOf(saved.id));
      }
    } else if (action.actionType == 'RESCHEDULE_VISITS') {
      List<Object> visitIdsRaw = (List<Object>) payload.get('visitIds');
      List<Object> startsRaw = (List<Object>) payload.get('startDateTimes');
      List<Object> endsRaw = (List<Object>) payload.get('endDateTimes');
      List<Id> visitIds = new List<Id>();
      List<DateTime> starts = new List<DateTime>();
      List<DateTime> ends = new List<DateTime>();
      for (Integer i = 0; i < visitIdsRaw.size(); i++) {
        visitIds.add((Id) String.valueOf(visitIdsRaw[i]));
        starts.add(parseDt(String.valueOf(startsRaw[i])));
        ends.add(parseDt(String.valueOf(endsRaw[i])));
      }
      FieldPlannerController.rescheduleVisits(visitIds, starts, ends);
    } else if (action.actionType == 'DELETE_VISIT') {
      FieldPlannerController.deleteVisit(blankToNullId((String) payload.get('visitId')));
    } else if (action.actionType == 'CREATE_TIME_OFF') {
      FieldPlannerController.createTimeOff(
        (String) payload.get('typeValue'),
        (String) payload.get('spanType'),
        (String) payload.get('durationHours'),
        parseDt((String) payload.get('startDateTime')),
        (String) payload.get('comments'),
        (String) payload.get('stage')
      );
    } else {
      throw new AuraHandledException('Unsupported outbox action: ' + action.actionType);
    }
  }

  private static Map<String, Object> buildUiMetadata() {
    Map<String, Object> uiConfig = loadUiConfigJson();
    return new Map<String, Object>{
      'uiConfig' => uiConfig,
      'describes' => new List<Object>{ describeObject('Visit__c'), describeObject('Time_Off_Request__c'), describeObject('Account') },
      'layouts' => new List<Object>{ buildSimpleLayout('Visit__c') },
      'labels' => uiConfig.containsKey('labels') ? uiConfig.get('labels') : new Map<String, Object>(),
      'flexiPageName' => 'Field_Rep_Planner'
    };
  }

  private static SyncPullResponse buildSyncPull(String sinceIgnored) {
    SyncPullResponse pull = new SyncPullResponse();
    Date today = Date.today();
    Date weekStart = today.toStartOfWeek();
    // Pull a wide window: last 60 / next 30 days of visits via planner weeks
    Date rangeStart = today.addDays(-60);
    Date rangeEnd = today.addDays(30);
    FieldPlannerController.PlannerPayload payload = FieldPlannerController.getPlannerData(
      rangeStart,
      rangeEnd,
      null
    );
    pull.visits = payload.visits;
    pull.timeOff = payload.timeOffBlocks;
    pull.accounts = FieldPlannerController.getMapAccounts(null);
    List<FieldPlannerController.ProjectOption> projectOpts = FieldPlannerController.getPromotionalProjects(null);
    List<FieldPlannerController.ProjectOption> safeOpts = projectOpts == null
      ? new List<FieldPlannerController.ProjectOption>()
      : projectOpts;
    // Serialize as id/name for mobile client via JSON map list stored temporarily in projects field type —
    // ProjectOption list kept for Apex typing; client maps label/value when needed.
    pull.projects = safeOpts;
    pull.ui = buildUiMetadata();
    pull.cursors = new Map<String, String>{ 'pull' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') };
    return pull;
  }

  private static Map<String, Object> loadUiConfigJson() {
    // Prefer Custom Metadata Planner_UI_Config__mdt.Default if present; else defaults.
    try {
      List<SObject> rows = Database.query(
        'SELECT Config_JSON__c FROM Planner_UI_Config__mdt WHERE DeveloperName = \'Default\' LIMIT 1'
      );
      if (!rows.isEmpty()) {
        String raw = (String) rows[0].get('Config_JSON__c');
        if (String.isNotBlank(raw)) {
          return (Map<String, Object>) JSON.deserializeUntyped(raw);
        }
      }
    } catch (Exception e) {
      // CMDT may not be deployed yet
    }
    return defaultUiConfig();
  }

  private static Map<String, Object> defaultUiConfig() {
    return new Map<String, Object>{
      'version' => 1,
      'weekStartsOn' => 0,
      'showMap' => true,
      'showPromo' => true,
      'showTot' => true,
      'showAccountSidebar' => true,
      'showCollections' => true,
      'slots' => new List<String>{ 'calendar', 'sidebar', 'map', 'promo', 'tot' },
      'filters' => new Map<String, Object>{
        'showSpecialty' => true,
        'showClassification' => true,
        'showBrick' => true,
        'showRecordType' => true
      },
      'labels' => new Map<String, Object>{
        'calendar' => 'Calendar',
        'map' => 'Map & Route',
        'accounts' => 'Accounts',
        'tot' => 'Time Off',
        'promo' => 'Promo',
        'sync' => 'Sync'
      },
      'totPresets' => new List<Object>{
        new Map<String, Object>{ 'label' => 'Holiday (Full day)', 'typeValue' => 'Holiday', 'spanType' => 'Full_Day' },
        new Map<String, Object>{ 'label' => 'Sick (Full day)', 'typeValue' => 'Sick', 'spanType' => 'Full_Day' },
        new Map<String, Object>{ 'label' => 'Training (4h)', 'typeValue' => 'Training', 'spanType' => 'Hours', 'durationHours' => '4' },
        new Map<String, Object>{ 'label' => 'Travelling (2h)', 'typeValue' => 'Travelling', 'spanType' => 'Hours', 'durationHours' => '2' }
      }
    };
  }

  private static Map<String, Object> describeObject(String apiName) {
    Schema.SObjectType t = Schema.getGlobalDescribe().get(apiName);
    if (t == null) {
      return new Map<String, Object>{ 'apiName' => apiName, 'label' => apiName, 'fields' => new List<Object>() };
    }
    Schema.DescribeSObjectResult d = t.getDescribe();
    List<Object> fields = new List<Object>();
    for (Schema.SObjectField f : d.fields.getMap().values()) {
      Schema.DescribeFieldResult fd = f.getDescribe();
      List<Object> picks = new List<Object>();
      if (fd.getType() == Schema.DisplayType.Picklist || fd.getType() == Schema.DisplayType.MultiPicklist) {
        for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
          if (pe.isActive()) {
            picks.add(new Map<String, Object>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
          }
        }
      }
      fields.add(
        new Map<String, Object>{
          'apiName' => fd.getName(),
          'label' => fd.getLabel(),
          'type' => String.valueOf(fd.getType()),
          'nillable' => fd.isNillable(),
          'updateable' => fd.isUpdateable(),
          'createable' => fd.isCreateable(),
          'picklistValues' => picks
        }
      );
    }
    return new Map<String, Object>{ 'apiName' => apiName, 'label' => d.getLabel(), 'fields' => fields };
  }

  private static Map<String, Object> buildSimpleLayout(String objectApiName) {
    List<Object> fields = new List<Object>{
      new Map<String, Object>{ 'field' => 'Status__c', 'behavior' => 'Required' },
      new Map<String, Object>{ 'field' => 'Visit_Type__c', 'behavior' => 'Edit' },
      new Map<String, Object>{ 'field' => 'Visit_Objective__c', 'behavior' => 'Edit' },
      new Map<String, Object>{ 'field' => 'Visit_Notes__c', 'behavior' => 'Edit' },
      new Map<String, Object>{ 'field' => 'Cancellation_Reason__c', 'behavior' => 'Edit' }
    };
    return new Map<String, Object>{
      'objectApiName' => objectApiName,
      'sections' => new List<Object>{
        new Map<String, Object>{ 'label' => 'Visit Details', 'fields' => fields }
      }
    };
  }

  private static Map<String, Object> buildHomeDashboard(Id contextUserId) {
    Date today = Date.today();
    Date monthStart = today.toStartOfMonth();
    FieldPlannerController.PlannerPayload todayPlan = FieldRepHomeController.getTodayPlan(contextUserId, today);
    List<HomeOfficeMessageController.HomeOfficeMessageRow> messages = HomeOfficeMessageController.getActiveMessages(
      6
    );
    Id resolvedUserId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    return new Map<String, Object>{
      'asOf' => String.valueOf(today),
      'userId' => resolvedUserId,
      'metrics' => FieldRepHomeController.getHomeMetrics(contextUserId),
      'gamification' => FieldRepHomeController.getPerformanceGamification(contextUserId, monthStart),
      'rankings' => FieldRepHomeController.getPerformanceRankings(contextUserId),
      'accountCoverageRows' => FieldRepHomeController.getAccountCoverageRows(
        contextUserId,
        'All',
        null,
        null,
        null,
        null
      ),
      'messages' => messages == null ? new List<Object>() : messages,
      'todayVisits' => todayPlan == null || todayPlan.visits == null
        ? new List<Object>()
        : todayPlan.visits,
      'todayTimeOff' => todayPlan == null || todayPlan.timeOffBlocks == null
        ? new List<Object>()
        : todayPlan.timeOffBlocks,
      'nextBestCustomers' => FieldRepHomeController.getNextBestCustomers(contextUserId, 5)
    };
  }

  private static Map<String, Object> buildTodayPlan(Id contextUserId, Date planDate) {
    Date today = planDate != null ? planDate : Date.today();
    FieldPlannerController.PlannerPayload todayPlan = FieldRepHomeController.getTodayPlan(contextUserId, today);
    Id resolvedUserId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    return new Map<String, Object>{
      'userId' => resolvedUserId,
      'planDate' => String.valueOf(today),
      'visits' => todayPlan == null || todayPlan.visits == null ? new List<Object>() : todayPlan.visits,
      'timeOff' => todayPlan == null || todayPlan.timeOffBlocks == null
        ? new List<Object>()
        : todayPlan.timeOffBlocks,
      'viewerContext' => FieldPlannerController.getPlannerViewerContext()
    };
  }

  private static Map<String, Object> buildNextBestCustomers(Id contextUserId, Integer limitSize) {
    Id resolvedUserId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    List<FieldRepHomeController.NextBestCustomerRow> rows = FieldRepHomeController.getNextBestCustomers(
      contextUserId,
      limitSize
    );
    return new Map<String, Object>{
      'userId' => resolvedUserId,
      'rows' => rows == null ? new List<Object>() : rows
    };
  }

  private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
    res.statusCode = statusCode;
    res.responseBody = Blob.valueOf(JSON.serialize(payload));
  }

  private static Id blankToNullId(String value) {
    return String.isBlank(value) ? null : (Id) value;
  }

  private static Date parseDate(String value) {
    return String.isBlank(value) ? null : Date.valueOf(value);
  }

  private static DateTime parseDt(String iso) {
    if (String.isBlank(iso)) {
      return null;
    }
    String normalized = iso.replace('T', ' ').replace('Z', '');
    if (normalized.contains('.')) {
      normalized = normalized.substringBefore('.');
    }
    return DateTime.valueOfGmt(normalized);
  }

  private static Integer toInteger(Object value, Integer fallback) {
    if (value == null) {
      return fallback;
    }
    return Integer.valueOf(String.valueOf(value));
  }

  private static List<String> toStringList(Object value) {
    List<String> out = new List<String>();
    if (value == null) {
      return out;
    }
    for (Object o : (List<Object>) value) {
      out.add(String.valueOf(o));
    }
    return out;
  }

  private static List<String> commaSeparatedToList(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    return value.split(',');
  }

  private static String firstOrBlank(List<String> values) {
    if (values == null || values.isEmpty()) {
      return null;
    }
    return values[0];
  }
}