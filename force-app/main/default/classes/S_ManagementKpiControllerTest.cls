@IsTest private class S_ManagementKpiControllerTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('ManagementKpiController'));
    ManagementKpiController.getTeamKpis();
  }
}