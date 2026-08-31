@IsTest private class S_AccountsTabControllerTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('AccountsTabController'));
    AccountsTabController.getRecordTypeOptions();
    AccountsTabController.getAccountsPage(new AccountsTabController.AccountsTabQuery());
  }
}