public with sharing class MendixSyncService {
    @AuraEnabled
    public static List<Object> getRecentSyncLogs() {
        return new List<Object>();
    }
    @AuraEnabled
    public static String getIntegrationStatus() {
        return null;
    }
}