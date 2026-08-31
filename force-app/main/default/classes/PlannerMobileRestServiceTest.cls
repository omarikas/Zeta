@IsTest
private class PlannerMobileRestServiceTest {
  private static RestResponse invokeGetWithParams(String path, Map<String, String> params) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/' + path;
    req.httpMethod = 'GET';
    if (params != null) {
      req.params.putAll(params);
    }
    RestContext.request = req;
    RestContext.response = res;
    PlannerMobileRestService.doGet();
    return res;
  }

  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    PlannerMobileRestService.doPost();
    return res;
  }

  @IsTest
  static void getUiMetadata_returnsConfig() {
    Test.startTest();
    RestResponse res = invokeGetWithParams('ui-metadata', null);
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody != null);
  }

  @IsTest
  static void getHomeDashboard_returnsPayload() {
    Test.startTest();
    RestResponse res = invokeGetWithParams('home/dashboard', null);
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    String body = res.responseBody.toString();
    System.assert(body.contains('metrics'));
    System.assert(body.contains('todayVisits'));
    System.assert(body.contains('accountCoverageRows'));
    System.assert(body.contains('userId'));

    Map<String, Object> auraPayload = PlannerMobileRestService.getHomeDashboard(null);
    System.assertNotEquals(null, auraPayload);
    System.assert(auraPayload.containsKey('accountCoverageRows'));
    System.assert(auraPayload.containsKey('userId'));
  }

  @IsTest
  static void getTodayPlanPayload_returnsPayload() {
    Test.startTest();
    RestResponse res = invokeGetWithParams(
      'home/today-plan',
      new Map<String, String>{ 'planDate' => String.valueOf(Date.today()) }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    String body = res.responseBody.toString();
    System.assert(body.contains('visits'));
    System.assert(body.contains('userId'));
    System.assert(body.contains('viewerContext'));

    Map<String, Object> auraPayload = PlannerMobileRestService.getTodayPlanPayload(null, Date.today());
    System.assertNotEquals(null, auraPayload);
    System.assert(auraPayload.containsKey('visits'));
    System.assert(auraPayload.containsKey('userId'));
  }

  @IsTest
  static void getNextBestCustomersPayload_returnsPayload() {
    Test.startTest();
    RestResponse res = invokeGetWithParams(
      'home/next-best-customers',
      new Map<String, String>{ 'limitSize' => '5' }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    String body = res.responseBody.toString();
    System.assert(body.contains('rows'));
    System.assert(body.contains('userId'));

    Map<String, Object> auraPayload = PlannerMobileRestService.getNextBestCustomersPayload(null, 5);
    System.assertNotEquals(null, auraPayload);
    System.assert(auraPayload.containsKey('rows'));
    System.assert(auraPayload.containsKey('userId'));
  }

  @IsTest
  static void getAccountsTabRoutes_ok() {
    Test.startTest();
    RestResponse pageRes = invokeGetWithParams(
      'accounts-tab/page',
      new Map<String, String>{
        'scope' => 'both',
        'searchTerm' => '',
        'recordTypeDeveloperName' => 'All',
        'classification' => '',
        'sortBy' => 'agentforceScore',
        'sortDirection' => 'desc',
        'offset' => '0',
        'pageSize' => '10'
      }
    );
    RestResponse mapRes = invokeGetWithParams(
      'accounts-tab/map-points',
      new Map<String, String>{ 'scope' => 'both', 'pageSize' => '5' }
    );
    RestResponse optionsRes = invokeGetWithParams('accounts-tab/record-type-options', null);
    Test.stopTest();

    System.assertEquals(200, pageRes.statusCode);
    String pageBody = pageRes.responseBody.toString();
    System.assert(pageBody.contains('rows'));
    System.assert(pageBody.contains('totalCount'));
    System.assert(pageBody.contains('recordTypeCounts'));

    System.assertEquals(200, mapRes.statusCode);
    String mapBody = mapRes.responseBody.toString();
    System.assert(mapBody.contains('rows'));
    System.assert(mapBody.contains('mapEligibleCount'));

    System.assertEquals(200, optionsRes.statusCode);
    String optionsBody = optionsRes.responseBody.toString();
    System.assert(optionsBody.contains('label'));
    System.assert(optionsBody.contains('value'));

    List<AccountsTabController.RecordTypeFilterOption> options = AccountsTabController.getAccountsTabRecordTypeOptions();
    System.assertNotEquals(null, options);
    System.assert(!options.isEmpty());
  }

  @IsTest
  static void getWeekAndSyncPull_ok() {
    Date weekStart = Date.today().toStartOfWeek();
    Test.startTest();
    RestResponse weekRes = invokeGetWithParams(
      'week',
      new Map<String, String>{
        'weekStart' => String.valueOf(weekStart),
        'weekEnd' => String.valueOf(weekStart.addDays(6))
      }
    );
    RestResponse pullRes = invokeGetWithParams('sync/pull', null);
    RestResponse mapRes = invokeGetWithParams('accounts/map', null);
    RestResponse filterRes = invokeGetWithParams('accounts/filters', null);
    RestResponse rtRes = invokeGetWithParams('accounts/record-types', null);
    RestResponse projectRes = invokeGetWithParams('projects', null);
    RestResponse targetRes = invokeGetWithParams('targets', null);
    Test.stopTest();
    System.assertEquals(200, weekRes.statusCode);
    System.assertEquals(200, pullRes.statusCode);
    System.assertEquals(200, mapRes.statusCode);
    System.assertEquals(200, filterRes.statusCode);
    System.assertEquals(200, rtRes.statusCode);
    System.assertEquals(200, projectRes.statusCode);
    System.assertEquals(200, targetRes.statusCode);
  }

  @IsTest
  static void getUnknownPath_returns404() {
    Test.startTest();
    RestResponse res = invokeGetWithParams('not-a-real-path', null);
    Test.stopTest();
    System.assertEquals(404, res.statusCode);
  }

  @IsTest
  static void postOutbox_emptyActions_ok() {
    Test.startTest();
    RestResponse res = invokePost('outbox', '{"actions":[]}');
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
  }

  @IsTest
  static void postSearchAndUnknown_ok() {
    Test.startTest();
    RestResponse searchRes = invokePost(
      'accounts/search',
      '{"searchTerm":"x","recordTypeDeveloperNames":["All"],"pageSize":10}'
    );
    RestResponse unknown = invokePost('not-a-real-path', '{}');
    Test.stopTest();
    System.assertEquals(200, searchRes.statusCode);
    System.assertEquals(404, unknown.statusCode);
  }

  @IsTest
  static void postVisitTotAndOutbox_ok() {
    Account account = new Account(Name = 'Mobile Rest Visit Account');
    insert account;
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 2);
    String startIso = DateTime.newInstance(workingDay, Time.newInstance(11, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String endIso = DateTime.newInstance(workingDay, Time.newInstance(12, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

    Test.startTest();
    RestResponse upsertRes = invokePost(
      'visits/upsert',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => account.Id,
          'startDateTime' => startIso,
          'endDateTime' => endIso,
          'status' => 'Draft',
          'visitType' => 'Planned (Automatically)'
        }
      )
    );
    Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(upsertRes.responseBody.toString());
    String visitId = String.valueOf(created.get('id'));

    String laterStart = DateTime.newInstance(workingDay, Time.newInstance(13, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    String laterEnd = DateTime.newInstance(workingDay, Time.newInstance(14, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    invokePost(
      'visits/reschedule',
      JSON.serialize(
        new Map<String, Object>{
          'moves' => new List<Object>{
            new Map<String, Object>{
              'visitId' => visitId,
              'startDateTime' => laterStart,
              'endDateTime' => laterEnd
            }
          }
        }
      )
    );

    RestResponse totRes = invokePost(
      'time-off',
      JSON.serialize(
        new Map<String, Object>{
          'typeValue' => 'Holiday',
          'spanType' => 'Hours',
          'durationHours' => '2',
          'startDateTime' => laterStart,
          'comments' => 'mobile',
          'stage' => 'Draft'
        }
      )
    );

    RestResponse outboxRes = invokePost(
      'outbox',
      JSON.serialize(
        new Map<String, Object>{
          'actions' => new List<Object>{
            new Map<String, Object>{
              'id' => '1',
              'actionType' => 'UPSERT_VISIT',
              'clientVisitKey' => 'ck1',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'accountId' => account.Id,
                  'startDateTime' => startIso,
                  'endDateTime' => endIso,
                  'status' => 'Draft',
                  'visitType' => 'Planned (Automatically)'
                }
              )
            },
            new Map<String, Object>{
              'id' => '2',
              'actionType' => 'RESCHEDULE_VISITS',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'visitIds' => new List<String>{ visitId },
                  'startDateTimes' => new List<String>{ laterStart },
                  'endDateTimes' => new List<String>{ laterEnd }
                }
              )
            },
            new Map<String, Object>{
              'id' => '3',
              'actionType' => 'DELETE_VISIT',
              'payloadJson' => JSON.serialize(new Map<String, Object>{ 'visitId' => visitId })
            },
            new Map<String, Object>{
              'id' => '4',
              'actionType' => 'CREATE_TIME_OFF',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'typeValue' => 'Sick',
                  'spanType' => 'Full_Day',
                  'startDateTime' => startIso,
                  'stage' => 'Draft'
                }
              )
            },
            new Map<String, Object>{
              'id' => '5',
              'actionType' => 'UNKNOWN',
              'payloadJson' => '{}'
            }
          }
        }
      )
    );

    invokePost('visits/delete', JSON.serialize(new Map<String, Object>{ 'visitId' => visitId }));
    RestResponse weekMissing = invokeGetWithParams('week', null);
    Test.stopTest();

    System.assertEquals(200, upsertRes.statusCode);
    System.assertEquals(200, totRes.statusCode);
    System.assertEquals(200, outboxRes.statusCode);
    System.assertEquals(400, weekMissing.statusCode);
  }
}
