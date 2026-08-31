@IsTest
private class AccountNameCleanupBatchTest {
  @IsTest
  static void cleansNumericPrefixedNames() {
    Id recordTypeId;
    for (RecordType rt : [
      SELECT Id, DeveloperName, IsPersonType
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN ('Institution_HCO', 'Pharmacy', 'Business_Account')
      ORDER BY DeveloperName
    ]) {
      if (rt.IsPersonType != true) {
        recordTypeId = rt.Id;
        break;
      }
    }
    System.assertNotEquals(null, recordTypeId, 'Expected a business Account record type.');

    Account dirty = new Account(
      Name = '1000000240_Test Pharmacy Clean',
      RecordTypeId = recordTypeId,
      External_ID__c = 'NAMECLEAN-' + String.valueOf(Crypto.getRandomInteger())
    );
    Account clean = new Account(
      Name = 'Already Clean Pharmacy',
      RecordTypeId = recordTypeId,
      External_ID__c = 'NAMECLEAN2-' + String.valueOf(Crypto.getRandomInteger())
    );
    insert new List<Account>{ dirty, clean };

    Test.startTest();
    Integer updated = AccountNameCleanupBatch.cleanAccounts(
      new List<Account>{
        [SELECT Id, Name, External_ID__c FROM Account WHERE Id = :dirty.Id],
        [SELECT Id, Name, External_ID__c FROM Account WHERE Id = :clean.Id]
      }
    );
    Test.stopTest();

    System.assertEquals(1, updated, 'Expected one name to be cleaned.');

    Account refreshed = [
      SELECT Name, External_ID__c
      FROM Account
      WHERE Id = :dirty.Id
    ];
    System.assertEquals('Test Pharmacy Clean', refreshed.Name);
    System.assertNotEquals(null, refreshed.External_ID__c);

    System.assertEquals(
      'Already Clean Pharmacy',
      [SELECT Name FROM Account WHERE Id = :clean.Id].Name
    );
  }

  @IsTest
  static void cleanPrefixedName_helpers() {
    System.assertEquals(
      'Pharmacy Name',
      AccountNameCleanupBatch.cleanPrefixedName('12345_Pharmacy Name')
    );
    System.assertEquals(
      'No Prefix',
      AccountNameCleanupBatch.cleanPrefixedName('No Prefix')
    );
    System.assertEquals(
      'abc_Name',
      AccountNameCleanupBatch.cleanPrefixedName('abc_Name')
    );
  }
}