@IsTest private class S_EmployeeTimeCardTerritoryServiceTest {
  @IsTest static void smoke() {
    EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(new Set<Id>());
    EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(new List<Id>());
  }
}