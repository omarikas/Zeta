@IsTest
private class ClmRatingLayoutSeedTest {
    @IsTest
    static void seedAndDeploy_createsDeployedHcpAndHcoLayouts() {
        System.assert(ClmRatingLayoutSeed.standardLayoutJson('HCP').contains('HCP_Classification__c'));
        System.assert(ClmRatingLayoutSeed.standardLayoutJson('HCO').contains('Potentiality'));
        System.assertEquals('HCP', ClmRatingLayoutSeed.resolveVariant(null));

        Test.startTest();
        ClmRatingLayoutSeed.SeedResult result = ClmRatingLayoutSeed.seedAndDeploy();
        Test.stopTest();

        System.assertNotEquals(null, result.hcpLayoutId);
        System.assertNotEquals(null, result.hcoLayoutId);
        System.assertEquals(2, [SELECT COUNT() FROM CLM_Rating_Layout__c WHERE Status__c = 'Deployed']);

        List<ClmAdminController.RatingLayoutRow> rows = ClmAdminController.getRatingLayouts();
        System.assertEquals(2, rows.size());
        System.assert(ClmAdminController.getRatingLayoutPreviewSample().contains('Is_Speaker__c'));
        System.assertEquals(6, ClmAdminController.getRatingFieldCatalog().size());

        ClmAdminController.RatingLayoutRow draft = new ClmAdminController.RatingLayoutRow();
        draft.name = 'Draft Extra Layout';
        draft.status = 'Draft';
        draft.fieldsJson = ClmRatingLayoutSeed.standardLayoutJson('HCP');
        ClmAdminController.RatingLayoutRow saved = ClmAdminController.saveRatingLayout(draft);
        System.assertNotEquals(null, saved.id);
        ClmAdminController.deployRatingLayout(saved.id);

        ClmRatingLayoutSeed.SeedResult again = ClmRatingLayoutSeed.seedAndDeploy();
        System.assertEquals(result.hcpLayoutId, again.hcpLayoutId);
        System.assertEquals(result.hcoLayoutId, again.hcoLayoutId);

        System.assertEquals(0, ClmAdminController.getPresentations(null).size());
        System.assertEquals(0, ClmAdminController.getTerritories().size());
        System.assertEquals(0, ClmAdminController.getProductOptions().size());
        ClmAdminController.deactivatePresentation(null);
        System.assertEquals(null, ClmAdminController.createPresentationDraft(null, null, null, null));
        System.assertEquals(0, ClmAdminController.attachSlideImages(null, null).size());
        System.assertEquals(0, ClmAdminController.generateSequencesFromPageCount(null, null, null).size());
        System.assertEquals(0, ClmAdminController.getSequences(null).size());
        System.assertEquals(0, ClmAdminController.saveSequences(null, null).size());
        System.assertEquals(null, ClmAdminController.getPresentationDraft(null));
        System.assertEquals(
            null,
            ClmAdminController.finalizePresentation(
                null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
            )
        );
        System.assertEquals(0, ClmAdminController.getTerritoryProductAlignments(null).size());
    }
}