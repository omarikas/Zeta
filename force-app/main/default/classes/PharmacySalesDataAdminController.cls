public with sharing class PharmacySalesDataAdminController {
    @AuraEnabled
    public static String getCsvTemplate() {
        return null;
    }
    @AuraEnabled
    public static Object previewSalesDataCsv(String csvContent) {
        return null;
    }
    @AuraEnabled
    public static Object importSalesDataCsv(String csvContent, String fileName) {
        return null;
    }
    @AuraEnabled
    public static List<Object> getWithdrawalRows(Date startMonth, Date endMonth, String dataSource, Id brickId, Integer rowLimit) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getImportBatches(Integer rowLimit) {
        return new List<Object>();
    }
    @AuraEnabled
    public static void deleteWithdrawalRows(List<Id> recordIds) {
    }
    @AuraEnabled
    public static Object seedDemoData() {
        return null;
    }
}