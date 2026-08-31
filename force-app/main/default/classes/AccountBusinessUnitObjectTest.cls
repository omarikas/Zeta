@IsTest
private class AccountBusinessUnitObjectTest {
  @IsTest
  static void schemaIsDeployed() {
    System.assertNotEquals(null, Account_Business_Unit__c.SObjectType);
    System.assert(
      Schema.SObjectType.Account_Business_Unit__c.fields.getMap()
        .containsKey('Business_Unit_External_ID__c')
    );
  }
}