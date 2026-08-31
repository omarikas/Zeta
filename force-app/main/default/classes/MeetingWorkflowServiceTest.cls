@IsTest
private class MeetingWorkflowServiceTest {
    private static Id meetingRtId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Meeting__c' AND DeveloperName = :developerName
            LIMIT 1
        ]
        .Id;
    }

    private static Id memberColleagueRtId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Meeting_Member__c' AND DeveloperName = 'Colleague'
            LIMIT 1
        ]
        .Id;
    }

    @IsTest
    static void seedPublishEvaluateAndTransition_gpmHappyPath() {
        MeetingWorkflowSeed.SeedResult seed = MeetingWorkflowSeed.seedStandardTemplates(true);
        System.assert(seed.workflowsCreated >= 7, seed.message);
        System.assert(seed.workflowsPublished >= 7, seed.message);

        Meeting__c meeting = new Meeting__c(
            RecordTypeId = meetingRtId('Speaker_Meeting'),
            Status__c = 'Draft',
            Objectives__c = 'Test objectives'
        );
        insert meeting;

        Meeting_Member__c approver = new Meeting_Member__c(
            Meeting__c = meeting.Id,
            RecordTypeId = memberColleagueRtId(),
            Colleague__c = UserInfo.getUserId(),
            Type__c = 'Approver',
            System_Generated__c = true
        );
        Meeting_Member__c second = new Meeting_Member__c(
            Meeting__c = meeting.Id,
            RecordTypeId = memberColleagueRtId(),
            Colleague__c = UserInfo.getUserId(),
            Type__c = 'Second Approver',
            System_Generated__c = true
        );
        insert new List<Meeting_Member__c>{ approver, second };

        MeetingWorkflowService.EvaluationResult draftEval = MeetingWorkflowService.evaluate(meeting.Id);
        System.assertEquals(true, draftEval.canEditMeeting);
        System.assert(!draftEval.actions.isEmpty(), 'Organizer should see Draft actions');

        MeetingWorkflowService.TransitionResult submit = MeetingWorkflowService.applyTransition(
            meeting.Id,
            'SubmitForApproval',
            null
        );
        System.assertEquals(true, submit.success, submit.message);
        meeting = [SELECT Status__c, Was_Approved__c FROM Meeting__c WHERE Id = :meeting.Id];
        System.assertEquals('PendingApproval', meeting.Status__c);

        MeetingWorkflowService.TransitionResult approve1 = MeetingWorkflowService.applyTransition(
            meeting.Id,
            'Approve',
            null
        );
        System.assertEquals(true, approve1.success, approve1.message);
        meeting = [SELECT Status__c FROM Meeting__c WHERE Id = :meeting.Id];
        System.assertEquals('Pending GPM Approval', meeting.Status__c);

        MeetingWorkflowService.TransitionResult approve2 = MeetingWorkflowService.applyTransition(
            meeting.Id,
            'Approve',
            null
        );
        System.assertEquals(true, approve2.success, approve2.message);
        meeting = [SELECT Status__c, Was_Approved__c FROM Meeting__c WHERE Id = :meeting.Id];
        System.assertEquals('Approved', meeting.Status__c);
        System.assertEquals(true, meeting.Was_Approved__c);

        Integer historyCount = [SELECT COUNT() FROM Meeting_History__c WHERE Meeting__c = :meeting.Id];
        System.assert(historyCount >= 3, 'Expected history rows for each transition');

        MeetingWorkflowService.TransitionResult closeResult = MeetingWorkflowService.applyTransition(
            meeting.Id,
            'Close',
            null
        );
        System.assertEquals(true, closeResult.success, closeResult.message);
        meeting = [SELECT Status__c FROM Meeting__c WHERE Id = :meeting.Id];
        System.assertEquals('Closed', meeting.Status__c);
    }

    @IsTest
    static void rejectReturnsToDraft_andPublishUniqueness() {
        MeetingWorkflowSeed.seedStandardTemplates(true);

        // Use GPM path so System Admin profile skip (NLM OwnerProfileNotIn) does not fire.
        Meeting__c meeting = new Meeting__c(
            RecordTypeId = meetingRtId('Speaker_Meeting'),
            Status__c = 'Draft'
        );
        insert meeting;
        insert new Meeting_Member__c(
            Meeting__c = meeting.Id,
            RecordTypeId = memberColleagueRtId(),
            Colleague__c = UserInfo.getUserId(),
            Type__c = 'Approver',
            System_Generated__c = true
        );

        System.assertEquals(
            true,
            MeetingWorkflowService.applyTransition(meeting.Id, 'SubmitForApproval', null).success
        );
        MeetingWorkflowService.TransitionResult reject = MeetingWorkflowService.applyTransition(
            meeting.Id,
            'Reject',
            'Needs more detail'
        );
        System.assertEquals(true, reject.success, reject.message);
        meeting = [SELECT Status__c FROM Meeting__c WHERE Id = :meeting.Id];
        System.assertEquals('Draft', meeting.Status__c);

        Meeting_Workflow__c published = [
            SELECT Id, Meeting_Record_Type__c
            FROM Meeting_Workflow__c
            WHERE Meeting_Record_Type__c = 'Speaker_Meeting' AND Is_Published__c = TRUE
            LIMIT 1
        ];
        Meeting_Workflow__c cloneDraft = new Meeting_Workflow__c(
            Name = 'Speaker Meeting clone draft',
            Meeting_Record_Type__c = 'Speaker_Meeting',
            Is_Published__c = false,
            Is_Draft__c = true,
            Version__c = 0,
            Family__c = 'GPM'
        );
        insert cloneDraft;

        insert new Meeting_WF_Status__c(
            Workflow__c = cloneDraft.Id,
            Status_Value__c = 'Draft',
            Status_Label__c = 'Draft',
            Sort_Order__c = 1
        );
        Meeting_WF_Role_Policy__c rp = new Meeting_WF_Role_Policy__c(
            Workflow__c = cloneDraft.Id,
            Status_Value__c = 'Draft',
            Role_Key__c = 'Organizer',
            Can_Edit_Meeting__c = true
        );
        insert rp;
        insert new Meeting_WF_Action__c(
            Role_Policy__c = rp.Id,
            Action_Key__c = 'SubmitForApproval',
            Label__c = 'Submit',
            Target_Status__c = 'PendingApproval',
            Sort_Order__c = 1
        );

        MeetingWorkflowPublisher.PublishResult pub = MeetingWorkflowPublisher.publish(cloneDraft.Id);
        System.assertEquals(true, pub.success, pub.message);

        Integer publishedCount = [
            SELECT COUNT()
            FROM Meeting_Workflow__c
            WHERE Meeting_Record_Type__c = 'Speaker_Meeting' AND Is_Published__c = TRUE
        ];
        System.assertEquals(1, publishedCount);
        Meeting_Workflow__c archivedPrior = [
            SELECT Is_Published__c, Is_Draft__c
            FROM Meeting_Workflow__c
            WHERE Id = :published.Id
        ];
        System.assertEquals(false, archivedPrior.Is_Published__c);
    }

    @IsTest
    static void adminControllerListAndDetail() {
        MeetingWorkflowSeed.seedStandardTemplates(true);
        List<MeetingWorkflowAdminController.WorkflowListItem> items = MeetingWorkflowAdminController.listWorkflows();
        System.assert(!items.isEmpty());
        MeetingWorkflowAdminController.WorkflowDetail detail = MeetingWorkflowAdminController.getWorkflowDetail(
            items[0].id
        );
        System.assertNotEquals(null, detail.workflow);
        System.assert(!detail.statuses.isEmpty());
        System.assert(!detail.rolePolicies.isEmpty());
    }

    @IsTest
    static void roleResolverDetectsOrganizer() {
        MeetingWorkflowSeed.seedStandardTemplates(true);
        Meeting__c meeting = new Meeting__c(
            RecordTypeId = meetingRtId('RTD'),
            Status__c = 'Draft'
        );
        insert meeting;
        Set<String> roles = MeetingRoleResolver.resolveRoles(meeting.Id, UserInfo.getUserId());
        System.assert(roles.contains(MeetingRoleResolver.ROLE_ORGANIZER));
    }

    @IsTest
    static void roleResolverMemberTypesAndNullGuards() {
        System.assertEquals(0, MeetingRoleResolver.resolveRoles(null, UserInfo.getUserId()).size());
        System.assertEquals(0, MeetingRoleResolver.resolveRoles(UserInfo.getUserId(), null).size());

        Meeting__c meeting = new Meeting__c(
            RecordTypeId = meetingRtId('Speaker_Meeting'),
            Status__c = 'Draft'
        );
        insert meeting;
        Id colleagueRt = memberColleagueRtId();
        Id userId = UserInfo.getUserId();
        insert new List<Meeting_Member__c>{
            new Meeting_Member__c(
                Meeting__c = meeting.Id,
                RecordTypeId = colleagueRt,
                Colleague__c = userId,
                Type__c = 'Approver'
            ),
            new Meeting_Member__c(
                Meeting__c = meeting.Id,
                RecordTypeId = colleagueRt,
                Colleague__c = userId,
                Type__c = 'Second Approver'
            ),
            new Meeting_Member__c(
                Meeting__c = meeting.Id,
                RecordTypeId = colleagueRt,
                Colleague__c = userId,
                Type__c = 'CoOrganizer'
            ),
            new Meeting_Member__c(
                Meeting__c = meeting.Id,
                RecordTypeId = colleagueRt,
                Colleague__c = userId,
                Type__c = 'Participant'
            )
        };

        Set<String> roles = MeetingRoleResolver.resolveRoles(meeting.Id, userId);
        System.assert(roles.contains(MeetingRoleResolver.ROLE_ORGANIZER));
        System.assert(roles.contains(MeetingRoleResolver.ROLE_APPROVER));
        System.assert(roles.contains(MeetingRoleResolver.ROLE_SECOND_APPROVER));
        System.assert(roles.contains(MeetingRoleResolver.ROLE_CO_ORGANIZER));
        System.assert(roles.contains(MeetingRoleResolver.ROLE_PARTICIPANT));
    }

    @IsTest
    static void historyServiceWritePaths() {
        Meeting__c meeting = new Meeting__c(
            RecordTypeId = meetingRtId('Speaker_Meeting'),
            Status__c = 'Draft'
        );
        insert meeting;

        MeetingHistoryService.writeTransition(null, 'Draft', 'Approved', 'Approve', null);
        MeetingHistoryService.writeBulk(null);
        MeetingHistoryService.writeBulk(new List<Meeting_History__c>());
        MeetingHistoryService.writeTransition(meeting.Id, 'Draft', 'PendingApproval', 'SubmitForApproval', 'go');
        MeetingHistoryService.writeBulk(
            new List<Meeting_History__c>{
                new Meeting_History__c(
                    Meeting__c = meeting.Id,
                    From_Status__c = 'PendingApproval',
                    To_Status__c = 'Approved',
                    Action_Key__c = 'Approve',
                    Changed_By__c = UserInfo.getUserId()
                )
            }
        );
        System.assertEquals(2, [SELECT COUNT() FROM Meeting_History__c WHERE Meeting__c = :meeting.Id]);
    }

    @IsTest
    static void adminControllerActionsAndSave() {
        MeetingWorkflowSeed.SeedResult seeded = MeetingWorkflowAdminController.seedTemplates(true);
        System.assert(seeded.workflowsPublished >= 1, seeded.message);

        List<MeetingWorkflowAdminController.WorkflowListItem> items = MeetingWorkflowAdminController.listWorkflows();
        System.assert(!items.isEmpty());

        Id draftId = MeetingWorkflowAdminController.cloneWorkflow(items[0].id);
        Meeting_Workflow__c header = MeetingWorkflowAdminController.saveWorkflowHeader(
            new Meeting_Workflow__c(Id = draftId, Description__c = 'Coverage update')
        );
        System.assertEquals('Coverage update', header.Description__c);

        MeetingWorkflowPublisher.PublishResult republish = MeetingWorkflowAdminController.publishWorkflow(draftId);
        System.assertEquals(true, republish.success, republish.message);

        Meeting__c meeting = new Meeting__c(
            RecordTypeId = meetingRtId('Speaker_Meeting'),
            Status__c = 'Draft',
            Objectives__c = 'Admin evaluate'
        );
        insert meeting;
        insert new Meeting_Member__c(
            Meeting__c = meeting.Id,
            RecordTypeId = memberColleagueRtId(),
            Colleague__c = UserInfo.getUserId(),
            Type__c = 'Approver',
            System_Generated__c = true
        );

        MeetingWorkflowService.EvaluationResult eval = MeetingWorkflowAdminController.evaluateMeeting(meeting.Id);
        System.assertEquals(true, eval.canEditMeeting);
        System.assert(!eval.statusPath.isEmpty(), 'Expected status path for Path UI');
        System.assertEquals('Draft', eval.statusPath[0].value);
        Boolean hasCurrent = false;
        for (MeetingWorkflowService.StatusPathDto step : eval.statusPath) {
            if (step.isCurrent == true) {
                hasCurrent = true;
                System.assertEquals('Draft', step.value);
            }
        }
        System.assertEquals(true, hasCurrent);

        MeetingWorkflowService.TransitionResult transition = MeetingWorkflowAdminController.applyMeetingAction(
            meeting.Id,
            'SubmitForApproval',
            null
        );
        System.assertEquals(true, transition.success, transition.message);

        Boolean detailFailed = false;
        try {
            MeetingWorkflowAdminController.getWorkflowDetail(null);
        } catch (AuraHandledException e) {
            detailFailed = true;
        }
        System.assertEquals(true, detailFailed);
    }

    @IsTest
    static void adminCreateCloneSaveStatusesAndArchive() {
        Id createdId = MeetingWorkflowAdminController.createDraftWorkflow(
            'Speaker_Meeting',
            'Custom Speaker Draft',
            'GPM'
        );
        System.assertNotEquals(null, createdId);

        List<Meeting_WF_Status__c> statuses = new List<Meeting_WF_Status__c>{
            new Meeting_WF_Status__c(
                Status_Value__c = 'Draft',
                Status_Label__c = 'Draft',
                Sort_Order__c = 10,
                Is_Terminal__c = false
            ),
            new Meeting_WF_Status__c(
                Status_Value__c = 'PendingApproval',
                Status_Label__c = 'Pending Approval',
                Sort_Order__c = 20,
                Is_Terminal__c = false
            ),
            new Meeting_WF_Status__c(
                Status_Value__c = 'Closed',
                Status_Label__c = 'Closed',
                Sort_Order__c = 30,
                Is_Terminal__c = true
            )
        };
        List<Meeting_WF_Status__c> saved = MeetingWorkflowAdminController.saveStatuses(createdId, statuses);
        System.assertEquals(3, saved.size());

        MeetingWorkflowAdminController.RolePolicyBundle bundle = new MeetingWorkflowAdminController.RolePolicyBundle();
        bundle.policy = new Meeting_WF_Role_Policy__c(
            Status_Value__c = 'Draft',
            Role_Key__c = 'Organizer',
            Can_Edit_Meeting__c = true
        );
        bundle.actions = new List<Meeting_WF_Action__c>{
            new Meeting_WF_Action__c(
                Action_Key__c = 'SubmitForApproval',
                Label__c = 'Submit',
                Target_Status__c = 'PendingApproval',
                Sort_Order__c = 1
            )
        };
        bundle.relatedPolicies = new List<Meeting_WF_Related_Policy__c>{
            new Meeting_WF_Related_Policy__c(
                Related_Object__c = 'Meeting_Member__c',
                Can_Create__c = true,
                Can_Edit__c = true
            )
        };
        Meeting_WF_Role_Policy__c policy = MeetingWorkflowAdminController.saveRolePolicyBundle(createdId, bundle);
        System.assertNotEquals(null, policy.Id);

        MeetingWorkflowAdminController.saveApproverRules(
            createdId,
            new List<Meeting_WF_Approver_Rule__c>{
                new Meeting_WF_Approver_Rule__c(First_Approver_Mode__c = 'OwnerManager')
            }
        );
        MeetingWorkflowAdminController.saveSkipRules(
            createdId,
            new List<Meeting_WF_Skip_Rule__c>{
                new Meeting_WF_Skip_Rule__c(
                    Priority__c = 10,
                    From_Status__c = 'PendingApproval',
                    To_Status__c = 'Closed',
                    Condition_Type__c = 'Always',
                    Record_Types__c = '*'
                )
            }
        );
        MeetingWorkflowAdminController.saveSideEffects(
            createdId,
            new List<Meeting_WF_Side_Effect__c>{
                new Meeting_WF_Side_Effect__c(
                    From_Status__c = '*',
                    To_Status__c = 'Closed',
                    Effect_Type__c = 'SetFlags'
                )
            }
        );

        MeetingWorkflowPublisher.PublishResult pub = MeetingWorkflowAdminController.publishWorkflow(createdId);
        System.assertEquals(true, pub.success, pub.message);

        Id cloneId = MeetingWorkflowAdminController.cloneWorkflow(createdId);
        MeetingWorkflowAdminController.WorkflowDetail cloneDetail = MeetingWorkflowAdminController.getWorkflowDetail(
            cloneId
        );
        System.assertEquals(true, cloneDetail.isEditable);
        System.assertEquals(3, cloneDetail.statuses.size());

        MeetingWorkflowAdminController.archiveWorkflow(createdId);
        Meeting_Workflow__c archived = [
            SELECT Is_Published__c, Is_Draft__c
            FROM Meeting_Workflow__c
            WHERE Id = :createdId
        ];
        System.assertEquals(false, archived.Is_Published__c);
        System.assertEquals(false, archived.Is_Draft__c);

        System.assert(!MeetingWorkflowAdminController.getMeetingRecordTypes().isEmpty());
    }

    @IsTest
    static void adminRelatedListMatrixAndApprovalSetup() {
        Id workflowId = MeetingWorkflowAdminController.createDraftWorkflow(
            'Speaker_Meeting',
            'Matrix Speaker Draft',
            'GPM'
        );
        MeetingWorkflowAdminController.saveStatuses(
            workflowId,
            new List<Meeting_WF_Status__c>{
                new Meeting_WF_Status__c(
                    Status_Value__c = 'Draft',
                    Status_Label__c = 'Draft',
                    Sort_Order__c = 10
                ),
                new Meeting_WF_Status__c(
                    Status_Value__c = 'PendingApproval',
                    Status_Label__c = 'Pending Approval',
                    Sort_Order__c = 20
                ),
                new Meeting_WF_Status__c(
                    Status_Value__c = 'Approved',
                    Status_Label__c = 'Approved',
                    Sort_Order__c = 30
                )
            }
        );

        MeetingWorkflowAdminController.RelatedAccessCell hidden = new MeetingWorkflowAdminController.RelatedAccessCell();
        hidden.statusValue = 'Draft';
        hidden.relatedObject = 'Meeting_Expense__c';
        hidden.recordTypeFilter = 'Actual';
        hidden.accessLevel = 'hidden';
        MeetingWorkflowAdminController.RelatedAccessCell modify = new MeetingWorkflowAdminController.RelatedAccessCell();
        modify.statusValue = 'Draft';
        modify.relatedObject = 'Meeting_Member__c';
        modify.recordTypeFilter = 'Attendee;Non_Profiled_Attendee;Write_In';
        modify.accessLevel = 'modify';
        MeetingWorkflowAdminController.saveRelatedListMatrix(
            workflowId,
            new List<MeetingWorkflowAdminController.RelatedAccessCell>{ hidden, modify }
        );

        MeetingWorkflowAdminController.ApprovalSetup setup = new MeetingWorkflowAdminController.ApprovalSetup();
        setup.firstApproverMode = 'OwnerManager';
        setup.secondApproverMode = 'None';
        setup.createManagerAsApprover = true;
        setup.skipRules = new List<Meeting_WF_Skip_Rule__c>{
            new Meeting_WF_Skip_Rule__c(
                Priority__c = 10,
                From_Status__c = 'PendingApproval',
                To_Status__c = 'Approved',
                Condition_Type__c = 'OwnerTitleContains',
                Condition_Values__c = 'Manager',
                Record_Types__c = '*'
            )
        };
        MeetingWorkflowAdminController.saveApprovalSetup(workflowId, setup);

        MeetingWorkflowAdminController.WorkflowDetail detail = MeetingWorkflowAdminController.getWorkflowDetail(
            workflowId
        );
        System.assertEquals(1, detail.approverRules.size());
        System.assertEquals(1, detail.skipRules.size());
        Boolean foundMembers = false;
        Boolean foundHiddenExpense = false;
        for (Meeting_WF_Role_Policy__c policy : detail.rolePolicies) {
            if (policy.Role_Key__c != 'Organizer' || policy.Status_Value__c != 'Draft') {
                continue;
            }
            for (Meeting_WF_Related_Policy__c related : policy.Related_Policies__r) {
                if (related.Related_Object__c == 'Meeting_Member__c' && related.Can_Create__c == true) {
                    foundMembers = true;
                }
                if (related.Related_Object__c == 'Meeting_Expense__c' && related.Is_Visible__c == false) {
                    foundHiddenExpense = true;
                }
            }
        }
        System.assertEquals(true, foundMembers);
        System.assertEquals(true, foundHiddenExpense);
    }
}