public with sharing class MeetingWorkflowAdminController {
    public class WorkflowListItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String meetingRecordType;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Boolean isPublished;
        @AuraEnabled public Boolean isDraft;
        @AuraEnabled public Boolean isArchived;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    public class WorkflowDetail {
        @AuraEnabled public Meeting_Workflow__c workflow;
        @AuraEnabled public List<Meeting_WF_Status__c> statuses;
        @AuraEnabled public List<Meeting_WF_Role_Policy__c> rolePolicies;
        @AuraEnabled public List<Meeting_WF_Approver_Rule__c> approverRules;
        @AuraEnabled public List<Meeting_WF_Skip_Rule__c> skipRules;
        @AuraEnabled public List<Meeting_WF_Side_Effect__c> sideEffects;
        @AuraEnabled public List<Meeting_WF_Publish_Log__c> publishLogs;
        @AuraEnabled public Boolean isEditable;
    }

    public class RecordTypeOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public RecordTypeOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class RolePolicyBundle {
        @AuraEnabled public Meeting_WF_Role_Policy__c policy;
        @AuraEnabled public List<Meeting_WF_Action__c> actions;
        @AuraEnabled public List<Meeting_WF_Related_Policy__c> relatedPolicies;
    }

    public class RelatedAccessCell {
        @AuraEnabled public String statusValue;
        @AuraEnabled public String relatedObject;
        @AuraEnabled public String recordTypeFilter;
        @AuraEnabled public String accessLevel;
    }

    public class ApprovalSetup {
        @AuraEnabled public String firstApproverMode;
        @AuraEnabled public String secondApproverMode;
        @AuraEnabled public String secondApproverRoles;
        @AuraEnabled public String secondApproverGroup;
        @AuraEnabled public String ownerProfileFilter;
        @AuraEnabled public Boolean createManagerAsApprover;
        @AuraEnabled public List<Meeting_WF_Skip_Rule__c> skipRules;
    }

    private static void assertManagePermission() {
        if (!FeatureManagement.checkPermission('Manage_Meeting_Workflows') && !Test.isRunningTest()) {
            throw new AuraHandledException('Missing Manage_Meeting_Workflows permission.');
        }
    }

    private static Meeting_Workflow__c requireWorkflow(Id workflowId) {
        if (workflowId == null) {
            throw new AuraHandledException('Workflow Id is required.');
        }
        List<Meeting_Workflow__c> rows = [
            SELECT
                Id,
                Name,
                Meeting_Record_Type__c,
                Description__c,
                Version__c,
                Is_Published__c,
                Is_Draft__c,
                Family__c,
                Create_Manager_As_Approver__c,
                Statuses_To_Calculate_Actuals__c,
                Published_Date__c,
                Published_By__c
            FROM Meeting_Workflow__c
            WHERE Id = :workflowId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Workflow not found.');
        }
        return rows[0];
    }

    private static void assertDraftEditable(Meeting_Workflow__c workflow) {
        if (workflow.Is_Published__c == true) {
            throw new AuraHandledException('Published workflows are read-only. Clone to a draft, edit, then publish.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RecordTypeOption> getMeetingRecordTypes() {
        assertManagePermission();
        List<RecordTypeOption> options = new List<RecordTypeOption>();
        for (RecordType rt : [
            SELECT Name, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Meeting__c' AND IsActive = TRUE
            ORDER BY Name
        ]) {
            options.add(new RecordTypeOption(rt.Name, rt.DeveloperName));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkflowListItem> listWorkflows() {
        assertManagePermission();
        List<WorkflowListItem> items = new List<WorkflowListItem>();
        for (Meeting_Workflow__c wf : [
            SELECT
                Id,
                Name,
                Meeting_Record_Type__c,
                Family__c,
                Version__c,
                Is_Published__c,
                Is_Draft__c,
                LastModifiedDate,
                LastModifiedBy.Name
            FROM Meeting_Workflow__c
            ORDER BY Meeting_Record_Type__c ASC, Version__c DESC NULLS LAST
            LIMIT 500
        ]) {
            WorkflowListItem item = new WorkflowListItem();
            item.id = wf.Id;
            item.name = wf.Name;
            item.meetingRecordType = wf.Meeting_Record_Type__c;
            item.family = wf.Family__c;
            item.version = wf.Version__c;
            item.isPublished = wf.Is_Published__c;
            item.isDraft = wf.Is_Draft__c;
            item.isArchived = wf.Is_Published__c != true && wf.Is_Draft__c != true;
            item.lastModifiedDate = wf.LastModifiedDate;
            item.lastModifiedByName = wf.LastModifiedBy != null ? wf.LastModifiedBy.Name : null;
            items.add(item);
        }
        return items;
    }

    @AuraEnabled
    public static WorkflowDetail getWorkflowDetail(Id workflowId) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        WorkflowDetail detail = new WorkflowDetail();
        detail.workflow = workflow;
        detail.isEditable = workflow.Is_Published__c != true;
        detail.statuses = [
            SELECT Id, Status_Value__c, Status_Label__c, Sort_Order__c, Is_Terminal__c
            FROM Meeting_WF_Status__c
            WHERE Workflow__c = :workflowId
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];
        detail.rolePolicies = [
            SELECT
                Id,
                Status_Value__c,
                Role_Key__c,
                Can_Edit_Meeting__c,
                Can_Delete_Meeting__c,
                (SELECT Id, Action_Key__c, Label__c, Target_Status__c, Requires_Reason__c, Sort_Order__c, Validation_Rule_Set__c FROM WF_Actions__r ORDER BY Sort_Order__c),
                (SELECT Id, Related_Object__c, Record_Type_Filter__c, Can_Create__c, Can_Edit__c, Can_Delete__c, Is_Visible__c FROM Related_Policies__r)
            FROM Meeting_WF_Role_Policy__c
            WHERE Workflow__c = :workflowId
            ORDER BY Status_Value__c, Role_Key__c
        ];
        detail.approverRules = [
            SELECT
                Id,
                First_Approver_Mode__c,
                Second_Approver_Mode__c,
                Second_Approver_Roles__c,
                Second_Approver_Group__c,
                Owner_Profile_Filter__c
            FROM Meeting_WF_Approver_Rule__c
            WHERE Workflow__c = :workflowId
        ];
        detail.skipRules = [
            SELECT
                Id,
                Priority__c,
                Record_Types__c,
                Condition_Type__c,
                Condition_Values__c,
                From_Status__c,
                To_Status__c
            FROM Meeting_WF_Skip_Rule__c
            WHERE Workflow__c = :workflowId
            ORDER BY Priority__c ASC NULLS LAST
        ];
        detail.sideEffects = [
            SELECT Id, From_Status__c, To_Status__c, Effect_Type__c, Config_JSON__c
            FROM Meeting_WF_Side_Effect__c
            WHERE Workflow__c = :workflowId
        ];
        detail.publishLogs = [
            SELECT Id, Version__c, Published_Date__c, Published_By__c, Notes__c, Meeting_Record_Type__c
            FROM Meeting_WF_Publish_Log__c
            WHERE Workflow__c = :workflowId
            ORDER BY Published_Date__c DESC NULLS LAST
            LIMIT 50
        ];
        return detail;
    }

    @AuraEnabled
    public static Id createDraftWorkflow(String meetingRecordType, String name, String family) {
        assertManagePermission();
        if (String.isBlank(meetingRecordType) || String.isBlank(name)) {
            throw new AuraHandledException('Name and Meeting Record Type are required.');
        }
        Meeting_Workflow__c workflow = new Meeting_Workflow__c(
            Name = name.trim(),
            Meeting_Record_Type__c = meetingRecordType.trim(),
            Family__c = String.isBlank(family) ? null : family.trim(),
            Is_Draft__c = true,
            Is_Published__c = false,
            Version__c = 0,
            Description__c = 'Draft workflow'
        );
        insert workflow;

        Meeting_WF_Status__c draftStatus = new Meeting_WF_Status__c(
            Workflow__c = workflow.Id,
            Status_Value__c = 'Draft',
            Status_Label__c = 'Draft',
            Sort_Order__c = 10,
            Is_Terminal__c = false
        );
        insert draftStatus;

        Meeting_WF_Role_Policy__c organizer = new Meeting_WF_Role_Policy__c(
            Workflow__c = workflow.Id,
            Status_Value__c = 'Draft',
            Role_Key__c = 'Organizer',
            Can_Edit_Meeting__c = true,
            Can_Delete_Meeting__c = true
        );
        insert organizer;
        insert new Meeting_WF_Action__c(
            Role_Policy__c = organizer.Id,
            Action_Key__c = 'SubmitForApproval',
            Label__c = 'Submit for Approval',
            Target_Status__c = 'PendingApproval',
            Sort_Order__c = 1
        );
        MeetingWorkflowService.clearCache();
        return workflow.Id;
    }

    @AuraEnabled
    public static Id cloneWorkflow(Id sourceWorkflowId) {
        assertManagePermission();
        Meeting_Workflow__c source = requireWorkflow(sourceWorkflowId);
        Meeting_Workflow__c clone = new Meeting_Workflow__c(
            Name = source.Name + ' (Draft)',
            Meeting_Record_Type__c = source.Meeting_Record_Type__c,
            Description__c = source.Description__c,
            Family__c = source.Family__c,
            Create_Manager_As_Approver__c = source.Create_Manager_As_Approver__c,
            Statuses_To_Calculate_Actuals__c = source.Statuses_To_Calculate_Actuals__c,
            Is_Draft__c = true,
            Is_Published__c = false,
            Version__c = 0
        );
        insert clone;

        Map<Id, Id> policyIdMap = new Map<Id, Id>();
        List<Meeting_WF_Status__c> statusClones = new List<Meeting_WF_Status__c>();
        for (Meeting_WF_Status__c row : [
            SELECT Status_Value__c, Status_Label__c, Sort_Order__c, Is_Terminal__c
            FROM Meeting_WF_Status__c
            WHERE Workflow__c = :source.Id
            ORDER BY Sort_Order__c ASC NULLS LAST
        ]) {
            statusClones.add(
                new Meeting_WF_Status__c(
                    Workflow__c = clone.Id,
                    Status_Value__c = row.Status_Value__c,
                    Status_Label__c = row.Status_Label__c,
                    Sort_Order__c = row.Sort_Order__c,
                    Is_Terminal__c = row.Is_Terminal__c
                )
            );
        }
        if (!statusClones.isEmpty()) {
            insert statusClones;
        }

        List<Meeting_WF_Role_Policy__c> sourcePolicies = [
            SELECT
                Id,
                Status_Value__c,
                Role_Key__c,
                Can_Edit_Meeting__c,
                Can_Delete_Meeting__c,
                (SELECT Action_Key__c, Label__c, Target_Status__c, Requires_Reason__c, Sort_Order__c, Validation_Rule_Set__c FROM WF_Actions__r),
                (SELECT Related_Object__c, Record_Type_Filter__c, Can_Create__c, Can_Edit__c, Can_Delete__c, Is_Visible__c FROM Related_Policies__r)
            FROM Meeting_WF_Role_Policy__c
            WHERE Workflow__c = :source.Id
        ];
        List<Meeting_WF_Role_Policy__c> policyClones = new List<Meeting_WF_Role_Policy__c>();
        for (Meeting_WF_Role_Policy__c policy : sourcePolicies) {
            policyClones.add(
                new Meeting_WF_Role_Policy__c(
                    Workflow__c = clone.Id,
                    Status_Value__c = policy.Status_Value__c,
                    Role_Key__c = policy.Role_Key__c,
                    Can_Edit_Meeting__c = policy.Can_Edit_Meeting__c,
                    Can_Delete_Meeting__c = policy.Can_Delete_Meeting__c
                )
            );
        }
        if (!policyClones.isEmpty()) {
            insert policyClones;
            for (Integer i = 0; i < sourcePolicies.size(); i++) {
                policyIdMap.put(sourcePolicies[i].Id, policyClones[i].Id);
            }
        }

        List<Meeting_WF_Action__c> actionClones = new List<Meeting_WF_Action__c>();
        List<Meeting_WF_Related_Policy__c> relatedClones = new List<Meeting_WF_Related_Policy__c>();
        for (Meeting_WF_Role_Policy__c policy : sourcePolicies) {
            Id newPolicyId = policyIdMap.get(policy.Id);
            for (Meeting_WF_Action__c action : policy.WF_Actions__r) {
                actionClones.add(
                    new Meeting_WF_Action__c(
                        Role_Policy__c = newPolicyId,
                        Action_Key__c = action.Action_Key__c,
                        Label__c = action.Label__c,
                        Target_Status__c = action.Target_Status__c,
                        Requires_Reason__c = action.Requires_Reason__c,
                        Sort_Order__c = action.Sort_Order__c,
                        Validation_Rule_Set__c = action.Validation_Rule_Set__c
                    )
                );
            }
            for (Meeting_WF_Related_Policy__c related : policy.Related_Policies__r) {
                relatedClones.add(
                    new Meeting_WF_Related_Policy__c(
                        Role_Policy__c = newPolicyId,
                        Related_Object__c = related.Related_Object__c,
                        Record_Type_Filter__c = related.Record_Type_Filter__c,
                        Can_Create__c = related.Can_Create__c,
                        Can_Edit__c = related.Can_Edit__c,
                        Can_Delete__c = related.Can_Delete__c,
                        Is_Visible__c = related.Is_Visible__c != false
                    )
                );
            }
        }
        if (!actionClones.isEmpty()) {
            insert actionClones;
        }
        if (!relatedClones.isEmpty()) {
            insert relatedClones;
        }

        List<Meeting_WF_Approver_Rule__c> approverClones = new List<Meeting_WF_Approver_Rule__c>();
        for (Meeting_WF_Approver_Rule__c row : [
            SELECT
                First_Approver_Mode__c,
                Second_Approver_Mode__c,
                Second_Approver_Roles__c,
                Second_Approver_Group__c,
                Owner_Profile_Filter__c
            FROM Meeting_WF_Approver_Rule__c
            WHERE Workflow__c = :source.Id
        ]) {
            approverClones.add(
                new Meeting_WF_Approver_Rule__c(
                    Workflow__c = clone.Id,
                    First_Approver_Mode__c = row.First_Approver_Mode__c,
                    Second_Approver_Mode__c = row.Second_Approver_Mode__c,
                    Second_Approver_Roles__c = row.Second_Approver_Roles__c,
                    Second_Approver_Group__c = row.Second_Approver_Group__c,
                    Owner_Profile_Filter__c = row.Owner_Profile_Filter__c
                )
            );
        }
        if (!approverClones.isEmpty()) {
            insert approverClones;
        }

        List<Meeting_WF_Skip_Rule__c> skipClones = new List<Meeting_WF_Skip_Rule__c>();
        for (Meeting_WF_Skip_Rule__c row : [
            SELECT
                Priority__c,
                Record_Types__c,
                Condition_Type__c,
                Condition_Values__c,
                From_Status__c,
                To_Status__c
            FROM Meeting_WF_Skip_Rule__c
            WHERE Workflow__c = :source.Id
        ]) {
            skipClones.add(
                new Meeting_WF_Skip_Rule__c(
                    Workflow__c = clone.Id,
                    Priority__c = row.Priority__c,
                    Record_Types__c = row.Record_Types__c,
                    Condition_Type__c = row.Condition_Type__c,
                    Condition_Values__c = row.Condition_Values__c,
                    From_Status__c = row.From_Status__c,
                    To_Status__c = row.To_Status__c
                )
            );
        }
        if (!skipClones.isEmpty()) {
            insert skipClones;
        }

        List<Meeting_WF_Side_Effect__c> effectClones = new List<Meeting_WF_Side_Effect__c>();
        for (Meeting_WF_Side_Effect__c row : [
            SELECT From_Status__c, To_Status__c, Effect_Type__c, Config_JSON__c
            FROM Meeting_WF_Side_Effect__c
            WHERE Workflow__c = :source.Id
        ]) {
            effectClones.add(
                new Meeting_WF_Side_Effect__c(
                    Workflow__c = clone.Id,
                    From_Status__c = row.From_Status__c,
                    To_Status__c = row.To_Status__c,
                    Effect_Type__c = row.Effect_Type__c,
                    Config_JSON__c = row.Config_JSON__c
                )
            );
        }
        if (!effectClones.isEmpty()) {
            insert effectClones;
        }

        MeetingWorkflowService.clearCache();
        return clone.Id;
    }

    @AuraEnabled
    public static void archiveWorkflow(Id workflowId) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        workflow.Is_Published__c = false;
        workflow.Is_Draft__c = false;
        update workflow;
        MeetingWorkflowService.clearCache();
    }

    @AuraEnabled
    public static MeetingWorkflowPublisher.PublishResult publishWorkflow(Id workflowId) {
        assertManagePermission();
        return MeetingWorkflowPublisher.publish(workflowId);
    }

    @AuraEnabled
    public static MeetingWorkflowSeed.SeedResult seedTemplates(Boolean publish) {
        assertManagePermission();
        return MeetingWorkflowSeed.seedStandardTemplates(publish == true);
    }

    @AuraEnabled
    public static MeetingWorkflowService.EvaluationResult evaluateMeeting(Id meetingId) {
        return MeetingWorkflowService.evaluate(meetingId);
    }

    @AuraEnabled
    public static MeetingWorkflowService.TransitionResult applyMeetingAction(
        Id meetingId,
        String actionKey,
        String reason
    ) {
        return MeetingWorkflowService.applyTransition(meetingId, actionKey, reason);
    }

    @AuraEnabled
    public static Meeting_Workflow__c saveWorkflowHeader(Meeting_Workflow__c workflow) {
        assertManagePermission();
        if (workflow == null || workflow.Id == null) {
            throw new AuraHandledException('Workflow with Id is required.');
        }
        Meeting_Workflow__c existing = requireWorkflow(workflow.Id);
        assertDraftEditable(existing);
        if (workflow.Name != null) {
            existing.Name = workflow.Name;
        }
        if (workflow.Meeting_Record_Type__c != null) {
            existing.Meeting_Record_Type__c = workflow.Meeting_Record_Type__c;
        }
        if (workflow.Description__c != null) {
            existing.Description__c = workflow.Description__c;
        }
        if (workflow.Family__c != null) {
            existing.Family__c = workflow.Family__c;
        }
        if (workflow.Create_Manager_As_Approver__c != null) {
            existing.Create_Manager_As_Approver__c = workflow.Create_Manager_As_Approver__c;
        }
        if (workflow.Statuses_To_Calculate_Actuals__c != null) {
            existing.Statuses_To_Calculate_Actuals__c = workflow.Statuses_To_Calculate_Actuals__c;
        }
        update existing;
        MeetingWorkflowService.clearCache();
        return existing;
    }

    @AuraEnabled
    public static List<Meeting_WF_Status__c> saveStatuses(Id workflowId, List<Meeting_WF_Status__c> statuses) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (statuses == null) {
            statuses = new List<Meeting_WF_Status__c>();
        }

        Set<Id> keepIds = new Set<Id>();
        List<Meeting_WF_Status__c> upserts = new List<Meeting_WF_Status__c>();
        for (Meeting_WF_Status__c row : statuses) {
            Meeting_WF_Status__c toSave = new Meeting_WF_Status__c(
                Workflow__c = workflowId,
                Status_Value__c = row.Status_Value__c,
                Status_Label__c = row.Status_Label__c,
                Sort_Order__c = row.Sort_Order__c,
                Is_Terminal__c = row.Is_Terminal__c == true
            );
            if (row.Id != null) {
                toSave.Id = row.Id;
                keepIds.add(row.Id);
            }
            upserts.add(toSave);
        }

        List<Meeting_WF_Status__c> toDelete = [
            SELECT Id
            FROM Meeting_WF_Status__c
            WHERE Workflow__c = :workflowId AND Id NOT IN :keepIds
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!upserts.isEmpty()) {
            upsert upserts;
        }
        MeetingWorkflowService.clearCache();
        return [
            SELECT Id, Status_Value__c, Status_Label__c, Sort_Order__c, Is_Terminal__c
            FROM Meeting_WF_Status__c
            WHERE Workflow__c = :workflowId
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];
    }

    @AuraEnabled
    public static Meeting_WF_Role_Policy__c saveRolePolicyBundle(Id workflowId, RolePolicyBundle bundle) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (bundle == null || bundle.policy == null) {
            throw new AuraHandledException('Role policy is required.');
        }

        Meeting_WF_Role_Policy__c policy = new Meeting_WF_Role_Policy__c(
            Workflow__c = workflowId,
            Status_Value__c = bundle.policy.Status_Value__c,
            Role_Key__c = bundle.policy.Role_Key__c,
            Can_Edit_Meeting__c = bundle.policy.Can_Edit_Meeting__c == true,
            Can_Delete_Meeting__c = bundle.policy.Can_Delete_Meeting__c == true
        );
        if (bundle.policy.Id != null) {
            policy.Id = bundle.policy.Id;
        }
        upsert policy;

        Set<Id> keepActionIds = new Set<Id>();
        List<Meeting_WF_Action__c> actionUpserts = new List<Meeting_WF_Action__c>();
        if (bundle.actions != null) {
            for (Meeting_WF_Action__c action : bundle.actions) {
                Meeting_WF_Action__c toSave = new Meeting_WF_Action__c(
                    Role_Policy__c = policy.Id,
                    Action_Key__c = action.Action_Key__c,
                    Label__c = action.Label__c,
                    Target_Status__c = action.Target_Status__c,
                    Requires_Reason__c = action.Requires_Reason__c == true,
                    Sort_Order__c = action.Sort_Order__c,
                    Validation_Rule_Set__c = action.Validation_Rule_Set__c
                );
                if (action.Id != null) {
                    toSave.Id = action.Id;
                    keepActionIds.add(action.Id);
                }
                actionUpserts.add(toSave);
            }
        }
        List<Meeting_WF_Action__c> actionsToDelete = [
            SELECT Id
            FROM Meeting_WF_Action__c
            WHERE Role_Policy__c = :policy.Id AND Id NOT IN :keepActionIds
        ];
        if (!actionsToDelete.isEmpty()) {
            delete actionsToDelete;
        }
        if (!actionUpserts.isEmpty()) {
            upsert actionUpserts;
        }

        Set<Id> keepRelatedIds = new Set<Id>();
        List<Meeting_WF_Related_Policy__c> relatedUpserts = new List<Meeting_WF_Related_Policy__c>();
        if (bundle.relatedPolicies != null) {
            for (Meeting_WF_Related_Policy__c related : bundle.relatedPolicies) {
                Meeting_WF_Related_Policy__c toSave = new Meeting_WF_Related_Policy__c(
                    Role_Policy__c = policy.Id,
                    Related_Object__c = related.Related_Object__c,
                    Record_Type_Filter__c = related.Record_Type_Filter__c,
                    Can_Create__c = related.Can_Create__c == true,
                    Can_Edit__c = related.Can_Edit__c == true,
                    Can_Delete__c = related.Can_Delete__c == true,
                    Is_Visible__c = related.Is_Visible__c != false
                );
                if (related.Id != null) {
                    toSave.Id = related.Id;
                    keepRelatedIds.add(related.Id);
                }
                relatedUpserts.add(toSave);
            }
            List<Meeting_WF_Related_Policy__c> relatedToDelete = [
                SELECT Id
                FROM Meeting_WF_Related_Policy__c
                WHERE Role_Policy__c = :policy.Id AND Id NOT IN :keepRelatedIds
            ];
            if (!relatedToDelete.isEmpty()) {
                delete relatedToDelete;
            }
        }
        if (!relatedUpserts.isEmpty()) {
            upsert relatedUpserts;
        }

        MeetingWorkflowService.clearCache();
        return policy;
    }

    @AuraEnabled
    public static void deleteRolePolicy(Id workflowId, Id rolePolicyId) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        List<Meeting_WF_Role_Policy__c> rows = [
            SELECT Id
            FROM Meeting_WF_Role_Policy__c
            WHERE Id = :rolePolicyId AND Workflow__c = :workflowId
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
        MeetingWorkflowService.clearCache();
    }

    @AuraEnabled
    public static List<Meeting_WF_Approver_Rule__c> saveApproverRules(
        Id workflowId,
        List<Meeting_WF_Approver_Rule__c> rules
    ) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (rules == null) {
            rules = new List<Meeting_WF_Approver_Rule__c>();
        }
        Set<Id> keepIds = new Set<Id>();
        List<Meeting_WF_Approver_Rule__c> upserts = new List<Meeting_WF_Approver_Rule__c>();
        for (Meeting_WF_Approver_Rule__c row : rules) {
            Meeting_WF_Approver_Rule__c toSave = new Meeting_WF_Approver_Rule__c(
                Workflow__c = workflowId,
                First_Approver_Mode__c = row.First_Approver_Mode__c,
                Second_Approver_Mode__c = row.Second_Approver_Mode__c,
                Second_Approver_Roles__c = row.Second_Approver_Roles__c,
                Second_Approver_Group__c = row.Second_Approver_Group__c,
                Owner_Profile_Filter__c = row.Owner_Profile_Filter__c
            );
            if (row.Id != null) {
                toSave.Id = row.Id;
                keepIds.add(row.Id);
            }
            upserts.add(toSave);
        }
        List<Meeting_WF_Approver_Rule__c> toDelete = [
            SELECT Id
            FROM Meeting_WF_Approver_Rule__c
            WHERE Workflow__c = :workflowId AND Id NOT IN :keepIds
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!upserts.isEmpty()) {
            upsert upserts;
        }
        MeetingWorkflowService.clearCache();
        return [
            SELECT
                Id,
                First_Approver_Mode__c,
                Second_Approver_Mode__c,
                Second_Approver_Roles__c,
                Second_Approver_Group__c,
                Owner_Profile_Filter__c
            FROM Meeting_WF_Approver_Rule__c
            WHERE Workflow__c = :workflowId
        ];
    }

    @AuraEnabled
    public static List<Meeting_WF_Skip_Rule__c> saveSkipRules(Id workflowId, List<Meeting_WF_Skip_Rule__c> rules) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (rules == null) {
            rules = new List<Meeting_WF_Skip_Rule__c>();
        }
        Set<Id> keepIds = new Set<Id>();
        List<Meeting_WF_Skip_Rule__c> upserts = new List<Meeting_WF_Skip_Rule__c>();
        for (Meeting_WF_Skip_Rule__c row : rules) {
            Meeting_WF_Skip_Rule__c toSave = new Meeting_WF_Skip_Rule__c(
                Workflow__c = workflowId,
                Priority__c = row.Priority__c,
                Record_Types__c = row.Record_Types__c,
                Condition_Type__c = row.Condition_Type__c,
                Condition_Values__c = row.Condition_Values__c,
                From_Status__c = row.From_Status__c,
                To_Status__c = row.To_Status__c
            );
            if (row.Id != null) {
                toSave.Id = row.Id;
                keepIds.add(row.Id);
            }
            upserts.add(toSave);
        }
        List<Meeting_WF_Skip_Rule__c> toDelete = [
            SELECT Id
            FROM Meeting_WF_Skip_Rule__c
            WHERE Workflow__c = :workflowId AND Id NOT IN :keepIds
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!upserts.isEmpty()) {
            upsert upserts;
        }
        MeetingWorkflowService.clearCache();
        return [
            SELECT
                Id,
                Priority__c,
                Record_Types__c,
                Condition_Type__c,
                Condition_Values__c,
                From_Status__c,
                To_Status__c
            FROM Meeting_WF_Skip_Rule__c
            WHERE Workflow__c = :workflowId
            ORDER BY Priority__c ASC NULLS LAST
        ];
    }

    @AuraEnabled
    public static List<Meeting_WF_Side_Effect__c> saveSideEffects(
        Id workflowId,
        List<Meeting_WF_Side_Effect__c> effects
    ) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (effects == null) {
            effects = new List<Meeting_WF_Side_Effect__c>();
        }
        Set<Id> keepIds = new Set<Id>();
        List<Meeting_WF_Side_Effect__c> upserts = new List<Meeting_WF_Side_Effect__c>();
        for (Meeting_WF_Side_Effect__c row : effects) {
            Meeting_WF_Side_Effect__c toSave = new Meeting_WF_Side_Effect__c(
                Workflow__c = workflowId,
                From_Status__c = row.From_Status__c,
                To_Status__c = row.To_Status__c,
                Effect_Type__c = row.Effect_Type__c,
                Config_JSON__c = row.Config_JSON__c
            );
            if (row.Id != null) {
                toSave.Id = row.Id;
                keepIds.add(row.Id);
            }
            upserts.add(toSave);
        }
        List<Meeting_WF_Side_Effect__c> toDelete = [
            SELECT Id
            FROM Meeting_WF_Side_Effect__c
            WHERE Workflow__c = :workflowId AND Id NOT IN :keepIds
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!upserts.isEmpty()) {
            upsert upserts;
        }
        MeetingWorkflowService.clearCache();
        return [
            SELECT Id, From_Status__c, To_Status__c, Effect_Type__c, Config_JSON__c
            FROM Meeting_WF_Side_Effect__c
            WHERE Workflow__c = :workflowId
        ];
    }

    @AuraEnabled
    public static void saveRelatedListMatrix(Id workflowId, List<RelatedAccessCell> cells) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (cells == null) {
            cells = new List<RelatedAccessCell>();
        }

        Set<String> statusValues = new Set<String>();
        for (RelatedAccessCell cell : cells) {
            if (String.isNotBlank(cell.statusValue)) {
                statusValues.add(cell.statusValue);
            }
        }

        Map<String, Meeting_WF_Role_Policy__c> organizerByStatus = new Map<String, Meeting_WF_Role_Policy__c>();
        for (Meeting_WF_Role_Policy__c policy : [
            SELECT Id, Status_Value__c
            FROM Meeting_WF_Role_Policy__c
            WHERE Workflow__c = :workflowId AND Role_Key__c = 'Organizer'
        ]) {
            organizerByStatus.put(policy.Status_Value__c, policy);
        }

        List<Meeting_WF_Role_Policy__c> policiesToInsert = new List<Meeting_WF_Role_Policy__c>();
        for (String statusValue : statusValues) {
            if (!organizerByStatus.containsKey(statusValue)) {
                policiesToInsert.add(
                    new Meeting_WF_Role_Policy__c(
                        Workflow__c = workflowId,
                        Status_Value__c = statusValue,
                        Role_Key__c = 'Organizer',
                        Can_Edit_Meeting__c = true,
                        Can_Delete_Meeting__c = statusValue == 'Draft'
                    )
                );
            }
        }
        if (!policiesToInsert.isEmpty()) {
            insert policiesToInsert;
            for (Meeting_WF_Role_Policy__c policy : policiesToInsert) {
                organizerByStatus.put(policy.Status_Value__c, policy);
            }
        }

        Set<Id> organizerIds = new Set<Id>();
        for (Meeting_WF_Role_Policy__c policy : organizerByStatus.values()) {
            organizerIds.add(policy.Id);
        }
        List<Meeting_WF_Related_Policy__c> existingRelated = [
            SELECT Id
            FROM Meeting_WF_Related_Policy__c
            WHERE Role_Policy__c IN :organizerIds
        ];
        if (!existingRelated.isEmpty()) {
            delete existingRelated;
        }

        List<Meeting_WF_Related_Policy__c> relatedInserts = new List<Meeting_WF_Related_Policy__c>();
        for (RelatedAccessCell cell : cells) {
            Meeting_WF_Role_Policy__c policy = organizerByStatus.get(cell.statusValue);
            if (policy == null) {
                continue;
            }
            String access = String.isBlank(cell.accessLevel) ? 'view' : cell.accessLevel;
            Boolean visible = access != 'hidden';
            Boolean modify = access == 'modify';
            relatedInserts.add(
                new Meeting_WF_Related_Policy__c(
                    Role_Policy__c = policy.Id,
                    Related_Object__c = cell.relatedObject,
                    Record_Type_Filter__c = cell.recordTypeFilter,
                    Is_Visible__c = visible,
                    Can_Create__c = modify,
                    Can_Edit__c = modify,
                    Can_Delete__c = modify && cell.statusValue == 'Draft'
                )
            );
        }
        if (!relatedInserts.isEmpty()) {
            insert relatedInserts;
        }
        MeetingWorkflowService.clearCache();
    }

    @AuraEnabled
    public static void saveApprovalSetup(Id workflowId, ApprovalSetup setup) {
        assertManagePermission();
        Meeting_Workflow__c workflow = requireWorkflow(workflowId);
        assertDraftEditable(workflow);
        if (setup == null) {
            throw new AuraHandledException('Approval setup is required.');
        }

        workflow.Create_Manager_As_Approver__c = setup.createManagerAsApprover == true;
        update workflow;

        List<Meeting_WF_Approver_Rule__c> existingRules = [
            SELECT Id
            FROM Meeting_WF_Approver_Rule__c
            WHERE Workflow__c = :workflowId
        ];
        if (!existingRules.isEmpty()) {
            delete existingRules;
        }
        insert new Meeting_WF_Approver_Rule__c(
            Workflow__c = workflowId,
            First_Approver_Mode__c = String.isBlank(setup.firstApproverMode)
                ? 'OwnerManager'
                : setup.firstApproverMode,
            Second_Approver_Mode__c = String.isBlank(setup.secondApproverMode)
                ? 'None'
                : setup.secondApproverMode,
            Second_Approver_Roles__c = setup.secondApproverRoles,
            Second_Approver_Group__c = setup.secondApproverGroup,
            Owner_Profile_Filter__c = setup.ownerProfileFilter
        );

        saveSkipRules(workflowId, setup.skipRules == null ? new List<Meeting_WF_Skip_Rule__c>() : setup.skipRules);
    }
}