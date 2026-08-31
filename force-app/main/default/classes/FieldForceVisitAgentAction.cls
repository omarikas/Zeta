public with sharing class FieldForceVisitAgentAction {
    @InvocableMethod(
        label='Get Visit Call Brief'
        description='Returns visit call-report context: account, status, attendees, detailed products, samples, and affiliations.'
    )
    public static List<FieldForceAgentActions.BriefResult> getVisitCallBrief(
        List<FieldForceAgentActions.VisitCallRequest> requests
    ) {
        return FieldForceAgentActions.buildVisitCallBrief(requests);
    }
}