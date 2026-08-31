public with sharing class FieldForceAccountsTabAgentAction {
    @InvocableMethod(
        label='Get Accounts Tab Brief'
        description='Returns plan-cycle account worklist context: in/out of plan counts, behind-pace accounts, and classification mix.'
    )
    public static List<FieldForceAgentActions.BriefResult> getAccountsTabBrief(
        List<FieldForceAgentActions.AccountsTabRequest> requests
    ) {
        return FieldForceAgentActions.buildAccountsTabBrief(requests);
    }
}