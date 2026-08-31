@IsTest
private class CoachingModuleSeedTest {
    @IsTest
    static void testLoadTemplate() {
        Test.startTest();
        Id templateId = CoachingModuleSeed.loadTemplate();
        Test.stopTest();

        System.assertNotEquals(null, templateId);
        Coaching_Template__c template = [
            SELECT Template_Title__c, Questions_JSON__c
            FROM Coaching_Template__c
            WHERE Id = :templateId
        ];
        System.assert(template.Template_Title__c.contains('MR Call Skills'));
        System.assert(template.Questions_JSON__c.contains('Selling Skills'));
        System.assert(template.Questions_JSON__c.contains('AFB'));
    }

    @IsTest
    static void testLoadTemplateUpdatePath() {
        Id firstId = CoachingModuleSeed.loadTemplate();
        Test.startTest();
        Id secondId = CoachingModuleSeed.loadTemplate();
        Test.stopTest();
        System.assertEquals(firstId, secondId);
    }

    @IsTest
    static void testSeedDemoData() {
        Test.startTest();
        CoachingModuleSeed.SeedResult result = CoachingModuleSeed.seedDemoData(null, null);
        Test.stopTest();
        System.assertNotEquals(null, result.templateId);
        System.assertNotEquals(null, result.eventId);
        System.assert(String.isNotBlank(result.message));
    }

    @IsTest
    static void testSeedDemoDataWithUsersAndExistingTemplate() {
        Id templateId = CoachingModuleSeed.loadTemplate();
        System.assertNotEquals(null, templateId);
        Id uid = UserInfo.getUserId();
        Test.startTest();
        CoachingModuleSeed.SeedResult result = CoachingModuleSeed.seedDemoData(uid, uid);
        Test.stopTest();
        System.assertEquals(templateId, result.templateId);
        System.assertNotEquals(null, result.eventId);
        Coaching_Event__c evt = [
            SELECT Employee__c, Manager__c, Status__c, Responses_JSON__c
            FROM Coaching_Event__c
            WHERE Id = :result.eventId
        ];
        System.assertEquals(uid, evt.Employee__c);
        System.assertEquals(uid, evt.Manager__c);
        System.assertEquals('Draft', evt.Status__c);
        System.assert(String.isNotBlank(evt.Responses_JSON__c));
    }
}