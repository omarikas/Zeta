public with sharing class MeetingHistoryService {
    public static void writeTransition(
        Id meetingId,
        String fromStatus,
        String toStatus,
        String actionKey,
        String reason
    ) {
        if (meetingId == null) {
            return;
        }
        Meeting_History__c row = new Meeting_History__c(
            Meeting__c = meetingId,
            From_Status__c = fromStatus,
            To_Status__c = toStatus,
            Action_Key__c = actionKey,
            Reason__c = reason,
            Changed_By__c = UserInfo.getUserId()
        );
        insert as system row;
    }

    public static void writeBulk(List<Meeting_History__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        insert as system rows;
    }
}