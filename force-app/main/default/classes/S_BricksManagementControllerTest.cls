@IsTest
private class S_BricksManagementControllerTest {
    @IsTest
    static void smoke() {
        BricksManagementController.listBricks();
        BricksManagementController.BrickUpsertInput input = new BricksManagementController.BrickUpsertInput();
        input.name = 'Test';
        BricksManagementController.upsertBrick(input);
        BricksManagementController.listPharmacies(null);
        BricksManagementController.getBricksByTerritory(null);
        BricksManagementController.getBrickPharmacies(null);
        BricksManagementController.searchPharmacyOptions('x');
        BricksManagementController.assignBrickToTerritory(null, null);
        BricksManagementController.deleteBrick(null);
        BricksManagementController.addPharmacyToBrick(null, null);
        BricksManagementController.removePharmacyFromBrick(null);
        BricksManagementController.seedBrickDemoData();
    }
}
