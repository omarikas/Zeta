@IsTest
private class VisitCallReportControllerTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Dr Call Report Ctrl Test', BillingCity = 'Cairo');
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
  static void getCallReportPayload_returnsVisit() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportController.getCallReportPayload(
      visit.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload);
    System.assertNotEquals(null, payload.visit);
    System.assertEquals(visit.Id, payload.visit.id);
  }

  @IsTest
  static void cacheableLookups_doNotThrow() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.TerritoryProductOption> products =
      VisitCallReportController.getTerritoryProducts(visit.Id);
    List<VisitCallReportService.SampleInventoryOption> inventory =
      VisitCallReportController.getSampleInventoryForUser();
    List<VisitCallReportService.AttendeeCandidate> candidates =
      VisitCallReportController.searchAttendeeCandidates(visit.Id, 'Dr', 0);
    List<CLM_Presentation__c> presentations = VisitCallReportController.getActiveClmPresentations();
    Test.stopTest();

    System.assertNotEquals(null, products);
    System.assertNotEquals(null, inventory);
    System.assertNotEquals(null, candidates);
    System.assertNotEquals(null, presentations);
  }

  @IsTest
  static void saveCallReport_acceptsJsonRequest() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account WHERE Id = :visit.Account__c LIMIT 1];

    Map<String, Object> attendee = new Map<String, Object>{
      'accountId' => account.Id,
      'accountName' => account.Name,
      'role' => 'Attendee',
      'isPrimary' => true,
      'displayOrder' => 1
    };
    Map<String, Object> request = new Map<String, Object>{
      'visitId' => visit.Id,
      'status' => 'Scheduled',
      'visitObjective' => 'Json save test',
      'visitNotes' => 'Notes',
      'attendees' => new List<Object>{ attendee },
      'products' => new List<Object>(),
      'samples' => new List<Object>(),
      'clmSessions' => new List<Object>()
    };

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportController.saveCallReport(
      JSON.serialize(request)
    );
    Test.stopTest();

    System.assertEquals('Scheduled', payload.visit.status);
    System.assertEquals('Json save test', payload.visit.visitObjective);
  }
}