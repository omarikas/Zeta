public with sharing class FieldForceHomeAgentAction {
    @InvocableMethod(
        label='Get Home Dashboard Brief'
        description='Returns coverage KPIs, RF% by classification, today plan, and next best customers for the field rep home page.'
    )
    public static List<FieldForceAgentActions.BriefResult> getHomeDashboardBrief(
        List<FieldForceAgentActions.HomeDashboardRequest> requests
    ) {
        return FieldForceAgentActions.buildHomeDashboardBrief(requests);
    }
}