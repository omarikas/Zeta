public with sharing class PlanCycleAdminController {
    @AuraEnabled
    public static List<Object> getYearMonthSummaries(Integer year) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getEmployeePlansForMonth(Integer year, Integer month) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getPlanTargets(Id timeCardId) {
        return new List<Object>();
    }
    @AuraEnabled
    public static void savePlanTargets(List<Object> updates) {
    }
    @AuraEnabled
    public static Id ensureEmployeePlan(Id employeeId, Integer year, Integer month) {
        return null;
    }
    @AuraEnabled
    public static Object copyPlansBetweenMonths(Integer year, Integer sourceMonth, Integer targetMonth, List<Id> employeeIds) {
        return null;
    }
}