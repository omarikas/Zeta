@IsTest
private class ClmPdfSmokeTest {
    @IsTest
    static void coversPdfViewerAndContentHelpers() {
        ContentVersion version = new ContentVersion(
            Title = 'clm-smoke.pdf',
            PathOnClient = 'clm-smoke.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 smoke'),
            IsMajorVersion = true
        );
        insert version;
        version = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :version.Id LIMIT 1];

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Smoke Deck',
            Status__c = 'Available',
            Format__c = 'PDF',
            Slide_Count__c = 1,
            Content_Document_Id__c = version.ContentDocumentId
        );
        insert presentation;

        ClmContentService.linkContentDocumentToPresentation(version.ContentDocumentId, presentation.Id);
        ClmContentService.linkContentDocumentToPresentation(version.ContentDocumentId, presentation.Id);

        System.assertNotEquals(null, ClmContentService.buildSlideImageUrl(version.Id));
        System.assertNotEquals(null, ClmContentService.buildPdfPageRenditionUrl(version.Id, 1));
        System.assertNotEquals(null, ClmContentService.buildPdfPageHighResUrl(version.Id, 2));
        System.assertEquals(null, ClmContentService.buildPdfPageRenditionUrl(null, 1));
        System.assertEquals(null, ClmContentService.buildPdfPageHighResUrl('', 1));
        System.assertNotEquals(null, ClmContentService.buildDocumentDownloadUrl(version.ContentDocumentId));
        System.assertNotEquals(null, ClmContentService.buildThumbnailUrl(version.Id));
        System.assertEquals(null, ClmContentService.normalizeContentUrl(null));
        System.assertNotEquals(null, ClmContentService.normalizeContentUrl('/sfc/servlet.shepherd/version/download/' + version.Id));
        System.assertEquals(null, ClmContentService.normalizeContentUrl('/sfc/servlet.shepherd/document/download/' + version.ContentDocumentId));
        System.assertEquals('https://example.com/x', ClmContentService.normalizeContentUrl('https://example.com/x'));
        System.assertNotEquals(null, ClmContentService.buildContentUrl(version.Id, null));
        System.assertNotEquals(null, ClmContentService.buildContentUrl(version.Id, '/sfc/servlet.shepherd/version/download/' + version.Id));

        String encodedPlayer = ClmPdfViewerController.getPdfBase64ForPlayer(version.ContentDocumentId);
        String encodedRemote = ClmPdfViewerController.getPdfBase64(version.ContentDocumentId);
        System.assertEquals(encodedPlayer, encodedRemote);
        System.assert(encodedPlayer.length() > 0);

        Boolean threw = false;
        try {
            ClmPdfViewerController.getPdfBase64ForPlayer(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);

        threw = false;
        try {
            ClmPdfViewerController.getPdfBase64ForPlayer('069000000000000AAA');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);

        Integer pages = ClmPdfParser.getPageCount(Blob.valueOf('%PDF-1.4\n/Type /Page\n/Type /Page\n'));
        System.assert(pages >= 1);
        pages = ClmPdfParser.getPageCount(Blob.valueOf('%PDF-1.4\n/Count 3\n'));
        System.assert(pages >= 1);
        pages = ClmPdfParser.getPageCount(Blob.valueOf('not-a-pdf'));
        System.assertEquals(1, pages);
    }
}