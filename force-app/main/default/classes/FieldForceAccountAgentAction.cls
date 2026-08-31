public with sharing class FieldForceAccountAgentAction {
    @InvocableMethod(
        label='Get Account Field Brief'
        description='Returns visit pace, plan-cycle targets, upcoming visits, and nearby accounts for an HCP account record.'
    )
    public static List<FieldForceAgentActions.BriefResult> getAccountFieldBrief(
        List<FieldForceAgentActions.AccountFieldRequest> requests
    ) {
        return FieldForceAgentActions.buildAccountFieldBrief(requests);
    }
}