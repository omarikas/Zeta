@IsTest
private class ClmMetricsSmokeTest {
    @IsTest
    static void adHocPresentationLifecycle() {
        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Metrics Smoke Deck',
            Status__c = 'Available',
            Format__c = 'PDF',
            Slide_Count__c = 1,
            Allow_Unaligned__c = true,
            Tags__c = 'Smoke'
        );
        insert presentation;

        CLM_Sequence__c sequence = new CLM_Sequence__c(
            CLM_Presentation__c = presentation.Id,
            Sequence_Order__c = 1,
            Sequence_Name__c = 'Intro',
            Name = 'Intro',
            Page_Number__c = 1,
            File_Name__c = 'smoke.pdf',
            Product_Names__c = 'Smoke Product',
            Message_Names__c = 'Efficacy',
            HTML_Entry_Point__c = 'index.html',
            Slide_Image_URL__c = 'https://example.com/slide.png'
        );
        insert sequence;

        Test.startTest();
        ClmMetricsController.AdHocPresentationStart started =
            ClmMetricsController.startAdHocSession(presentation.Id);
        System.assertNotEquals(null, started.visitId);

        ClmMetricsController.SessionSummary session =
            ClmMetricsController.startAdHocPresentation(presentation.Id);
        System.assertNotEquals(null, session);
        System.assertNotEquals(null, session.id);
        System.assertNotEquals(null, session.visitId);
        System.assertEquals('PDF', session.formatType);
        System.assertEquals(1, session.sequences.size());
        System.assertEquals(sequence.Id, session.sequences[0].id);
        System.assertEquals('index.html', session.sequences[0].htmlEntryPoint);

        ClmMetricsController.logSlideEvent(session.id, sequence.Id, 5, false);
        ClmMetricsController.logSlideEvent(session.id, sequence.Id, 3, true);

        ClmMetricsController.MessageResponseInput msg = new ClmMetricsController.MessageResponseInput();
        msg.productName = 'Smoke Product';
        msg.messageName = 'Efficacy';
        msg.sentiment = 'Positive';
        msg.sortOrder = 1;
        ClmMetricsController.saveMessageResponses(
            session.id,
            new List<ClmMetricsController.MessageResponseInput>{ msg }
        );
        List<ClmMetricsController.MessageResponseInput> saved =
            ClmMetricsController.getSessionMessageResponses(session.id);
        System.assertEquals(1, saved.size());

        List<ClmMetricsController.SessionSummary> visitSessions =
            ClmMetricsController.getVisitSessions(session.visitId);
        System.assert(!visitSessions.isEmpty());

        List<ClmMetricsController.PresentationSummary> available =
            ClmMetricsController.getAvailablePresentations(null);
        System.assert(!available.isEmpty(), 'Expected at least one available presentation');

        List<ClmMetricsController.PresentationSummary> repPresentations =
            ClmMetricsController.getRepPresentations();
        System.assert(!repPresentations.isEmpty(), 'Expected getRepPresentations to be non-empty');

        List<ClmMetricsController.PresentationPrefetch> manifest =
            ClmMetricsController.getRepPresentationManifest();
        System.assert(!manifest.isEmpty());

        ClmMetricsController.SessionSummary fromVisit =
            ClmMetricsController.startSession(session.visitId, presentation.Id);
        System.assertNotEquals(null, fromVisit.id);

        System.assertEquals(null, ClmMetricsController.getDeployedRatingLayoutJson());
        System.assertNotEquals(null, ClmMetricsController.getRatingCaptureContext(session.visitId, session.id));
        System.assertNotEquals(null, ClmMetricsController.loadAccountRatingContext(null));
        Boolean emptyRatingsThrew = false;
        try {
            ClmMetricsController.saveAccountRatings(null, null, null, null, null);
        } catch (AuraHandledException ex) {
            emptyRatingsThrew = true;
        }
        System.assertEquals(true, emptyRatingsThrew);
        ClmMetricsController.saveVisitRatings(session.visitId, session.id, null, null);
        System.assertNotEquals(null, ClmMetricsController.validateAccountRatings(null, null));

        ClmMetricsController.SessionSummary completed =
            ClmMetricsController.completeSession(session.id);
        System.assertEquals('Completed', completed.status);

        ClmMetricsController.SessionSummary other =
            ClmMetricsController.startAdHocPresentation(presentation.Id);
        ClmMetricsController.cancelSession(other.id);
        ClmMetricsController.SessionSummary cancelled =
            ClmMetricsController.getSessionDetail(other.id);
        System.assertEquals('Cancelled', cancelled.status);
        Test.stopTest();
    }

    @IsTest
    static void rejectsInvalidSessionCalls() {
        Boolean threw = false;
        try {
            ClmMetricsController.logSlideEvent(null, null, 1, false);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);

        threw = false;
        try {
            ClmMetricsController.completeSession(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);

        threw = false;
        try {
            ClmMetricsController.cancelSession(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);

        threw = false;
        try {
            ClmMetricsController.startAdHocPresentation(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);

        System.assertEquals(0, ClmMetricsController.getVisitSessions(null).size());
        System.assertEquals(0, ClmMetricsController.getSessionMessageResponses(null).size());
    }

    @IsTest
    static void coversPresentationFiltersAndRatingParsers() {
        insert new List<CLM_Presentation__c>{
            new CLM_Presentation__c(
                Name = 'Future Smoke Deck',
                Status__c = 'Available',
                Format__c = 'PDF',
                Slide_Count__c = 1,
                Allow_Unaligned__c = true,
                Start_Date__c = Date.today().addDays(10)
            ),
            new CLM_Presentation__c(
                Name = 'Territory Smoke Deck',
                Status__c = 'Available',
                Format__c = 'PDF',
                Slide_Count__c = 1,
                Allow_Unaligned__c = false,
                Territory_Ids__c = '0MIxxxxxxxxxxx'
            )
        };

        Test.startTest();
        ClmMetricsController.getAvailablePresentations(null);
        ClmMetricsController.getRepPresentationManifest();
        ClmMetricsController.saveMessageResponses(UserInfo.getUserId(), new List<ClmMetricsController.MessageResponseInput>());

        try {
            ClmMetricsController.saveAccountRatings(null, null, null, '{}', '{}');
        } catch (Exception ignore) {
        }
        try {
            ClmMetricsController.saveAccountRatings(
                null,
                null,
                null,
                '[{"objectApiName":"Account","fieldApiName":"Description","valueJson":"Rated"},{"objectApiName":"","fieldApiName":"Skip"},"skip"]',
                '[{"product2Id":null},{"product2Id":"01t000000000000AAA","values":[{"objectApiName":"Account","fieldApiName":"Description","valueJson":"P"},{}]}]'
            );
        } catch (Exception ignore) {
        }
        Test.stopTest();
    }
}