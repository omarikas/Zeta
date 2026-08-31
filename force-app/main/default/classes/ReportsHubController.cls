public with sharing class ReportsHubController {

    public class TileTarget {
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String apiName;
        @AuraEnabled public Boolean accessible;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, TileTarget> getTileTargets() {
        Map<String, TileTarget> targets = new Map<String, TileTarget>();
        targets.put('working-days-analysis', resolveReport('Working_Days_Analysis', 'Working Days Analysis'));
        targets.put('medical-rep-360', resolveDashboard('Medical_Rep_360_Dashboard', 'Management'));
        targets.put('pharmacy-sales', resolveCustomTab('Pharmacy_Sales_Dashboard'));
        return targets;
    }

    private static TileTarget resolveReport(String developerName, String folderName) {
        TileTarget target = new TileTarget();
        target.objectApiName = 'Report';
        target.accessible = false;

        List<Report> reports = [
            SELECT Id
            FROM Report
            WHERE DeveloperName = :developerName
            AND FolderName = :folderName
            WITH USER_MODE
            LIMIT 1
        ];
        if (!reports.isEmpty()) {
            target.recordId = reports[0].Id;
            target.accessible = true;
        }
        return target;
    }

    private static TileTarget resolveDashboard(String developerName, String folderName) {
        TileTarget target = new TileTarget();
        target.objectApiName = 'Dashboard';
        target.accessible = false;

        List<Dashboard> dashboards = [
            SELECT Id
            FROM Dashboard
            WHERE DeveloperName = :developerName
            AND FolderName = :folderName
            WITH USER_MODE
            LIMIT 1
        ];
        if (!dashboards.isEmpty()) {
            target.recordId = dashboards[0].Id;
            target.accessible = true;
        }
        return target;
    }

    private static TileTarget resolveCustomTab(String tabApiName) {
        TileTarget target = new TileTarget();
        target.objectApiName = 'Tab';
        target.apiName = tabApiName;
        target.accessible = true;
        return target;
    }
}