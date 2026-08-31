public with sharing class FieldForceAffiliationAgentAction {
    @InvocableMethod(
        label='Get Affiliation Brief'
        description='Returns active affiliations for an Account, or for the account on a Visit record.'
    )
    public static List<FieldForceAgentActions.BriefResult> getAffiliationBrief(
        List<FieldForceAgentActions.AffiliationRequest> requests
    ) {
        return FieldForceAgentActions.buildAffiliationBrief(requests);
    }
}