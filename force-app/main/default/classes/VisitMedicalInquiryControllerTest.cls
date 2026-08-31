@IsTest
private class VisitMedicalInquiryControllerTest {
    @IsTest
    static void getMedicalInquiryContext_loadsVisit() {
        Account account = new Account(Name = 'MI Test');
        insert account;
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1)
        );
        insert visit;
        Test.startTest();
        VisitMedicalInquiryController.MedicalInquiryContext context =
            VisitMedicalInquiryController.getMedicalInquiryContext(visit.Id);
        Test.stopTest();
        System.assertEquals(visit.Id, context.visitId);
        System.assertEquals(false, context.isLocked);
        System.assert(!context.questionCategories.isEmpty());
    }

    @IsTest
    static void createMedicalInquiry_notConfigured() {
        Boolean threw = false;
        try {
            VisitMedicalInquiryController.createMedicalInquiry(new VisitMedicalInquiryController.CreateInquiryRequest());
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}