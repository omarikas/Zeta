@IsTest
private class AccountAffiliationControllerTest {
  @IsTest
  static void picklistMethods_returnActiveValues() {
    Test.startTest();
    List<AccountAffiliationController.PicklistOption> types =
      AccountAffiliationController.getRelationTypePicklistValues();
    List<AccountAffiliationController.PicklistOption> roles =
      AccountAffiliationController.getRolePicklistValues();
    List<AccountAffiliationController.PicklistOption> strengths =
      AccountAffiliationController.getStrengthPicklistValues();
    Object emptyGraph = AccountAffiliationController.getAccountAffiliations(null, null, 0, 25);
    Test.stopTest();

    System.assert(!types.isEmpty(), 'Expected affiliation type values');
    System.assert(!roles.isEmpty(), 'Expected role values');
    System.assert(!strengths.isEmpty(), 'Expected strength values');
    System.assertNotEquals(null, emptyGraph);
  }

  @IsTest
  static void getAccountDetails_returnsName() {
    Account account = new Account(Name = 'Affiliation Details Test');
    insert account;

    Test.startTest();
    Map<String, Object> details = (Map<String, Object>) AccountAffiliationController.getAccountDetails(
      account.Id
    );
    Test.stopTest();

    System.assertEquals(account.Id, details.get('id'));
    System.assertEquals('Affiliation Details Test', details.get('name'));
  }
}
