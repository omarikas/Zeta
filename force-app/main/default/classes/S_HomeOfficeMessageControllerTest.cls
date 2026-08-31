@IsTest
private class S_HomeOfficeMessageControllerTest {
  @IsTest
  static void smoke() {
    System.assertNotEquals(null, Type.forName('HomeOfficeMessageController'));
    HomeOfficeMessageController.getMessages();
    HomeOfficeMessageController.getActiveMessages(5);
  }
}
