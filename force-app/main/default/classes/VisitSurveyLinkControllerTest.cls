@IsTest
private class VisitSurveyLinkControllerTest {
  @TestSetup
  static void setupData() {
    Account acct = new Account(
      Name = 'Dr Ahmed Hassan',
      Phone = '+20 100 111 2222'
    );
    insert acct;

    Visit__c visit = new Visit__c(
      Account__c = acct.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Draft',
      Start_Date__c = DateTime.now().addDays(1),
      End_Date__c = DateTime.now().addDays(1).addHours(1)
    );
    insert visit;

    insert new Visit_Attendee__c(
      Visit__c = visit.Id,
      Account__c = acct.Id
    );
  }

  @IsTest
  static void buildsSurveyContextAndMessage() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    VisitSurveyLinkController.WhatsAppSurveyContext context = VisitSurveyLinkController.getWhatsAppSurveyContext(
      visit.Id
    );
    String surveyUrl = VisitSurveyLinkController.buildSurveyUrl(visit.Id, 'ZetaMed');
    String message = VisitSurveyLinkController.buildWhatsAppMessage(
      'Ahmed',
      'ZetaMed',
      surveyUrl
    );
    Test.stopTest();

    System.assert(!context.phoneOptions.isEmpty());
    System.assert(surveyUrl.contains('visitId='));
    System.assert(message.contains('Ahmed'));
    System.assert(message.contains('ZetaMed'));
    System.assertEquals(
      '201001112222',
      VisitSurveyLinkController.digitsOnlyPhone('+20 100 111 2222')
    );
    System.assertEquals('Dr', VisitSurveyLinkController.extractFirstName('Dr Ahmed Hassan'));
    System.assertEquals(
      'Ahmed',
      VisitSurveyLinkController.extractDoctorGreetingName('Dr Ahmed Hassan')
    );
    String reminder = VisitSurveyLinkController.buildMeetingReminderMessage(
      visit.Id,
      'Dr Ahmed Hassan'
    );
    System.assert(reminder.contains('Hello Dr. Ahmed,'));
    System.assert(reminder.contains('Looking forward to meeting you today at'));
    System.assert(reminder.startsWith('Hello Dr. Ahmed,'));
  }
}