@IsTest private class S_TerritoryManagementControllerTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('TerritoryManagementController'));
    TerritoryManagementController.getConsoleData();
  }
}