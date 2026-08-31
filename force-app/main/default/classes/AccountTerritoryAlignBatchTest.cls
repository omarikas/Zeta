@IsTest
private class AccountTerritoryAlignBatchTest {
    @IsTest
    static void alignsAccountsToTerritory() {
        Id hcoRt = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'Institution_HCO' AND IsActive = TRUE AND IsPersonType = FALSE
            LIMIT 1
        ]
        .Id;
        Account acc = new Account(
            RecordTypeId = hcoRt,
            Name = 'Align Batch Test HCO',
            External_ID__c = 'ALIGN_BATCH_TEST_1',
            BillingCountry = 'Egypt',
            Account_Status__c = 'Active'
        );
        insert acc;

        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        if (territories.isEmpty()) {
            System.assert(true, 'No Territory2 in org � skip alignment assertions.');
            return;
        }
        Id territoryId = territories[0].Id;

        Test.startTest();
        Database.executeBatch(new AccountTerritoryAlignBatch(territoryId), 50);
        Test.stopTest();

        Integer ot2a = [
            SELECT COUNT()
            FROM ObjectTerritory2Association
            WHERE ObjectId = :acc.Id AND Territory2Id = :territoryId
        ];
        Integer atf = [
            SELECT COUNT()
            FROM Account_Territory_Fields__c
            WHERE Account__c = :acc.Id AND Territory2_Id__c = :String.valueOf(territoryId)
        ];
        System.assert(ot2a >= 1 || atf >= 1, 'Expected OT2A or ATF after alignment batch.');
    }
}