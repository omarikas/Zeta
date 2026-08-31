public with sharing class FieldForcePlannerAgentAction {
    @InvocableMethod(
        label='Get Planner Week Brief'
        description='Returns this week visits, time off blocks, and scheduling gaps for the field planner page.'
    )
    public static List<FieldForceAgentActions.BriefResult> getPlannerWeekBrief(
        List<FieldForceAgentActions.PlannerWeekRequest> requests
    ) {
        return FieldForceAgentActions.buildPlannerWeekBrief(requests);
    }
}