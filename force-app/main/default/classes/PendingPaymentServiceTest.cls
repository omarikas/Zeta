@IsTest
private class PendingPaymentServiceTest {
  @IsTest
  static void isEnabled_falseWhenUnchecked() {
    Org_Feature_Switch__c cfg = Org_Feature_Switch__c.getOrgDefaults();
    cfg.Pending_Payment__c = false;
    upsert cfg;

    System.assertEquals(false, PendingPaymentService.isEnabled());
    System.assertEquals(false, PendingPaymentController.isPendingPayment());
  }

  @IsTest
  static void isEnabled_trueWhenChecked() {
    PendingPaymentService.enablePendingPayment();

    System.assertEquals(true, PendingPaymentService.isEnabled());
    System.assertEquals(true, PendingPaymentController.isPendingPayment());
    System.assertEquals(true, PendingPaymentController.isPendingPaymentNow());

    PendingPaymentController ctrl = new PendingPaymentController();
    System.assertEquals(true, ctrl.getIsPendingPayment());
    System.assertEquals(PendingPaymentService.WARNING_MESSAGE, ctrl.getWarningMessage());
  }
}