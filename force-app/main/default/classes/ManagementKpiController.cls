public with sharing class ManagementKpiController {
    @AuraEnabled
    public static List<Object> getWorkforceRoster(String workforceType, String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return new List<Object>();
    }
    @AuraEnabled
    public static Object getEmployeeAttendanceDetail(Id employeeUserId, String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static Object getExecutiveOrgSnapshot() {
        return null;
    }
    @AuraEnabled
    public static List<Object> getExecutiveBuComparison() {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getExecutiveBuProductPerformance(String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return new List<Object>();
    }
    @AuraEnabled
    public static Object getProductPerformanceDrillDown(Id productId, String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static Object getTeamKpis(String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static Object getEgyptCoverageHeatMap(String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static Object getCoachingTrendDrillDown(String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static Object getCoachingMonthDrillDown(String monthKey, String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static Object getTeamClmDrillDown(String drillType, String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return null;
    }
    @AuraEnabled
    public static List<Object> getBusinessUnitOptions() {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getLineOptions(String buTerritoryId) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getDistrictOptions(String lineTerritoryId) {
        return new List<Object>();
    }
}