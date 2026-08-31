public with sharing class VisitValidationController {
    public class PlanApprovalRow {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String repName;
        @AuraEnabled public String accountName;
        @AuraEnabled public DateTime startDateTime;
        @AuraEnabled public String status;
        @AuraEnabled public String visitType;
        @AuraEnabled public Id processInstanceId;
    }

    public class UnplannedReviewRow {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String repName;
        @AuraEnabled public String accountName;
        @AuraEnabled public DateTime completedAt;
        @AuraEnabled public Date validationDueDate;
        @AuraEnabled public String validationStatus;
    }

    @AuraEnabled(cacheable=true)
    public static List<PlanApprovalRow> getPendingPlanApprovals() {
        Id managerId = UserInfo.getUserId();
        List<User> directReports = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :managerId AND IsActive = TRUE
            WITH SYSTEM_MODE
        ];
        if (directReports.isEmpty()) {
            return new List<PlanApprovalRow>();
        }
        Set<Id> reportIds = new Map<Id, User>(directReports).keySet();
        Map<Id, String> reportNames = new Map<Id, String>();
        for (User rep : directReports) {
            reportNames.put(rep.Id, rep.Name);
        }

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Visit_Type__c,
                Start_Date__c,
                Assigned_To__c,
                Account__r.Name
            FROM Visit__c
            WHERE
                Assigned_To__c IN :reportIds
                AND Status__c = 'Submitted'
                AND Visit_Type__c IN ('Planned (Automatically)', 'Planned (Manager)')
            WITH SYSTEM_MODE
            ORDER BY Start_Date__c ASC
            LIMIT 200
        ];

        List<PlanApprovalRow> rows = new List<PlanApprovalRow>();
        for (Visit__c visit : visits) {
            PlanApprovalRow row = new PlanApprovalRow();
            row.visitId = visit.Id;
            row.visitName = visit.Name;
            row.repName = reportNames.get(visit.Assigned_To__c);
            row.accountName = visit.Account__r?.Name;
            row.startDateTime = visit.Start_Date__c;
            row.status = visit.Status__c;
            row.visitType = visit.Visit_Type__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<UnplannedReviewRow> getPendingUnplannedReviews() {
        Id managerId = UserInfo.getUserId();
        List<User> directReports = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :managerId AND IsActive = TRUE
            WITH SYSTEM_MODE
        ];
        if (directReports.isEmpty()) {
            return new List<UnplannedReviewRow>();
        }
        Set<Id> reportIds = new Map<Id, User>(directReports).keySet();
        Map<Id, String> reportNames = new Map<Id, String>();
        for (User rep : directReports) {
            reportNames.put(rep.Id, rep.Name);
        }

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Start_Date__c,
                Assigned_To__c,
                Validation_Status__c,
                Validation_Due_Date__c,
                Account__r.Name
            FROM Visit__c
            WHERE
                Assigned_To__c IN :reportIds
                AND Visit_Type__c = 'Unplanned'
                AND Status__c = 'Completed'
                AND Validation_Status__c = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY Validation_Due_Date__c ASC NULLS LAST, Start_Date__c DESC
            LIMIT 200
        ];

        List<UnplannedReviewRow> rows = new List<UnplannedReviewRow>();
        for (Visit__c visit : visits) {
            UnplannedReviewRow row = new UnplannedReviewRow();
            row.visitId = visit.Id;
            row.visitName = visit.Name;
            row.repName = reportNames.get(visit.Assigned_To__c);
            row.accountName = visit.Account__r?.Name;
            row.completedAt = visit.Start_Date__c;
            row.validationDueDate = visit.Validation_Due_Date__c;
            row.validationStatus = visit.Validation_Status__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void validateUnplannedVisit(Id visitId, String validationStatus) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (validationStatus != 'Valid' && validationStatus != 'Invalid') {
            throw new AuraHandledException('Validation status must be Valid or Invalid.');
        }
        Visit__c visit = [
            SELECT Id, Visit_Type__c, Status__c, Validation_Status__c, Assigned_To__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!VisitStatusHelper.isUnplannedVisitType(visit.Visit_Type__c)) {
            throw new AuraHandledException('Only unplanned visits can be validated here.');
        }
        if (visit.Status__c != VisitStatusHelper.STATUS_COMPLETED) {
            throw new AuraHandledException('Only completed unplanned visits can be validated.');
        }
        assertManagerOfRep(visit.Assigned_To__c);

        visit.Validation_Status__c = validationStatus;
        visit.Validated_By__c = UserInfo.getUserId();
        visit.Validated_At__c = System.now();
        update as system visit;
    }

    @AuraEnabled
    public static void rejectPlanVisit(Id visitId, String rejectionReason) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        Visit__c visit = [
            SELECT Id, Status__c, Visit_Type__c, Assigned_To__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (visit.Status__c != VisitStatusHelper.STATUS_SUBMITTED) {
            throw new AuraHandledException('Only submitted visits can be rejected.');
        }
        assertManagerOfRep(visit.Assigned_To__c);

        visit.Status__c = VisitStatusHelper.STATUS_DRAFT;
        visit.Plan_Rejection_Reason__c = rejectionReason;
        update as system visit;
    }

    private static void assertManagerOfRep(Id repUserId) {
        if (repUserId == null) {
            throw new AuraHandledException('Visit has no assigned rep.');
        }
        List<User> reps = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :repUserId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (reps.isEmpty() || reps[0].ManagerId != UserInfo.getUserId()) {
            throw new AuraHandledException('You can only action visits for your direct reports.');
        }
    }
}
