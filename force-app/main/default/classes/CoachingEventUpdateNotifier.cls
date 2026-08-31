/**
 * Notifies the assigned employee and manager when a coaching event is created or materially updated.
 */
public without sharing class CoachingEventUpdateNotifier {

    private static final String NOTIF_TYPE_DEV_NAME = 'Coaching_Event_Updated';

    public static void handleChanges(List<Coaching_Event__c> newRecords, Map<Id, Coaching_Event__c> oldById) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        Id notifTypeId = resolveNotificationTypeId();
        if (notifTypeId == null) {
            return;
        }

        Id actingUserId = UserInfo.getUserId();

        for (Coaching_Event__c eventRecord : newRecords) {
            Coaching_Event__c prior = oldById != null ? oldById.get(eventRecord.Id) : null;
            Boolean isInsert = prior == null;

            List<String> changes = describeChanges(eventRecord, prior, isInsert);
            if (changes.isEmpty()) {
                continue;
            }

            Set<Id> recipients = resolveRecipients(eventRecord, prior, changes, actingUserId);
            if (recipients.isEmpty()) {
                continue;
            }

            String title = isInsert ? 'New coaching event' : 'Coaching event updated';
            String body = buildBody(eventRecord.Name, changes);
            sendNotification(notifTypeId, eventRecord.Id, title, body, recipients);
        }
    }

    private static List<String> describeChanges(
        Coaching_Event__c current,
        Coaching_Event__c prior,
        Boolean isInsert
    ) {
        List<String> changes = new List<String>();

        if (isInsert) {
            changes.add('A new coaching session has been scheduled.');
            if (String.isNotBlank(current.Status__c)) {
                changes.add('Status: ' + current.Status__c);
            }
            return changes;
        }

        if (current.Status__c != prior.Status__c) {
            changes.add('Status changed to ' + current.Status__c + '.');
        }
        if (current.Manager_Total_Score__c != prior.Manager_Total_Score__c
            || current.Employee_Total_Score__c != prior.Employee_Total_Score__c) {
            String scoreLine = 'Scores updated';
            if (current.Manager_Total_Score__c != null) {
                scoreLine += ' — Manager: ' + current.Manager_Total_Score__c.setScale(1) + '%';
            }
            if (current.Employee_Total_Score__c != null) {
                scoreLine += ', Rep: ' + current.Employee_Total_Score__c.setScale(1) + '%';
            }
            changes.add(scoreLine + '.');
        }
        if (current.Self_Evaluation_Requested__c == true && prior.Self_Evaluation_Requested__c != true) {
            changes.add('Self-evaluation has been requested from the rep.');
        }
        if (current.Self_Evaluation_Completed__c == true && prior.Self_Evaluation_Completed__c != true) {
            changes.add('The rep completed their self-evaluation.');
        }
        if (String.isNotBlank(current.Recommended_Action_Plan__c)
            && current.Recommended_Action_Plan__c != prior.Recommended_Action_Plan__c
            && !changesContainsScoreUpdate(changes)) {
            changes.add('The recommended action plan was refreshed.');
        }

        return changes;
    }

    private static Boolean changesContainsScoreUpdate(List<String> changes) {
        for (String line : changes) {
            if (line.startsWith('Scores updated')) {
                return true;
            }
        }
        return false;
    }

    private static Set<Id> resolveRecipients(
        Coaching_Event__c current,
        Coaching_Event__c prior,
        List<String> changes,
        Id actingUserId
    ) {
        Set<Id> recipients = new Set<Id>();
        Boolean selfEvalRequested = containsSelfEvalRequested(changes);
        Boolean selfEvalCompleted = containsSelfEvalCompleted(changes);

        if (selfEvalRequested && current.Employee__c != null && current.Employee__c != actingUserId) {
            recipients.add(current.Employee__c);
            return recipients;
        }
        if (selfEvalCompleted && current.Manager__c != null && current.Manager__c != actingUserId) {
            recipients.add(current.Manager__c);
            return recipients;
        }

        if (current.Employee__c != null && current.Employee__c != actingUserId) {
            recipients.add(current.Employee__c);
        }
        if (current.Manager__c != null && current.Manager__c != actingUserId) {
            recipients.add(current.Manager__c);
        }
        return recipients;
    }

    private static Boolean containsSelfEvalRequested(List<String> changes) {
        for (String line : changes) {
            if (line.contains('Self-evaluation has been requested')) {
                return true;
            }
        }
        return false;
    }

    private static Boolean containsSelfEvalCompleted(List<String> changes) {
        for (String line : changes) {
            if (line.contains('completed their self-evaluation')) {
                return true;
            }
        }
        return false;
    }

    private static String buildBody(String eventName, List<String> changes) {
        String label = String.isNotBlank(eventName) ? eventName : 'Coaching event';
        return label + ': ' + String.join(changes, ' ');
    }

    private static void sendNotification(
        Id notifTypeId,
        Id targetId,
        String title,
        String body,
        Set<Id> recipientIds
    ) {
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notifTypeId);
            notification.setTargetId(targetId);
            notification.send(toStringSet(recipientIds));
        } catch (Exception e) {
            // Delivery can fail if notifications are disabled for the user or org.
        }
    }

    private static Set<String> toStringSet(Set<Id> ids) {
        Set<String> values = new Set<String>();
        for (Id recordId : ids) {
            values.add(String.valueOf(recordId));
        }
        return values;
    }

    private static Id resolveNotificationTypeId() {
        List<CustomNotificationType> rows = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }
}