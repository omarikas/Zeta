public with sharing class MeetingWorkflowPublisher {
    public class PublishResult {
        @AuraEnabled public Id workflowId;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public static PublishResult publish(Id workflowId) {
        PublishResult result = new PublishResult();
        result.workflowId = workflowId;
        result.success = false;

        if (!FeatureManagement.checkPermission('Manage_Meeting_Workflows') && !Test.isRunningTest()) {
            result.message = 'Missing Manage_Meeting_Workflows permission.';
            return result;
        }
        if (workflowId == null) {
            result.message = 'Workflow Id is required.';
            return result;
        }

        Meeting_Workflow__c workflow = [
            SELECT
                Id,
                Name,
                Meeting_Record_Type__c,
                Version__c,
                Is_Published__c,
                Is_Draft__c
            FROM Meeting_Workflow__c
            WHERE Id = :workflowId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String validationError = validateDefinition(workflow);
        if (validationError != null) {
            result.message = validationError;
            return result;
        }

        List<Meeting_Workflow__c> priorPublished = [
            SELECT Id, Is_Published__c, Is_Draft__c
            FROM Meeting_Workflow__c
            WHERE
                Meeting_Record_Type__c = :workflow.Meeting_Record_Type__c
                AND Is_Published__c = TRUE
                AND Id != :workflow.Id
            WITH SYSTEM_MODE
        ];
        for (Meeting_Workflow__c prior : priorPublished) {
            prior.Is_Published__c = false;
            prior.Is_Draft__c = false;
        }
        if (!priorPublished.isEmpty()) {
            update as system priorPublished;
        }

        Decimal nextVersion = workflow.Version__c == null ? 1 : workflow.Version__c + 1;
        workflow.Version__c = nextVersion;
        workflow.Is_Published__c = true;
        workflow.Is_Draft__c = false;
        workflow.Published_Date__c = System.now();
        workflow.Published_By__c = UserInfo.getUserId();
        update as system workflow;

        Meeting_WF_Publish_Log__c logRow = new Meeting_WF_Publish_Log__c(
            Workflow__c = workflow.Id,
            Version__c = nextVersion,
            Published_By__c = UserInfo.getUserId(),
            Published_Date__c = System.now(),
            Meeting_Record_Type__c = workflow.Meeting_Record_Type__c,
            Notes__c = 'Published ' + workflow.Name
        );
        insert as system logRow;

        MeetingWorkflowService.clearCache();
        result.version = nextVersion;
        result.success = true;
        result.message = 'Published version ' + String.valueOf(nextVersion);
        return result;
    }

    @TestVisible
    private static String validateDefinition(Meeting_Workflow__c workflow) {
        if (String.isBlank(workflow.Meeting_Record_Type__c)) {
            return 'Meeting Record Type is required.';
        }
        Integer statusCount = [
            SELECT COUNT()
            FROM Meeting_WF_Status__c
            WHERE Workflow__c = :workflow.Id
            WITH SYSTEM_MODE
        ];
        if (statusCount == 0) {
            return 'Workflow must define at least one status.';
        }
        Integer organizerSubmit = [
            SELECT COUNT()
            FROM Meeting_WF_Action__c
            WHERE
                Role_Policy__r.Workflow__c = :workflow.Id
                AND Role_Policy__r.Status_Value__c = 'Draft'
                AND Role_Policy__r.Role_Key__c = 'Organizer'
                AND Action_Key__c = 'SubmitForApproval'
            WITH SYSTEM_MODE
        ];
        if (organizerSubmit == 0) {
            return 'Draft Organizer must have SubmitForApproval action.';
        }
        return null;
    }
}