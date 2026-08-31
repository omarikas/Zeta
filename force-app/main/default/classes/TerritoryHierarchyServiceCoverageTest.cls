@IsTest
private class TerritoryHierarchyServiceCoverageTest {
    @IsTest
    static void publicApis_executeWithoutThrowing() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        System.assertEquals(0, TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(null).size());
        System.assertEquals(0, TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>()).size());
        TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>{ userId });

        TerritoryHierarchyService.getBusinessUnitOptions();
        TerritoryHierarchyService.getLineOptions(null);
        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        if (!territories.isEmpty()) {
            TerritoryHierarchyService.getLineOptions(territories[0].Id);
            TerritoryHierarchyService.getDistrictOptions(territories[0].Id);
            TerritoryHierarchyService.expandTerritoryHierarchy(new Set<Id>{ territories[0].Id });
            TerritoryHierarchyService.getTerritoryNames(new Set<Id>{ territories[0].Id });
        }
        TerritoryHierarchyService.getDistrictOptions(null);

        TerritoryHierarchyService.resolveScopedEmployeeIds(null, null, null);
        TerritoryHierarchyService.countScopedManagers(null, null, null);
        TerritoryHierarchyService.resolveScopedManagerIds(null, null, null);
        TerritoryHierarchyService.resolvePrimaryRoleByUser(new Set<Id>{ userId });
        TerritoryHierarchyService.resolvePrimaryRoleByUser(null);
        TerritoryHierarchyService.resolveScopedTerritoryIds(null, null, null);
        TerritoryHierarchyService.expandTerritoryHierarchy(new Set<Id>());

        TerritoryHierarchyService.getHierarchy();
        TerritoryHierarchyService.getAccessibleTerritoryIds();
        TerritoryHierarchyService.getUserTerritoryId(null);
        TerritoryHierarchyService.getUserTerritoryId(userId);
        TerritoryHierarchyService.getTerritoryNames(new Set<Id>());
        Test.stopTest();
    }
}
