@IsTest
private class S_FieldPlannerControllerTest {
  @IsTest
  static void smoke() {
    System.assertNotEquals(null, Type.forName('FieldPlannerController'));
    Date weekStart = Date.today().toStartOfWeek();
    FieldPlannerController.PlannerPayload payload = FieldPlannerController.getPlannerData(
      weekStart,
      weekStart.addDays(6),
      null
    );
    System.assertNotEquals(null, payload);
    System.assertNotEquals(null, FieldPlannerController.getPlannerAccountRecordTypes());
  }
}
