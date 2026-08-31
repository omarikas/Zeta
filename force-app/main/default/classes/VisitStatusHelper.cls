public with sharing class VisitStatusHelper {
    public class RepairResult {
        @AuraEnabled public Integer futureCompletedReset;
        @AuraEnabled public Integer cancelledReasonFilled;
        @AuraEnabled public String message;

        public RepairResult() {
            futureCompletedReset = 0;
            cancelledReasonFilled = 0;
        }
    }

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_SCHEDULED = 'Scheduled';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_CANCELLED = 'Cancelled';

    public static final String TYPE_UNPLANNED = 'Unplanned';
    public static final String TYPE_PLANNED_AUTO = 'Planned (Automatically)';
    public static final String TYPE_PLANNED_MANAGER = 'Planned (Manager)';

    public static Date visitDay(DateTime startDateTime) {
        return startDateTime == null ? null : startDateTime.date();
    }

    public static Boolean isFutureVisitDay(DateTime startDateTime) {
        Date day = visitDay(startDateTime);
        return day != null && day > Date.today();
    }

    public static Boolean isPlannedVisitType(String visitType) {
        return visitType == TYPE_PLANNED_AUTO || visitType == TYPE_PLANNED_MANAGER;
    }

    public static Boolean isUnplannedVisitType(String visitType) {
        return visitType == TYPE_UNPLANNED;
    }

    public static void validateStatusChange(String status, DateTime startDateTime, String cancellationReason) {
        if (String.isBlank(status)) {
            return;
        }
        if (STATUS_CANCELLED == status && String.isBlank(cancellationReason)) {
            throw new AuraHandledException('Cancellation reason is required when cancelling a visit.');
        }
        if (STATUS_COMPLETED == status && isFutureVisitDay(startDateTime)) {
            throw new AuraHandledException('A visit cannot be marked Completed before its scheduled date.');
        }
    }

    public static void assertTransitionAllowed(
        String currentStatus,
        String newStatus,
        String visitType,
        Boolean allowApprovalTransition
    ) {
        if (String.isBlank(newStatus) || newStatus == currentStatus) {
            return;
        }

        if (isUnplannedVisitType(visitType)) {
            assertUnplannedTransition(currentStatus, newStatus);
            return;
        }

        assertPlannedTransition(currentStatus, newStatus, allowApprovalTransition == true);
    }

    private static void assertUnplannedTransition(String currentStatus, String newStatus) {
        Set<String> allowed = new Set<String>();
        if (String.isBlank(currentStatus)) {
            allowed.add(STATUS_SCHEDULED);
        } else if (currentStatus == STATUS_SCHEDULED) {
            allowed.addAll(new List<String>{ STATUS_COMPLETED, STATUS_CANCELLED });
        }
        if (!allowed.contains(newStatus)) {
            throw new AuraHandledException(
                'Unplanned visits follow Scheduled → Completed/Cancelled. Cannot change status from ' +
                currentStatus +
                ' to ' +
                newStatus +
                '.'
            );
        }
    }

    private static void assertPlannedTransition(
        String currentStatus,
        String newStatus,
        Boolean allowApprovalTransition
    ) {
        Set<String> allowed = new Set<String>();
        if (String.isBlank(currentStatus) || currentStatus == STATUS_DRAFT) {
            allowed.addAll(new List<String>{ STATUS_DRAFT, STATUS_SUBMITTED });
        } else if (currentStatus == STATUS_SUBMITTED) {
            if (allowApprovalTransition) {
                allowed.addAll(new List<String>{ STATUS_SCHEDULED, STATUS_DRAFT });
            }
        } else if (currentStatus == STATUS_SCHEDULED) {
            allowed.addAll(
                new List<String>{ STATUS_COMPLETED, STATUS_CANCELLED, STATUS_SUBMITTED, STATUS_SCHEDULED }
            );
        } else if (currentStatus == STATUS_RESCHEDULED_LEGACY()) {
            allowed.addAll(new List<String>{ STATUS_SUBMITTED, STATUS_SCHEDULED, STATUS_CANCELLED });
        }

        if (!allowed.contains(newStatus)) {
            throw new AuraHandledException(
                'Invalid status change from ' + currentStatus + ' to ' + newStatus + ' for a planned visit.'
            );
        }
    }

    private static String STATUS_RESCHEDULED_LEGACY() {
        return 'Rescheduled';
    }

    public static Boolean isLockedStatus(String status) {
        return status == STATUS_COMPLETED || status == STATUS_CANCELLED;
    }

    public static Boolean isPendingApproval(String status) {
        return status == STATUS_SUBMITTED;
    }

    public static void applyUnplannedCompletionValidation(Visit__c visit) {
        if (visit == null || !isUnplannedVisitType(visit.Visit_Type__c)) {
            return;
        }
        visit.Validation_Status__c = 'Pending';
        visit.Validation_Due_Date__c = WorkingCalendarUtil.addWorkingDays(
            Date.today(),
            WorkingCalendarUtil.DEFAULT_VALIDATION_DUE_WORKING_DAYS
        );
    }

    /**
     * Demo seed helper: past visits may be Completed or Cancelled; today/future stay open.
     */
    public static String resolveDemoStatus(Date visitDay, Integer slotIndex) {
        Integer slot = slotIndex == null ? 0 : slotIndex;
        if (visitDay == null) {
            return STATUS_DRAFT;
        }
        if (visitDay > Date.today()) {
            return Math.mod(slot, 3) == 0 ? STATUS_DRAFT : STATUS_SCHEDULED;
        }
        if (visitDay == Date.today()) {
            return STATUS_SCHEDULED;
        }
        return Math.mod(slot, 7) == 0 ? STATUS_CANCELLED : STATUS_COMPLETED;
    }

    public static String defaultCancellationReason() {
        return 'HCP unavailable — visit rescheduled.';
    }

    public static void applyCancelledReason(Visit__c visit) {
        if (visit != null && visit.Status__c == STATUS_CANCELLED && String.isBlank(visit.Cancellation_Reason__c)) {
            visit.Cancellation_Reason__c = defaultCancellationReason();
        }
    }

    public static RepairResult repairInvalidVisitStatuses() {
        RepairResult result = new RepairResult();
        DateTime nextDayStart = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));

        List<Visit__c> futureCompleted = [
            SELECT Id, Status__c, Start_Date__c
            FROM Visit__c
            WHERE Status__c = 'Completed' AND Start_Date__c >= :nextDayStart
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        for (Visit__c visit : futureCompleted) {
            visit.Status__c = STATUS_SCHEDULED;
            visit.Cancellation_Reason__c = null;
        }
        if (!futureCompleted.isEmpty()) {
            update as system futureCompleted;
            result.futureCompletedReset = futureCompleted.size();
        }

        List<Visit__c> cancelledVisits = [
            SELECT Id, Status__c, Cancellation_Reason__c
            FROM Visit__c
            WHERE Status__c = 'Cancelled'
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        List<Visit__c> cancelledMissingReason = new List<Visit__c>();
        for (Visit__c visit : cancelledVisits) {
            if (String.isBlank(visit.Cancellation_Reason__c)) {
                visit.Cancellation_Reason__c = defaultCancellationReason();
                cancelledMissingReason.add(visit);
            }
        }
        if (!cancelledMissingReason.isEmpty()) {
            update as system cancelledMissingReason;
            result.cancelledReasonFilled = cancelledMissingReason.size();
        }

        result.message = 'Reset ' + result.futureCompletedReset +
            ' future Completed visit(s) and filled ' + result.cancelledReasonFilled +
            ' missing cancellation reason(s).';
        return result;
    }
}
