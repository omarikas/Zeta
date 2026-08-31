public without sharing class MeetingWorkflowSeed {
    public class SeedResult {
        @AuraEnabled public Integer workflowsCreated;
        @AuraEnabled public Integer workflowsPublished;
        @AuraEnabled public String message;

        public SeedResult() {
            workflowsCreated = 0;
            workflowsPublished = 0;
        }
    }

    private static final List<String> GPM_TYPES = new List<String>{
        'Speaker_Meeting',
        'Regional_Standalone',
        'National_Standalone',
        'Advisory_Board'
    };
    private static final List<String> NLM_TYPES = new List<String>{
        'RTD',
        'AV_Action',
        'Promotional_Activity'
    };

    public static SeedResult seedStandardTemplates(Boolean publish) {
        SeedResult result = new SeedResult();
        for (String rt : GPM_TYPES) {
            Id wfId = ensureTemplate(rt, 'GPM', midStatusFor('GPM'));
            result.workflowsCreated++;
            if (publish == true) {
                MeetingWorkflowPublisher.PublishResult pub = MeetingWorkflowPublisher.publish(wfId);
                if (pub.success) {
                    result.workflowsPublished++;
                }
            }
        }
        for (String rt : NLM_TYPES) {
            Id wfId = ensureTemplate(rt, 'NLM', midStatusFor('NLM'));
            result.workflowsCreated++;
            if (publish == true) {
                MeetingWorkflowPublisher.PublishResult pub = MeetingWorkflowPublisher.publish(wfId);
                if (pub.success) {
                    result.workflowsPublished++;
                }
            }
        }
        result.message =
            'Created ' +
            result.workflowsCreated +
            ' workflows; published ' +
            result.workflowsPublished;
        return result;
    }

    private static String midStatusFor(String family) {
        return family == 'NLM' ? 'Pending NLM Approval' : 'Pending GPM Approval';
    }

    private static Id ensureTemplate(String recordTypeDevName, String family, String midStatus) {
        List<Meeting_Workflow__c> existing = [
            SELECT Id
            FROM Meeting_Workflow__c
            WHERE Meeting_Record_Type__c = :recordTypeDevName AND Is_Published__c = FALSE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Meeting_Workflow__c workflow = new Meeting_Workflow__c(
            Name = recordTypeDevName + ' - ' + family + ' Standard',
            Meeting_Record_Type__c = recordTypeDevName,
            Description__c = family + ' Standard template seeded for Wave 1.',
            Version__c = 0,
            Is_Published__c = false,
            Is_Draft__c = true,
            Create_Manager_As_Approver__c = true,
            Family__c = family,
            Statuses_To_Calculate_Actuals__c = 'Approved;Closed;Cancelled'
        );
        insert workflow;

        insertStatuses(workflow.Id, midStatus);
        insertApproverRule(workflow.Id, family);
        insertSkipRules(workflow.Id, family, recordTypeDevName);
        insertSideEffects(workflow.Id);
        Map<String, Id> policyIds = insertRolePolicies(workflow.Id, midStatus, family);
        insertRelatedPolicies(policyIds);
        return workflow.Id;
    }

    private static void insertStatuses(Id workflowId, String midStatus) {
        List<Meeting_WF_Status__c> statuses = new List<Meeting_WF_Status__c>{
            statusRow(workflowId, 'Draft', 'Draft', 10, false),
            statusRow(workflowId, 'PendingApproval', 'Pending Approval', 20, false),
            statusRow(workflowId, midStatus, midStatus, 30, false),
            statusRow(workflowId, 'Approved', 'Approved', 40, false),
            statusRow(workflowId, 'Closed', 'Closed', 50, true),
            statusRow(workflowId, 'Cancelled', 'Cancelled', 60, true)
        };
        insert statuses;
    }

    private static Meeting_WF_Status__c statusRow(
        Id workflowId,
        String value,
        String label,
        Integer sortOrder,
        Boolean terminal
    ) {
        return new Meeting_WF_Status__c(
            Workflow__c = workflowId,
            Status_Value__c = value,
            Status_Label__c = label,
            Sort_Order__c = sortOrder,
            Is_Terminal__c = terminal
        );
    }

    private static void insertApproverRule(Id workflowId, String family) {
        insert new Meeting_WF_Approver_Rule__c(
            Workflow__c = workflowId,
            First_Approver_Mode__c = 'OwnerManager',
            Second_Approver_Mode__c = family == 'NLM' ? 'OwnerManagerManager' : 'UsersInRole',
            Second_Approver_Roles__c = family == 'GPM' ? 'Group_Product_Manager' : null
        );
    }

    private static void insertSkipRules(Id workflowId, String family, String recordTypeDevName) {
        List<Meeting_WF_Skip_Rule__c> rules = new List<Meeting_WF_Skip_Rule__c>();
        if (family == 'GPM') {
            rules.add(
                new Meeting_WF_Skip_Rule__c(
                    Workflow__c = workflowId,
                    Priority__c = 10,
                    Record_Types__c = recordTypeDevName,
                    Condition_Type__c = 'OwnerTitleIn',
                    Condition_Values__c = 'National Line Manager',
                    From_Status__c = 'PendingApproval',
                    To_Status__c = 'Pending GPM Approval'
                )
            );
            rules.add(
                new Meeting_WF_Skip_Rule__c(
                    Workflow__c = workflowId,
                    Priority__c = 20,
                    Record_Types__c = recordTypeDevName,
                    Condition_Type__c = 'OwnerTitleContains',
                    Condition_Values__c = 'Product',
                    From_Status__c = 'PendingApproval',
                    To_Status__c = 'Approved'
                )
            );
        } else {
            rules.add(
                new Meeting_WF_Skip_Rule__c(
                    Workflow__c = workflowId,
                    Priority__c = 10,
                    Record_Types__c = recordTypeDevName,
                    Condition_Type__c = 'OwnerProfileNotIn',
                    Condition_Values__c = 'Sales Rep',
                    From_Status__c = 'PendingApproval',
                    To_Status__c = 'Approved'
                )
            );
        }
        insert rules;
    }

    private static void insertSideEffects(Id workflowId) {
        insert new List<Meeting_WF_Side_Effect__c>{
            new Meeting_WF_Side_Effect__c(
                Workflow__c = workflowId,
                From_Status__c = '*',
                To_Status__c = 'Approved',
                Effect_Type__c = 'SetFlags',
                Config_JSON__c = '{"Was_Approved__c":true}'
            ),
            new Meeting_WF_Side_Effect__c(
                Workflow__c = workflowId,
                From_Status__c = '*',
                To_Status__c = '*',
                Effect_Type__c = 'WriteHistory',
                Config_JSON__c = '{}'
            )
        };
    }

    private static Map<String, Id> insertRolePolicies(Id workflowId, String midStatus, String family) {
        Map<String, Id> policyIds = new Map<String, Id>();
        List<Meeting_WF_Role_Policy__c> policies = new List<Meeting_WF_Role_Policy__c>();
        Map<String, Meeting_WF_Role_Policy__c> keyed = new Map<String, Meeting_WF_Role_Policy__c>();

        // Draft
        keyed.put('Draft|Organizer', policy(workflowId, 'Draft', 'Organizer', true, false));
        keyed.put('Draft|SuperUser', policy(workflowId, 'Draft', 'SuperUser', true, true));
        keyed.put('Draft|Approver', policy(workflowId, 'Draft', 'Approver', false, false));
        keyed.put('Draft|SecondApprover', policy(workflowId, 'Draft', 'SecondApprover', false, false));
        keyed.put('Draft|Participant', policy(workflowId, 'Draft', 'Participant', false, false));

        // PendingApproval
        keyed.put('PendingApproval|Organizer', policy(workflowId, 'PendingApproval', 'Organizer', false, false));
        keyed.put('PendingApproval|Approver', policy(workflowId, 'PendingApproval', 'Approver', false, false));
        keyed.put('PendingApproval|SecondApprover', policy(workflowId, 'PendingApproval', 'SecondApprover', false, false));
        keyed.put('PendingApproval|SuperUser', policy(workflowId, 'PendingApproval', 'SuperUser', true, false));

        // Mid status
        keyed.put(midStatus + '|Organizer', policy(workflowId, midStatus, 'Organizer', false, false));
        keyed.put(midStatus + '|Approver', policy(workflowId, midStatus, 'Approver', false, false));
        keyed.put(midStatus + '|SecondApprover', policy(workflowId, midStatus, 'SecondApprover', false, false));
        keyed.put(midStatus + '|SuperUser', policy(workflowId, midStatus, 'SuperUser', true, false));

        // Approved
        keyed.put('Approved|Organizer', policy(workflowId, 'Approved', 'Organizer', true, false));
        keyed.put('Approved|SuperUser', policy(workflowId, 'Approved', 'SuperUser', true, false));
        keyed.put('Approved|Approver', policy(workflowId, 'Approved', 'Approver', false, false));
        keyed.put('Approved|SecondApprover', policy(workflowId, 'Approved', 'SecondApprover', false, false));

        // Closed / Cancelled
        keyed.put('Closed|Organizer', policy(workflowId, 'Closed', 'Organizer', false, false));
        keyed.put('Closed|SuperUser', policy(workflowId, 'Closed', 'SuperUser', false, false));
        keyed.put('Cancelled|Organizer', policy(workflowId, 'Cancelled', 'Organizer', false, false));
        keyed.put('Cancelled|SuperUser', policy(workflowId, 'Cancelled', 'SuperUser', false, false));

        policies.addAll(keyed.values());
        insert policies;
        for (String key : keyed.keySet()) {
            policyIds.put(key, keyed.get(key).Id);
        }

        List<Meeting_WF_Action__c> actions = new List<Meeting_WF_Action__c>();
        actions.add(action(policyIds.get('Draft|Organizer'), 'SubmitForApproval', 'Submit for Approval', 'PendingApproval', false, 10));
        actions.add(action(policyIds.get('Draft|Organizer'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 20));
        actions.add(action(policyIds.get('Draft|SuperUser'), 'SubmitForApproval', 'Submit for Approval', 'PendingApproval', false, 10));
        actions.add(action(policyIds.get('Draft|SuperUser'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 20));

        actions.add(action(policyIds.get('PendingApproval|Approver'), 'Approve', 'Approve', midStatus, false, 10));
        actions.add(action(policyIds.get('PendingApproval|Approver'), 'Reject', 'Reject', 'Draft', true, 20));
        actions.add(action(policyIds.get('PendingApproval|Approver'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 30));
        actions.add(action(policyIds.get('PendingApproval|Organizer'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 10));
        actions.add(action(policyIds.get('PendingApproval|SuperUser'), 'Approve', 'Approve', midStatus, false, 10));
        actions.add(action(policyIds.get('PendingApproval|SuperUser'), 'Reject', 'Reject', 'Draft', true, 20));

        actions.add(action(policyIds.get(midStatus + '|SecondApprover'), 'Approve', 'Approve', 'Approved', false, 10));
        actions.add(action(policyIds.get(midStatus + '|SecondApprover'), 'Reject', 'Reject', 'Draft', true, 20));
        actions.add(action(policyIds.get(midStatus + '|SuperUser'), 'Approve', 'Approve', 'Approved', false, 10));
        actions.add(action(policyIds.get(midStatus + '|SuperUser'), 'Reject', 'Reject', 'Draft', true, 20));
        actions.add(action(policyIds.get(midStatus + '|Organizer'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 10));

        actions.add(action(policyIds.get('Approved|Organizer'), 'Close', 'Close', 'Closed', false, 10));
        actions.add(action(policyIds.get('Approved|Organizer'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 20));
        actions.add(action(policyIds.get('Approved|Organizer'), 'Resubmit', 'Resubmit', 'PendingApproval', true, 30));
        actions.add(action(policyIds.get('Approved|SuperUser'), 'Close', 'Close', 'Closed', false, 10));
        actions.add(action(policyIds.get('Approved|SuperUser'), 'CancelMeeting', 'Cancel Meeting', 'Cancelled', true, 20));
        actions.add(action(policyIds.get('Approved|SuperUser'), 'Resubmit', 'Resubmit', 'PendingApproval', true, 30));

        insert actions;
        return policyIds;
    }

    private static Meeting_WF_Role_Policy__c policy(
        Id workflowId,
        String statusValue,
        String roleKey,
        Boolean canEdit,
        Boolean canDelete
    ) {
        return new Meeting_WF_Role_Policy__c(
            Workflow__c = workflowId,
            Status_Value__c = statusValue,
            Role_Key__c = roleKey,
            Can_Edit_Meeting__c = canEdit,
            Can_Delete_Meeting__c = canDelete
        );
    }

    private static Meeting_WF_Action__c action(
        Id policyId,
        String key,
        String label,
        String target,
        Boolean requiresReason,
        Integer sortOrder
    ) {
        return new Meeting_WF_Action__c(
            Role_Policy__c = policyId,
            Action_Key__c = key,
            Label__c = label,
            Target_Status__c = target,
            Requires_Reason__c = requiresReason,
            Sort_Order__c = sortOrder
        );
    }

    private static void insertRelatedPolicies(Map<String, Id> policyIds) {
        Id organizerDraft = policyIds.get('Draft|Organizer');
        Id superDraft = policyIds.get('Draft|SuperUser');
        Id organizerApproved = policyIds.get('Approved|Organizer');
        if (organizerDraft == null) {
            return;
        }

        List<Meeting_WF_Related_Policy__c> related = new List<Meeting_WF_Related_Policy__c>();
        related.addAll(draftOrganizerRelated(organizerDraft));
        if (superDraft != null) {
            related.addAll(draftOrganizerRelated(superDraft));
        }
        if (organizerApproved != null) {
            related.add(
                relatedRow(organizerApproved, 'Meeting_Member__c', 'Attendee;Non_Profiled_Attendee;Write_In', true, true, false)
            );
            related.add(relatedRow(organizerApproved, 'Meeting_Member__c', 'Speaker', true, true, false));
            related.add(relatedRow(organizerApproved, 'Meeting_Member__c', 'Colleague', true, true, false));
            related.add(relatedRow(organizerApproved, 'Meeting_Expense__c', 'Estimate', false, false, false));
            related.add(relatedRow(organizerApproved, 'Meeting_Expense__c', 'Actual', true, true, false));
            related.add(relatedRow(organizerApproved, 'Meeting_Location__c', null, true, true, false));
            related.add(relatedRow(organizerApproved, 'Meeting_Product__c', null, true, true, false));
            related.add(relatedRow(organizerApproved, 'Meeting_Topic__c', null, true, true, false));
        }
        insert related;
    }

    private static List<Meeting_WF_Related_Policy__c> draftOrganizerRelated(Id policyId) {
        return new List<Meeting_WF_Related_Policy__c>{
            relatedRow(policyId, 'Meeting_Member__c', 'Attendee;Non_Profiled_Attendee;Write_In', true, true, false),
            relatedRow(policyId, 'Meeting_Member__c', 'Speaker', true, true, false),
            relatedRow(policyId, 'Meeting_Member__c', 'Colleague', true, true, true),
            relatedRow(policyId, 'Meeting_Expense__c', 'Estimate', true, true, true),
            relatedRow(policyId, 'Meeting_Expense__c', 'Actual', false, false, false),
            relatedRow(policyId, 'Meeting_Expense_Allocation__c', null, true, true, true),
            relatedRow(policyId, 'Meeting_Location__c', null, true, true, true),
            relatedRow(policyId, 'Meeting_Product__c', null, true, true, true),
            relatedRow(policyId, 'Meeting_Topic__c', null, true, true, true),
            relatedRow(policyId, 'Meeting_Budget__c', null, true, true, false)
        };
    }

    private static Meeting_WF_Related_Policy__c relatedRow(
        Id policyId,
        String relatedObject,
        String rtFilter,
        Boolean canCreate,
        Boolean canEdit,
        Boolean canDelete
    ) {
        return new Meeting_WF_Related_Policy__c(
            Role_Policy__c = policyId,
            Related_Object__c = relatedObject,
            Record_Type_Filter__c = rtFilter,
            Can_Create__c = canCreate,
            Can_Edit__c = canEdit,
            Can_Delete__c = canDelete
        );
    }
}