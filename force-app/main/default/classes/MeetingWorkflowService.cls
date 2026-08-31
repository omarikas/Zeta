public with sharing class MeetingWorkflowService {
    private static Map<String, Meeting_Workflow__c> publishedByRtCache;

    public class ActionDto {
        @AuraEnabled public String actionKey;
        @AuraEnabled public String label;
        @AuraEnabled public String targetStatus;
        @AuraEnabled public Boolean requiresReason;
        @AuraEnabled public String validationRuleSet;
        @AuraEnabled public Integer sortOrder;
    }

    public class RelatedPolicyDto {
        @AuraEnabled public String relatedObject;
        @AuraEnabled public String recordTypeFilter;
        @AuraEnabled public Boolean canCreate;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean canDelete;
        @AuraEnabled public Boolean isVisible;
    }

    public class StatusPathDto {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public Boolean isTerminal;
        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public Boolean isComplete;
    }

    public class EvaluationResult {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String status;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public Id workflowId;
        @AuraEnabled public List<String> roles;
        @AuraEnabled public Boolean canEditMeeting;
        @AuraEnabled public Boolean canDeleteMeeting;
        @AuraEnabled public List<ActionDto> actions;
        @AuraEnabled public List<RelatedPolicyDto> relatedPolicies;
        @AuraEnabled public List<StatusPathDto> statusPath;
        @AuraEnabled public String message;

        public EvaluationResult() {
            roles = new List<String>();
            actions = new List<ActionDto>();
            relatedPolicies = new List<RelatedPolicyDto>();
            statusPath = new List<StatusPathDto>();
            canEditMeeting = false;
            canDeleteMeeting = false;
        }
    }

    public class TransitionResult {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String fromStatus;
        @AuraEnabled public String toStatus;
        @AuraEnabled public String actionKey;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public static void clearCache() {
        publishedByRtCache = null;
    }

    public static Meeting_Workflow__c getPublishedWorkflow(String recordTypeDeveloperName) {
        if (String.isBlank(recordTypeDeveloperName)) {
            return null;
        }
        if (publishedByRtCache == null) {
            publishedByRtCache = new Map<String, Meeting_Workflow__c>();
            for (Meeting_Workflow__c wf : [
                SELECT
                    Id,
                    Name,
                    Meeting_Record_Type__c,
                    Version__c,
                    Is_Published__c,
                    Family__c,
                    Create_Manager_As_Approver__c,
                    Statuses_To_Calculate_Actuals__c
                FROM Meeting_Workflow__c
                WHERE Is_Published__c = TRUE
                WITH SYSTEM_MODE
            ]) {
                publishedByRtCache.put(wf.Meeting_Record_Type__c, wf);
            }
        }
        return publishedByRtCache.get(recordTypeDeveloperName);
    }

    public static EvaluationResult evaluate(Id meetingId) {
        EvaluationResult result = new EvaluationResult();
        result.meetingId = meetingId;
        if (meetingId == null) {
            result.message = 'Meeting Id is required.';
            return result;
        }

        Meeting__c meeting = [
            SELECT Id, Status__c, OwnerId, RecordType.DeveloperName
            FROM Meeting__c
            WHERE Id = :meetingId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        result.status = meeting.Status__c;
        result.recordTypeDeveloperName = meeting.RecordType.DeveloperName;

        Meeting_Workflow__c workflow = getPublishedWorkflow(meeting.RecordType.DeveloperName);
        if (workflow == null) {
            result.message = 'No published workflow for record type ' + meeting.RecordType.DeveloperName;
            return result;
        }
        result.workflowId = workflow.Id;
        result.statusPath = buildStatusPath(workflow.Id, meeting.Status__c);

        Set<String> roles = MeetingRoleResolver.resolveRoles(meetingId, UserInfo.getUserId());
        result.roles = new List<String>(roles);

        List<Meeting_WF_Role_Policy__c> policies = [
            SELECT
                Id,
                Role_Key__c,
                Can_Edit_Meeting__c,
                Can_Delete_Meeting__c,
                (SELECT Action_Key__c, Label__c, Target_Status__c, Requires_Reason__c, Validation_Rule_Set__c, Sort_Order__c FROM WF_Actions__r ORDER BY Sort_Order__c ASC NULLS LAST),
                (SELECT Related_Object__c, Record_Type_Filter__c, Can_Create__c, Can_Edit__c, Can_Delete__c, Is_Visible__c FROM Related_Policies__r)
            FROM Meeting_WF_Role_Policy__c
            WHERE Workflow__c = :workflow.Id AND Status_Value__c = :meeting.Status__c AND Role_Key__c IN :roles
            WITH SYSTEM_MODE
        ];

        Map<String, ActionDto> actionByKey = new Map<String, ActionDto>();
        Map<String, RelatedPolicyDto> relatedByKey = new Map<String, RelatedPolicyDto>();

        for (Meeting_WF_Role_Policy__c policy : policies) {
            if (policy.Can_Edit_Meeting__c) {
                result.canEditMeeting = true;
            }
            if (policy.Can_Delete_Meeting__c) {
                result.canDeleteMeeting = true;
            }
            for (Meeting_WF_Action__c action : policy.WF_Actions__r) {
                if (!actionByKey.containsKey(action.Action_Key__c)) {
                    ActionDto dto = new ActionDto();
                    dto.actionKey = action.Action_Key__c;
                    dto.label = action.Label__c;
                    dto.targetStatus = action.Target_Status__c;
                    dto.requiresReason = action.Requires_Reason__c;
                    dto.validationRuleSet = action.Validation_Rule_Set__c;
                    dto.sortOrder = action.Sort_Order__c == null ? 0 : Integer.valueOf(action.Sort_Order__c);
                    actionByKey.put(action.Action_Key__c, dto);
                }
            }
            for (Meeting_WF_Related_Policy__c related : policy.Related_Policies__r) {
                String key =
                    related.Related_Object__c +
                    '|' +
                    (related.Record_Type_Filter__c == null ? '' : related.Record_Type_Filter__c);
                RelatedPolicyDto existing = relatedByKey.get(key);
                if (existing == null) {
                    existing = new RelatedPolicyDto();
                    existing.relatedObject = related.Related_Object__c;
                    existing.recordTypeFilter = related.Record_Type_Filter__c;
                    existing.canCreate = false;
                    existing.canEdit = false;
                    existing.canDelete = false;
                    existing.isVisible = related.Is_Visible__c != false;
                    relatedByKey.put(key, existing);
                }
                if (related.Is_Visible__c == true) {
                    existing.isVisible = true;
                }
                if (related.Can_Create__c) {
                    existing.canCreate = true;
                }
                if (related.Can_Edit__c) {
                    existing.canEdit = true;
                }
                if (related.Can_Delete__c) {
                    existing.canDelete = true;
                }
            }
        }

        result.actions = actionByKey.values();
        result.actions.sort(new ActionSortComparator());
        result.relatedPolicies = relatedByKey.values();
        return result;
    }

    public static TransitionResult applyTransition(Id meetingId, String actionKey, String reason) {
        TransitionResult result = new TransitionResult();
        result.meetingId = meetingId;
        result.actionKey = actionKey;
        result.success = false;

        EvaluationResult evaluation = evaluate(meetingId);
        if (evaluation.workflowId == null) {
            result.message = evaluation.message;
            return result;
        }

        ActionDto matched;
        for (ActionDto action : evaluation.actions) {
            if (action.actionKey == actionKey) {
                matched = action;
                break;
            }
        }
        if (matched == null) {
            result.message = 'Action not allowed for current user/status: ' + actionKey;
            return result;
        }
        if (matched.requiresReason == true && String.isBlank(reason)) {
            result.message = 'A reason is required for this action.';
            return result;
        }

        Meeting__c meeting = [
            SELECT Id, Status__c, OwnerId, RecordType.DeveloperName, Was_Approved__c
            FROM Meeting__c
            WHERE Id = :meetingId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        result.fromStatus = meeting.Status__c;
        String targetStatus = matched.targetStatus;

        if (actionKey == 'SubmitForApproval') {
            targetStatus = applySkipRules(evaluation.workflowId, meeting, targetStatus);
        }

        meeting.Status__c = targetStatus;
        applySideEffects(evaluation.workflowId, result.fromStatus, targetStatus, meeting);
        update as system meeting;

        MeetingHistoryService.writeTransition(
            meeting.Id,
            result.fromStatus,
            targetStatus,
            actionKey,
            reason
        );

        result.toStatus = targetStatus;
        result.success = true;
        result.message = 'Transitioned to ' + targetStatus;
        clearCache();
        return result;
    }

    @TestVisible
    private static List<StatusPathDto> buildStatusPath(Id workflowId, String currentStatus) {
        List<StatusPathDto> path = new List<StatusPathDto>();
        List<Meeting_WF_Status__c> statuses = [
            SELECT Status_Value__c, Status_Label__c, Sort_Order__c, Is_Terminal__c
            FROM Meeting_WF_Status__c
            WHERE Workflow__c = :workflowId
            WITH SYSTEM_MODE
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];
        Integer currentOrder;
        for (Meeting_WF_Status__c statusRow : statuses) {
            if (statusRow.Status_Value__c == currentStatus && statusRow.Sort_Order__c != null) {
                currentOrder = Integer.valueOf(statusRow.Sort_Order__c);
                break;
            }
        }
        Boolean currentIsCancelled = currentStatus == 'Cancelled';
        for (Meeting_WF_Status__c statusRow : statuses) {
            if (statusRow.Status_Value__c == 'Cancelled' && !currentIsCancelled) {
                continue;
            }
            StatusPathDto dto = new StatusPathDto();
            dto.value = statusRow.Status_Value__c;
            dto.label = String.isNotBlank(statusRow.Status_Label__c)
                ? statusRow.Status_Label__c
                : statusRow.Status_Value__c;
            dto.sortOrder = statusRow.Sort_Order__c == null
                ? 0
                : Integer.valueOf(statusRow.Sort_Order__c);
            dto.isTerminal = statusRow.Is_Terminal__c == true;
            dto.isCurrent = statusRow.Status_Value__c == currentStatus;
            dto.isComplete =
                !dto.isCurrent &&
                !currentIsCancelled &&
                currentOrder != null &&
                dto.sortOrder < currentOrder;
            path.add(dto);
        }
        return path;
    }

    @TestVisible
    private static String applySkipRules(Id workflowId, Meeting__c meeting, String currentTarget) {
        List<Meeting_WF_Skip_Rule__c> rules = [
            SELECT
                Priority__c,
                Record_Types__c,
                Condition_Type__c,
                Condition_Values__c,
                From_Status__c,
                To_Status__c
            FROM Meeting_WF_Skip_Rule__c
            WHERE Workflow__c = :workflowId
            WITH SYSTEM_MODE
            ORDER BY Priority__c ASC NULLS LAST
        ];
        if (rules.isEmpty()) {
            return currentTarget;
        }

        User owner = [
            SELECT Id, Title, Profile.Name
            FROM User
            WHERE Id = :meeting.OwnerId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String working = currentTarget;
        for (Meeting_WF_Skip_Rule__c rule : rules) {
            // After Submit, evaluate skips against the action's target (usually PendingApproval).
            if (!statusMatches(rule.From_Status__c, working)) {
                continue;
            }
            if (!recordTypeAllowed(rule.Record_Types__c, meeting.RecordType.DeveloperName)) {
                continue;
            }
            if (!conditionMatches(rule, owner)) {
                continue;
            }
            working = rule.To_Status__c;
        }
        return working;
    }

    private static Boolean statusMatches(String configured, String actual) {
        return configured == '*' || configured == actual;
    }

    private static Boolean recordTypeAllowed(String configured, String rtDevName) {
        if (String.isBlank(configured) || configured == '*') {
            return true;
        }
        for (String token : configured.split('[;,]')) {
            if (token.trim() == rtDevName) {
                return true;
            }
        }
        return false;
    }

    private static Boolean conditionMatches(Meeting_WF_Skip_Rule__c rule, User owner) {
        String conditionType = rule.Condition_Type__c;
        List<String> values = splitValues(rule.Condition_Values__c);
        if (conditionType == 'Always') {
            return true;
        }
        if (conditionType == 'OwnerTitleIn') {
            return owner.Title != null && values.contains(owner.Title);
        }
        if (conditionType == 'OwnerTitleContains') {
            if (owner.Title == null) {
                return false;
            }
            for (String value : values) {
                if (owner.Title.containsIgnoreCase(value)) {
                    return true;
                }
            }
            return false;
        }
        if (conditionType == 'OwnerProfileNotIn') {
            return owner.Profile == null || !values.contains(owner.Profile.Name);
        }
        return false;
    }

    private static List<String> splitValues(String raw) {
        List<String> values = new List<String>();
        if (String.isBlank(raw)) {
            return values;
        }
        for (String token : raw.split('[;,]')) {
            String trimmed = token.trim();
            if (String.isNotBlank(trimmed)) {
                values.add(trimmed);
            }
        }
        return values;
    }

    @TestVisible
    private static void applySideEffects(Id workflowId, String fromStatus, String toStatus, Meeting__c meeting) {
        List<Meeting_WF_Side_Effect__c> effects = [
            SELECT From_Status__c, To_Status__c, Effect_Type__c, Config_JSON__c
            FROM Meeting_WF_Side_Effect__c
            WHERE Workflow__c = :workflowId
            WITH SYSTEM_MODE
        ];
        for (Meeting_WF_Side_Effect__c effect : effects) {
            if (!statusMatches(effect.From_Status__c, fromStatus) && effect.From_Status__c != '*') {
                continue;
            }
            if (!statusMatches(effect.To_Status__c, toStatus) && effect.To_Status__c != '*') {
                continue;
            }
            if (effect.Effect_Type__c == 'SetFlags') {
                if (toStatus == 'Approved') {
                    meeting.Was_Approved__c = true;
                }
                // Config_JSON can add more flags in later waves
            }
            // Notify / Validate / RecalcActuals / CustomInvocable deferred to W3/W4
        }
        if (toStatus == 'Approved') {
            meeting.Was_Approved__c = true;
        }
    }

    private class ActionSortComparator implements Comparator<ActionDto> {
        public Integer compare(ActionDto a, ActionDto b) {
            Integer left = a.sortOrder == null ? 0 : a.sortOrder;
            Integer right = b.sortOrder == null ? 0 : b.sortOrder;
            if (left == right) {
                return 0;
            }
            return left > right ? 1 : -1;
        }
    }
}