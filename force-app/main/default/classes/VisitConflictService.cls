public with sharing class VisitConflictService {
    public static void assertNoConflicts(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Id excludeVisitId
    ) {
        if (assignedToUserId == null || startDateTime == null || endDateTime == null) {
            return;
        }
        WorkingCalendarUtil.assertWorkingDay(startDateTime);
        assertNoTotConflict(assignedToUserId, startDateTime, endDateTime);
        assertNoVisitConflict(assignedToUserId, startDateTime, endDateTime, excludeVisitId);
    }

    private static void assertNoTotConflict(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime
    ) {
        List<Time_Off_Request__c> blocks = [
            SELECT Id, Name, Type__c, Stage__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                CreatedById = :assignedToUserId
                AND Stage__c IN ('Submitted for Approval', 'Approved')
                AND Start_Date_Time__c < :endDateTime
                AND End_Date_Time__c > :startDateTime
            WITH USER_MODE
            LIMIT 1
        ];
        if (!blocks.isEmpty()) {
            Time_Off_Request__c block = blocks[0];
            String typeLabel = String.isNotBlank(block.Type__c) ? block.Type__c : 'Time off';
            throw new AuraHandledException(
                'This time overlaps with ' +
                typeLabel +
                ' (' +
                block.Stage__c +
                '). Choose another slot or adjust time off first.'
            );
        }
    }

    private static void assertNoVisitConflict(
        Id assignedToUserId,
        DateTime startDateTime,
        DateTime endDateTime,
        Id excludeVisitId
    ) {
        List<Visit__c> overlaps = [
            SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :assignedToUserId
                AND Status__c NOT IN ('Cancelled')
                AND Start_Date__c < :endDateTime
                AND End_Date__c > :startDateTime
                AND Id != :excludeVisitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!overlaps.isEmpty()) {
            Visit__c overlap = overlaps[0];
            throw new AuraHandledException(
                'This time overlaps with visit ' +
                overlap.Name +
                ' (' +
                overlap.Status__c +
                ').'
            );
        }
    }
}
