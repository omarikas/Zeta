@IsTest private class S_TerritoryHierarchyServiceTest {
  @IsTest static void smoke() {
    TerritoryHierarchyService.getHierarchy();
    TerritoryHierarchyService.getAccessibleTerritoryIds();
    TerritoryHierarchyService.getUserTerritoryId(UserInfo.getUserId());
    TerritoryHierarchyService.getTerritoryNames(new Set<Id>());
  }
}