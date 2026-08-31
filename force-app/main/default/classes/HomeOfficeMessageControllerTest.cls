@IsTest
private class HomeOfficeMessageControllerTest {
    @IsTest
    static void publishAndRetrieve_allBusinessUnits() {
        Test.startTest();
        HomeOfficeMessageController.PublishResult published = HomeOfficeMessageController.publishMessage(
            'Test broadcast',
            'Hello all BUs',
            'All Business Units',
            null,
            null,
            null,
            'High'
        );
        List<HomeOfficeMessageController.HomeOfficeMessageRow> rows = HomeOfficeMessageController.getActiveMessages(5);
        List<HomeOfficeMessageController.HomeOfficeMessageRow> aliasRows = HomeOfficeMessageController.getMessages();
        HomeOfficeMessageController.getActiveMessages(0);
        Test.stopTest();

        System.assertNotEquals(null, published.recordId);
        System.assert(!rows.isEmpty(), 'Expected at least one active message');
        System.assertEquals('Test broadcast', rows[0].subject);
        System.assertEquals(true, rows[0].isHighPriority);
        System.assert(!aliasRows.isEmpty());
    }

    @IsTest
    static void publish_scopedAudiencesAndValidation() {
        Boolean threw = false;
        try {
            HomeOfficeMessageController.publishMessage(null, null, null, null, null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);

        HomeOfficeMessageController.publishMessage('BU note', 'Body', 'Business Unit', 'ALL', null, null, 'Normal');
        HomeOfficeMessageController.publishMessage('Line note', 'Body', 'Line', null, 'ALL', null, null);
        HomeOfficeMessageController.publishMessage('District note', 'Body', 'District', null, null, 'ALL', 'Normal');
        HomeOfficeMessageController.getActiveMessages(25);
    }
}
