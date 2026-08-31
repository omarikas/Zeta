@IsTest private class S_ClmAdminControllerTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('ClmAdminController'));
    ClmAdminController.getAdminData();
  }
}