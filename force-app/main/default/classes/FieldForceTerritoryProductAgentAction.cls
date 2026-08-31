public with sharing class FieldForceTerritoryProductAgentAction {
    @InvocableMethod(
        label='Get Territory Product Classification Brief'
        description='Returns territory-aligned products and account classification mix for the field rep territory.'
    )
    public static List<FieldForceAgentActions.BriefResult> getTerritoryProductBrief(
        List<FieldForceAgentActions.TerritoryProductRequest> requests
    ) {
        return FieldForceAgentActions.buildTerritoryProductBrief(requests);
    }
}