public with sharing class CoachingEventController {

    public class EvaluationData {
        @AuraEnabled public String templateJson;
        @AuraEnabled public String responsesJson;
        @AuraEnabled public String sectionScoresJson;
        @AuraEnabled public Decimal managerTotalScore;
        @AuraEnabled public Decimal employeeTotalScore;
        @AuraEnabled public Decimal previousScore;
        @AuraEnabled public String status;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public Id managerId;
        @AuraEnabled public Boolean selfEvaluationRequested;
        @AuraEnabled public Boolean selfEvaluationCompleted;
        @AuraEnabled public String userRole;
        @AuraEnabled public Id currentUserId;
    }

    public class SaveResult {
        @AuraEnabled public Decimal managerTotalScore;
        @AuraEnabled public Decimal employeeTotalScore;
        @AuraEnabled public String sectionScoresJson;
        @AuraEnabled public String responsesJson;
    }

    @AuraEnabled(cacheable=true)
    public static EvaluationData getEvaluationData(Id eventId) {
        if (eventId == null) {
            throw new AuraHandledException('Event Id is required.');
        }

        List<Coaching_Event__c> events = [
            SELECT Id, Employee__c, Manager__c, Status__c, Responses_JSON__c,
                   Manager_Total_Score__c, Employee_Total_Score__c, Previous_Score__c,
                   Section_Scores_JSON__c, Self_Evaluation_Requested__c, Self_Evaluation_Completed__c,
                   Coaching_Template__r.Questions_JSON__c
            FROM Coaching_Event__c
            WHERE Id = :eventId
            WITH USER_MODE
            LIMIT 1
        ];

        if (events.isEmpty()) {
            throw new AuraHandledException('Coaching event not found.');
        }

        Coaching_Event__c eventRecord = events[0];
        EvaluationData data = new EvaluationData();
        data.templateJson = eventRecord.Coaching_Template__r.Questions_JSON__c;
        data.responsesJson = eventRecord.Responses_JSON__c;
        data.sectionScoresJson = eventRecord.Section_Scores_JSON__c;
        data.managerTotalScore = eventRecord.Manager_Total_Score__c;
        data.employeeTotalScore = eventRecord.Employee_Total_Score__c;
        data.previousScore = eventRecord.Previous_Score__c;
        data.status = eventRecord.Status__c;
        data.employeeId = eventRecord.Employee__c;
        data.managerId = eventRecord.Manager__c;
        data.selfEvaluationRequested = eventRecord.Self_Evaluation_Requested__c;
        data.selfEvaluationCompleted = eventRecord.Self_Evaluation_Completed__c;
        data.currentUserId = UserInfo.getUserId();
        data.userRole = resolveUserRole(eventRecord);

        if (data.previousScore == null) {
            data.previousScore = lookupPreviousScore(eventRecord.Employee__c, eventRecord.Id);
        }

        return data;
    }

    @AuraEnabled
    public static SaveResult saveEvaluation(Id eventId, String responsesJson, String status) {
        if (eventId == null) {
            throw new AuraHandledException('Event Id is required.');
        }

        List<Coaching_Event__c> events = [
            SELECT Id, Employee__c, Manager__c, Status__c, Responses_JSON__c,
                   Coaching_Template__r.Questions_JSON__c,
                   Self_Evaluation_Requested__c, Self_Evaluation_Completed__c
            FROM Coaching_Event__c
            WHERE Id = :eventId
            WITH USER_MODE
            LIMIT 1
        ];

        if (events.isEmpty()) {
            throw new AuraHandledException('Coaching event not found.');
        }

        Coaching_Event__c eventRecord = events[0];
        String role = resolveUserRole(eventRecord);
        validateSavePermission(eventRecord, role);

        String templateJson = eventRecord.Coaching_Template__r.Questions_JSON__c;
        CoachingScoringService.ScoreResult scores =
            CoachingScoringService.computeScores(templateJson, responsesJson);

        Coaching_Event__c updateRecord = new Coaching_Event__c(
            Id = eventRecord.Id,
            Responses_JSON__c = responsesJson,
            Manager_Total_Score__c = scores.managerTotalScore,
            Employee_Total_Score__c = scores.employeeTotalScore,
            Section_Scores_JSON__c = scores.sectionScoresJson,
            Previous_Score__c = lookupPreviousScore(eventRecord.Employee__c, eventRecord.Id)
        );

        if (String.isNotBlank(status)) {
            updateRecord.Status__c = status;
        } else if (eventRecord.Status__c == 'Draft' || eventRecord.Status__c == 'Planned') {
            updateRecord.Status__c = 'Available for Scoring';
        }

        updateRecord.Recommended_Action_Plan__c = scores.recommendedActionPlan;

        if (hasEmployeeResponses(responsesJson)) {
            updateRecord.Self_Evaluation_Completed__c = true;
        }

        if (!Schema.sObjectType.Coaching_Event__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update coaching event.');
        }

        update updateRecord;

        SaveResult result = new SaveResult();
        result.managerTotalScore = scores.managerTotalScore;
        result.employeeTotalScore = scores.employeeTotalScore;
        result.sectionScoresJson = scores.sectionScoresJson;
        result.responsesJson = responsesJson;
        return result;
    }

    @AuraEnabled
    public static void requestSelfEvaluation(Id eventId) {
        if (eventId == null) {
            throw new AuraHandledException('Event Id is required.');
        }

        List<Coaching_Event__c> events = [
            SELECT Id, Manager__c
            FROM Coaching_Event__c
            WHERE Id = :eventId
            WITH USER_MODE
            LIMIT 1
        ];

        if (events.isEmpty()) {
            throw new AuraHandledException('Coaching event not found.');
        }

        if (events[0].Manager__c != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the assigned manager can request self-evaluation.');
        }

        update new Coaching_Event__c(
            Id = eventId,
            Self_Evaluation_Requested__c = true,
            Status__c = 'Available for Scoring'
        );
    }

    private static String resolveUserRole(Coaching_Event__c eventRecord) {
        Id currentUserId = UserInfo.getUserId();
        if (eventRecord.Manager__c == currentUserId) {
            return 'manager';
        }
        if (eventRecord.Employee__c == currentUserId) {
            return 'employee';
        }
        return 'admin';
    }

    private static void validateSavePermission(Coaching_Event__c eventRecord, String role) {
        if (role == 'admin') {
            return;
        }
        Id currentUserId = UserInfo.getUserId();
        if (role != 'manager' && role != 'employee') {
            throw new AuraHandledException('You do not have permission to save this evaluation.');
        }
        if (role == 'manager' && eventRecord.Manager__c != currentUserId) {
            throw new AuraHandledException('You do not have permission to save this evaluation.');
        }
        if (role == 'employee' && eventRecord.Employee__c != currentUserId) {
            throw new AuraHandledException('You do not have permission to save this evaluation.');
        }
    }

    private static Decimal lookupPreviousScore(Id employeeId, Id currentEventId) {
        if (employeeId == null) {
            return null;
        }

        List<Coaching_Event__c> priorEvents = [
            SELECT Manager_Total_Score__c
            FROM Coaching_Event__c
            WHERE Employee__c = :employeeId
              AND Status__c IN ('Closed', 'Completed')
              AND Id != :currentEventId
              AND Manager_Total_Score__c != null
            WITH USER_MODE
            ORDER BY Event_End__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];

        return priorEvents.isEmpty() ? null : priorEvents[0].Manager_Total_Score__c;
    }

    private static Boolean hasEmployeeResponses(String responsesJson) {
        if (String.isBlank(responsesJson)) {
            return false;
        }
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responsesJson);
        List<Object> answers = (List<Object>) root.get('answers');
        if (answers == null) {
            return false;
        }
        for (Object answerObj : answers) {
            Map<String, Object> answer = (Map<String, Object>) answerObj;
            if (answer.containsKey('employeeValue') && answer.get('employeeValue') != null) {
                return true;
            }
        }
        return false;
    }
}