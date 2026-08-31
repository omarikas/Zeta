public with sharing class VisitCoachingController {
    @AuraEnabled(cacheable=true)
    public static Object getCoachingFormContext(Id visitId) {
        return new Map<String, Object>{ 'available' => false, 'message' => 'Coaching module migrating' };
    }
    @AuraEnabled
    public static Object createVisitCoachingEvent(Id visitId, Id templateId, Boolean prefillFromVisit) {
        throw new AuraHandledException('Coaching module is being migrated. Try again shortly.');
    }
    @AuraEnabled
    public static void submitForManagerReview(Id coachingEventId) {
        throw new AuraHandledException('Coaching module is being migrated. Try again shortly.');
    }
}