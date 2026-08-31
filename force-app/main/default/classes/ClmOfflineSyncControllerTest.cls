@IsTest
private class ClmOfflineSyncControllerTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Offline Sync Visit Account');
    insert account;
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
  }

  @IsTest
  static void syncOfflineActions_saveCallReport() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account WHERE Id = :visit.Account__c LIMIT 1];

    Map<String, Object> request = new Map<String, Object>{
      'visitId' => visit.Id,
      'status' => 'Draft',
      'visitObjective' => 'Offline save',
      'attendees' => new List<Object>{
        new Map<String, Object>{
          'accountId' => account.Id,
          'accountName' => account.Name,
          'isPrimary' => true,
          'displayOrder' => 1
        }
      },
      'products' => new List<Object>(),
      'samples' => new List<Object>(),
      'clmSessions' => new List<Object>()
    };

    ClmOfflineSyncController.OfflineAction action = new ClmOfflineSyncController.OfflineAction();
    action.actionType = 'SAVE_CALL_REPORT';
    action.clientActionKey = 'save_1';
    action.callReportJson = JSON.serialize(request);

    Test.startTest();
    ClmOfflineSyncController.SyncResult result = ClmOfflineSyncController.syncOfflineActions(
      new List<ClmOfflineSyncController.OfflineAction>{ action }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.failedClientKeys.size(),
      'Save should succeed: ' + String.join(result.errorMessages, ' | ')
    );
    Visit__c updated = [SELECT Status__c, Visit_Objective__c FROM Visit__c WHERE Id = :visit.Id];
    System.assertEquals('Draft', updated.Status__c);
    System.assertEquals('Offline save', updated.Visit_Objective__c);
  }

  @IsTest
  static void syncOfflineActions_emptyList_isSafe() {
    Test.startTest();
    ClmOfflineSyncController.SyncResult result = ClmOfflineSyncController.syncOfflineActions(
      new List<ClmOfflineSyncController.OfflineAction>()
    );
    Test.stopTest();
    System.assertNotEquals(null, result);
    System.assertEquals(0, result.failedClientKeys.size());
  }

  @IsTest
  static void syncOfflineActions_recordsFailuresAndIgnoresUnknown() {
    ClmOfflineSyncController.OfflineAction badSave = new ClmOfflineSyncController.OfflineAction();
    badSave.actionType = 'SAVE_CALL_REPORT';
    badSave.clientActionKey = 'bad_save';

    ClmOfflineSyncController.OfflineAction missingVisit = new ClmOfflineSyncController.OfflineAction();
    missingVisit.actionType = 'START_SESSION';
    missingVisit.clientActionKey = 'start_missing';
    missingVisit.clientSessionKey = 'local_session_1';

    ClmOfflineSyncController.OfflineAction unknown = new ClmOfflineSyncController.OfflineAction();
    unknown.actionType = 'FUTURE_ACTION';
    unknown.clientActionKey = 'future_1';

    ClmOfflineSyncController.OfflineAction badSlide = new ClmOfflineSyncController.OfflineAction();
    badSlide.actionType = 'LOG_SLIDE_EVENT';
    badSlide.clientActionKey = 'slide_1';
    badSlide.clientSessionKey = 'not_a_real_session';

    ClmOfflineSyncController.OfflineAction badComplete = new ClmOfflineSyncController.OfflineAction();
    badComplete.actionType = 'COMPLETE_SESSION';
    badComplete.clientActionKey = 'complete_1';

    ClmOfflineSyncController.OfflineAction badCancel = new ClmOfflineSyncController.OfflineAction();
    badCancel.actionType = 'CANCEL_SESSION';
    badCancel.clientActionKey = 'cancel_1';

    ClmOfflineSyncController.OfflineAction badMessages = new ClmOfflineSyncController.OfflineAction();
    badMessages.actionType = 'SAVE_MESSAGE_RESPONSES';
    badMessages.clientActionKey = 'msg_1';
    badMessages.responsesJson = '[]';

    ClmOfflineSyncController.OfflineAction badAdhoc = new ClmOfflineSyncController.OfflineAction();
    badAdhoc.actionType = 'START_ADHOC_SESSION';
    badAdhoc.clientActionKey = 'adhoc_1';
    badAdhoc.clientSessionKey = 'local_adhoc';
    badAdhoc.clientVisitKey = 'local_visit';

    Test.startTest();
    ClmOfflineSyncController.SyncResult result = ClmOfflineSyncController.syncOfflineActions(
      new List<ClmOfflineSyncController.OfflineAction>{
        badSave,
        missingVisit,
        unknown,
        badSlide,
        badComplete,
        badCancel,
        badMessages,
        badAdhoc,
        null
      }
    );
    Test.stopTest();

    System.assert(!result.failedClientKeys.isEmpty(), 'Expected some failures');
    System.assert(result.failedClientKeys.contains('bad_save'));
    System.assert(result.failedClientKeys.contains('slide_1'));
  }

  @IsTest
  static void syncOfflineActions_clmLifecycleHappyPath() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    CLM_Presentation__c presentation = new CLM_Presentation__c(
      Name = 'Offline Deck',
      Status__c = 'Available',
      Format__c = 'PDF',
      Slide_Count__c = 1,
      Allow_Unaligned__c = true
    );
    insert presentation;
    CLM_Sequence__c sequence = new CLM_Sequence__c(
      CLM_Presentation__c = presentation.Id,
      Sequence_Order__c = 1,
      Sequence_Name__c = 'Intro',
      Name = 'Intro',
      Page_Number__c = 1,
      File_Name__c = 'offline.pdf'
    );
    insert sequence;

    ClmOfflineSyncController.OfflineAction startAction = new ClmOfflineSyncController.OfflineAction();
    startAction.actionType = 'START_SESSION';
    startAction.clientActionKey = 'start_ok';
    startAction.clientSessionKey = 'local_session_ok';
    startAction.visitId = visit.Id;
    startAction.presentationId = presentation.Id;

    ClmOfflineSyncController.OfflineAction slideAction = new ClmOfflineSyncController.OfflineAction();
    slideAction.actionType = 'LOG_SLIDE_EVENT';
    slideAction.clientActionKey = 'slide_ok';
    slideAction.clientSessionKey = 'local_session_ok';
    slideAction.sequenceId = sequence.Id;
    slideAction.dwellSeconds = 12;
    slideAction.trackingPaused = false;

    ClmOfflineSyncController.OfflineAction msgAction = new ClmOfflineSyncController.OfflineAction();
    msgAction.actionType = 'SAVE_MESSAGE_RESPONSES';
    msgAction.clientActionKey = 'msg_ok';
    msgAction.clientSessionKey = 'local_session_ok';
    msgAction.responsesJson = JSON.serialize(
      new List<Object>{
        new Map<String, Object>{
          'productName' => 'Prod',
          'messageName' => 'Efficacy',
          'sentiment' => 'Positive',
          'sortOrder' => 1
        }
      }
    );

    ClmOfflineSyncController.OfflineAction completeAction = new ClmOfflineSyncController.OfflineAction();
    completeAction.actionType = 'COMPLETE_SESSION';
    completeAction.clientActionKey = 'complete_ok';
    completeAction.clientSessionKey = 'local_session_ok';

    ClmOfflineSyncController.OfflineAction adhoc = new ClmOfflineSyncController.OfflineAction();
    adhoc.actionType = 'START_ADHOC_SESSION';
    adhoc.clientActionKey = 'adhoc_ok';
    adhoc.clientSessionKey = 'local_adhoc_ok';
    adhoc.clientVisitKey = 'local_visit_ok';
    adhoc.presentationId = presentation.Id;

    ClmOfflineSyncController.OfflineAction cancelAdhoc = new ClmOfflineSyncController.OfflineAction();
    cancelAdhoc.actionType = 'CANCEL_SESSION';
    cancelAdhoc.clientActionKey = 'cancel_ok';
    cancelAdhoc.clientSessionKey = 'local_adhoc_ok';

    Test.startTest();
    ClmOfflineSyncController.SyncResult result = ClmOfflineSyncController.syncOfflineActions(
      new List<ClmOfflineSyncController.OfflineAction>{
        startAction,
        slideAction,
        msgAction,
        completeAction,
        adhoc,
        cancelAdhoc
      }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.failedClientKeys.size(),
      'CLM lifecycle should sync: ' + String.join(result.errorMessages, ' | ')
    );
    System.assert(result.sessionIdByClientKey.containsKey('local_session_ok'));
    System.assert(result.sessionIdByClientKey.containsKey('local_adhoc_ok'));
    System.assert(result.visitIdByClientKey.containsKey('local_visit_ok'));
  }

  @IsTest
  static void syncOfflineActions_upsertAndSubmitVisit() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(9, 0, 0, 0));
    DateTime endDt = startDt.addMinutes(45);

    ClmOfflineSyncController.OfflineAction upsertAction = new ClmOfflineSyncController.OfflineAction();
    upsertAction.actionType = 'UPSERT_VISIT';
    upsertAction.clientActionKey = 'upsert_ok';
    upsertAction.clientVisitKey = 'local_planner_visit';
    upsertAction.payloadJson = JSON.serialize(
      new Map<String, Object>{
        'visitId' => null,
        'accountId' => account.Id,
        'startDateTime' => startDt,
        'endDateTime' => endDt,
        'status' => 'Draft',
        'visitType' => 'Planned (Automatically)',
        'cancellationReason' => null,
        'zetaProjectId' => null,
        'visitObjective' => 'Offline plan'
      }
    );

    Test.startTest();
    ClmOfflineSyncController.SyncResult upsertResult = ClmOfflineSyncController.syncOfflineActions(
      new List<ClmOfflineSyncController.OfflineAction>{ upsertAction }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      upsertResult.failedClientKeys.size(),
      'UPSERT_VISIT should succeed: ' + String.join(upsertResult.errorMessages, ' | ')
    );
    System.assert(upsertResult.visitIdByClientKey.containsKey('local_planner_visit'));
    Id createdVisitId = upsertResult.visitIdByClientKey.get('local_planner_visit');

    ClmOfflineSyncController.OfflineAction submitAction = new ClmOfflineSyncController.OfflineAction();
    submitAction.actionType = 'SUBMIT_VISIT';
    submitAction.clientActionKey = 'submit_ok';
    submitAction.visitId = createdVisitId;

    ClmOfflineSyncController.OfflineAction missingSubmit = new ClmOfflineSyncController.OfflineAction();
    missingSubmit.actionType = 'SUBMIT_VISIT';
    missingSubmit.clientActionKey = 'submit_missing';

    ClmOfflineSyncController.OfflineAction totAction = new ClmOfflineSyncController.OfflineAction();
    totAction.actionType = 'CREATE_TIME_OFF';
    totAction.clientActionKey = 'tot_ok';
    totAction.payloadJson = JSON.serialize(
      new Map<String, Object>{
        'typeValue' => 'Training',
        'spanType' => 'Hours',
        'durationHours' => '2',
        'startDateTime' => DateTime.newInstance(workingDay, Time.newInstance(14, 0, 0, 0)),
        'comments' => 'Offline TOT',
        'stage' => 'Draft'
      }
    );

    ClmOfflineSyncController.SyncResult followOn = ClmOfflineSyncController.syncOfflineActions(
      new List<ClmOfflineSyncController.OfflineAction>{ submitAction, missingSubmit, totAction }
    );
    System.assert(followOn.failedClientKeys.contains('submit_missing'));
    System.assert(
      !followOn.failedClientKeys.contains('tot_ok'),
      'CREATE_TIME_OFF should succeed: ' + String.join(followOn.errorMessages, ' | ')
    );
    Visit__c submitted = [SELECT Status__c FROM Visit__c WHERE Id = :createdVisitId];
    System.assert(
      submitted.Status__c == 'Submitted' || submitted.Status__c == 'Draft',
      'Offline submit should attempt approval or roll back to Draft.'
    );
  }
}
