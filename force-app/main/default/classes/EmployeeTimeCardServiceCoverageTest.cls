@IsTest
private class EmployeeTimeCardServiceCoverageTest {
    @IsTest
    static void ensureAndMapAndWeights() {
        Id userId = UserInfo.getUserId();
        Date nextMonth = Date.today().addMonths(1).toStartOfMonth();

        System.assertEquals(null, EmployeeTimeCardService.ensureMonthlyTimeCard(null, null));
        Employee_Time_Card__c created = EmployeeTimeCardService.ensureMonthlyTimeCard(userId, nextMonth, true);
        System.assertNotEquals(null, created);
        Employee_Time_Card__c again = EmployeeTimeCardService.ensureMonthlyTimeCard(userId, nextMonth);
        System.assertEquals(created.Id, again.Id);
        EmployeeTimeCardService.ensureMonthlyTimeCard(userId, Date.today().addMonths(2).toStartOfMonth(), false);

        System.assertEquals(1, EmployeeTimeCardService.mapFrequencyPicklist(null));
        System.assertEquals(4, EmployeeTimeCardService.mapFrequencyPicklist('Weekly'));
        System.assertEquals(2, EmployeeTimeCardService.mapFrequencyPicklist('Bi-Weekly'));
        System.assertEquals(1, EmployeeTimeCardService.mapFrequencyPicklist('Monthly'));
        System.assertEquals(1, EmployeeTimeCardService.mapFrequencyPicklist('Quarterly'));
        System.assertEquals(0, EmployeeTimeCardService.mapFrequencyPicklist('Unknown'));

        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 6; i++) {
            accounts.add(new Account(Name = 'ETC Coverage ' + i));
        }
        insert accounts;

        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        if (!territories.isEmpty()) {
            Id territoryId = territories[0].Id;
            EmployeeTimeCardService.testOverrideTerritoryIds = new Set<Id>{ territoryId };

            List<Account_Territory_Fields__c> atfs = new List<Account_Territory_Fields__c>();
            for (Account acc : accounts) {
                atfs.add(
                    new Account_Territory_Fields__c(
                        Account__c = acc.Id,
                        Territory2_Id__c = territoryId,
                        Classification__c = 'A',
                        Potential__c = 'A',
                        Is_Active__c = true
                    )
                );
            }
            insert atfs;

            Product2 product = new Product2(Name = 'ETC Product', IsActive = true);
            insert product;
            insert new Account_Territory_Product_Fields__c(
                Account__c = accounts[0].Id,
                Territory2_Id__c = territoryId,
                Product2_Id__c = product.Id,
                Target_Visit_Frequency__c = 'Weekly'
            );

            insert new Employee_Time_Card_Account_Target__c(
                Employee_Time_Card__c = created.Id,
                Account__c = accounts[0].Id,
                Target_Visit_Frequency__c = 1,
                Potentiality__c = 'A',
                Unique_Key__c = created.Id + ':' + accounts[0].Id
            );
            insert new Employee_Time_Card_Account_Target__c(
                Employee_Time_Card__c = created.Id,
                Account__c = accounts[5].Id,
                Target_Visit_Frequency__c = 1,
                Potentiality__c = 'C',
                Unique_Key__c = created.Id + ':orphan-' + accounts[5].Id
            );

            EmployeeTimeCardService.syncAccountTargets(created.Id);
            EmployeeTimeCardService.syncAccountTargetsForTimeCards(userId, new List<Id>{ created.Id });
            EmployeeTimeCardService.expandTerritoryHierarchy(new Set<Id>{ territoryId });
        } else {
            EmployeeTimeCardService.syncAccountTargets(created.Id);
            EmployeeTimeCardService.syncAccountTargetsForTimeCards(userId, new List<Id>{ created.Id });
        }

        EmployeeTimeCardService.applyVisionWeights(
            created.Id,
            new Map<String, Object>{ 'A' => 2, 'B' => null, 'C' => 1 }
        );

        Account_Territory_Fields__c atf = new Account_Territory_Fields__c(
            Classification__c = 'A',
            Potential__c = 'B'
        );
        System.assertEquals('A', EmployeeTimeCardService.resolvePotentiality(atf));
        atf.Classification__c = null;
        System.assertEquals('B', EmployeeTimeCardService.resolvePotentiality(atf));
        atf.Potential__c = null;
        System.assertEquals('Not Rated', EmployeeTimeCardService.resolvePotentiality(atf));
        System.assertEquals(false, EmployeeTimeCardService.includeAccountInPlanCycle(null));
        EmployeeTimeCardService.includeAccountInPlanCycle(accounts[0].Id);
        EmployeeTimeCardService.getEmployeeDepartment(userId);
        EmployeeTimeCardService.getEmployeeDepartmentCached(userId);
        EmployeeTimeCardService.getEmployeeDepartmentCached(userId);
        EmployeeTimeCardService.resolvePrimaryTerritoryName(userId);
        EmployeeTimeCardService.resolvePrimaryTerritoryNameCached(userId);
        EmployeeTimeCardService.resolvePrimaryTerritoryNameCached(userId);
        EmployeeTimeCardService.resolveEmployeeTerritoryIds(userId);
        EmployeeTimeCardService.loadTargetFrequencies(new List<Account_Territory_Fields__c>());
        EmployeeTimeCardService.expandTerritoryHierarchy(new Set<Id>());
        EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(new Set<Id>{ created.Id });
        EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(new List<Id>{ created.Id });
        EmployeeTimeCardService.testOverrideTerritoryIds = null;
    }
}
