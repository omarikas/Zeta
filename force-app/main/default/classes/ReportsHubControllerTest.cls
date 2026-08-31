@IsTest
private class ReportsHubControllerTest {

    @IsTest
    static void getTileTargetsReturnsConfiguredKeys() {
        Test.startTest();
        Map<String, ReportsHubController.TileTarget> targets = ReportsHubController.getTileTargets();
        Test.stopTest();

        System.assertNotEquals(null, targets);
        System.assert(targets.containsKey('working-days-analysis'));
        System.assert(targets.containsKey('medical-rep-360'));
        System.assertEquals('Report', targets.get('working-days-analysis').objectApiName);
        System.assertEquals('Dashboard', targets.get('medical-rep-360').objectApiName);
    }
}