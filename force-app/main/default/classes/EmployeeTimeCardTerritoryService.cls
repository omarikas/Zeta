public without sharing class EmployeeTimeCardTerritoryService {

    private static final String HEAD_OFFICE_EXTERNAL_ID = 'TERR_HEAD_OFFICE';

    public static void syncTerritoryHierarchy(List<Id> timeCardIds) {
        syncTerritoryHierarchy(timeCardIds == null ? new Set<Id>() : new Set<Id>(timeCardIds));
    }

    public static void syncTerritoryHierarchy(Set<Id> timeCardIds) {
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }

        Map<Id, Employee_Time_Card__c> cardsById = new Map<Id, Employee_Time_Card__c>([
            SELECT Id, Employee__c
            FROM Employee_Time_Card__c
            WHERE Id IN :timeCardIds
            WITH SYSTEM_MODE
        ]);
        if (cardsById.isEmpty()) {
            return;
        }

        Set<Id> employeeIds = new Set<Id>();
        for (Employee_Time_Card__c card : cardsById.values()) {
            if (card.Employee__c != null) {
                employeeIds.add(card.Employee__c);
            }
        }

        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByEmployee =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(employeeIds);

        List<Employee_Time_Card__c> updates = new List<Employee_Time_Card__c>();
        for (Employee_Time_Card__c card : cardsById.values()) {
            TerritoryHierarchyService.HierarchyLabels labels = labelsByEmployee.get(card.Employee__c);
            if (labels == null) {
                continue;
            }
            updates.add(new Employee_Time_Card__c(
                Id = card.Id,
                Territory_BU__c = labels.businessUnit,
                Territory_Line__c = labels.line,
                Territory_District__c = labels.district
            ));
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
    }
}
