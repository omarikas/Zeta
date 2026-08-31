@IsTest
private class S_FieldRepHomeControllerTest {
  @IsTest
  static void smoke() {
    System.assertNotEquals(null, Type.forName('FieldRepHomeController'));
    FieldRepHomeController.getHomeMetrics(null);
    FieldRepHomeController.getTodayPlan(null, Date.today());
    FieldRepHomeController.getNextBestCustomers(null, 5);
    FieldRepHomeController.getPerformanceGamification(null, Date.today().toStartOfMonth());
    FieldRepHomeController.getPerformanceRankings(null);
  }
}
