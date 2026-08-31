/**
 * Keeps Coaching_Event_Section_Score__c rows in sync with Section_Scores_JSON__c for reporting.
 */
public without sharing class CoachingEventSectionScoreSync {

    public static void handleChanges(List<Coaching_Event__c> newRecords, Map<Id, Coaching_Event__c> oldById) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        Map<Id, String> jsonByEventId = new Map<Id, String>();
        for (Coaching_Event__c eventRecord : newRecords) {
            Coaching_Event__c prior = oldById != null ? oldById.get(eventRecord.Id) : null;
            Boolean jsonChanged = prior == null
                || eventRecord.Section_Scores_JSON__c != prior.Section_Scores_JSON__c;
            if (jsonChanged) {
                jsonByEventId.put(eventRecord.Id, eventRecord.Section_Scores_JSON__c);
            }
        }

        if (jsonByEventId.isEmpty()) {
            return;
        }

        syncForEvents(jsonByEventId);
    }

    public static void syncForEvents(Map<Id, String> jsonByEventId) {
        if (jsonByEventId == null || jsonByEventId.isEmpty()) {
            return;
        }

        Set<Id> eventIds = jsonByEventId.keySet();
        List<Coaching_Event_Section_Score__c> existing = [
            SELECT Id, Coaching_Event__c
            FROM Coaching_Event_Section_Score__c
            WHERE Coaching_Event__c IN :eventIds
        ];
        if (!existing.isEmpty()) {
            delete existing;
        }

        List<Coaching_Event_Section_Score__c> toInsert = new List<Coaching_Event_Section_Score__c>();
        for (Id eventId : eventIds) {
            toInsert.addAll(buildRows(eventId, jsonByEventId.get(eventId)));
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    public static List<Coaching_Event_Section_Score__c> buildRows(Id eventId, String sectionScoresJson) {
        List<Coaching_Event_Section_Score__c> rows = new List<Coaching_Event_Section_Score__c>();
        if (eventId == null || String.isBlank(sectionScoresJson) || sectionScoresJson == '{}') {
            return rows;
        }

        Map<String, Object> sections = (Map<String, Object>) JSON.deserializeUntyped(sectionScoresJson);
        for (String sectionName : sections.keySet()) {
            Map<String, Object> section = (Map<String, Object>) sections.get(sectionName);
            Object managerScore = section.get('managerScore');
            Object employeeScore = section.get('employeeScore');
            rows.add(new Coaching_Event_Section_Score__c(
                Coaching_Event__c = eventId,
                Section_Name__c = sectionName,
                Manager_Score__c = managerScore == null ? null : Decimal.valueOf(String.valueOf(managerScore)),
                Employee_Score__c = employeeScore == null ? null : Decimal.valueOf(String.valueOf(employeeScore))
            ));
        }
        return rows;
    }
}