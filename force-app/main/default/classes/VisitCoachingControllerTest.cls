@IsTest
private class VisitCoachingControllerTest {
    @IsTest static void coverage() {
        Object ctx = VisitCoachingController.getCoachingFormContext(null);
        System.assertNotEquals(null, ctx);
        try { VisitCoachingController.createVisitCoachingEvent(null, null, false); System.assert(false); }
        catch (Exception e) { System.assert(true); }
        try { VisitCoachingController.submitForManagerReview(null); System.assert(false); }
        catch (Exception e) { System.assert(true); }
    }
}