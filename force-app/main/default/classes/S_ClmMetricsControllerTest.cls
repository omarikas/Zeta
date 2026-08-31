@IsTest private class S_ClmMetricsControllerTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('ClmMetricsController'));
    ClmMetricsController.getSessions();
    ClmMetricsController.getPresentations();
  }
}