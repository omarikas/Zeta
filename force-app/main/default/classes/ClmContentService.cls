public with sharing class ClmContentService {

    public static void linkContentDocumentToPresentation(Id contentDocumentId, Id presentationId) {
        if (contentDocumentId == null || presentationId == null) {
            return;
        }

        List<ContentDocumentLink> existing = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
              AND LinkedEntityId = :presentationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }

        insert as user new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = presentationId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    public static String buildSlideImageUrl(String contentVersionId) {
        if (String.isBlank(contentVersionId)) {
            return null;
        }
        return '/sfc/servlet.shepherd/version/renditionDownload?rendition=ORIGINAL_Png&versionId='
            + contentVersionId;
    }

    /**
     * Page-level PDF/PPT preview image. pageNumber is 1-based (matches CLM_Sequence__c.Page_Number__c).
     * Renditions display inline in <img>; document/download URLs often force attachment downloads.
     */
    public static String buildPdfPageRenditionUrl(String contentVersionId, Integer pageNumber) {
        if (String.isBlank(contentVersionId)) {
            return null;
        }
        Integer pageIndex = pageNumber != null && pageNumber > 0 ? pageNumber - 1 : 0;
        return '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId='
            + contentVersionId
            + '&page='
            + String.valueOf(pageIndex);
    }

    public static String buildPdfPageHighResUrl(String contentVersionId, Integer pageNumber) {
        if (String.isBlank(contentVersionId)) {
            return null;
        }
        Integer pageIndex = pageNumber != null && pageNumber > 0 ? pageNumber - 1 : 0;
        return '/sfc/servlet.shepherd/version/renditionDownload?rendition=SVGZ&versionId='
            + contentVersionId
            + '&page='
            + String.valueOf(pageIndex);
    }

    public static String buildDocumentDownloadUrl(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            return null;
        }
        return '/sfc/servlet.shepherd/document/download/' + contentDocumentId;
    }

    public static String buildThumbnailUrl(String contentVersionId) {
        if (String.isBlank(contentVersionId)) {
            return null;
        }
        return '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId='
            + contentVersionId;
    }

    public static String normalizeContentUrl(String url) {
        if (String.isBlank(url)) {
            return null;
        }
        if (url.contains('/sfc/servlet.shepherd/version/download/')) {
            return buildSlideImageUrl(url.substringAfterLast('/'));
        }
        if (url.contains('/sfc/servlet.shepherd/document/download/')) {
            return null;
        }
        return url;
    }

    public static String buildContentUrl(String contentVersionId, String slideImageUrl) {
        String normalizedSlideUrl = normalizeContentUrl(slideImageUrl);
        if (String.isNotBlank(normalizedSlideUrl)) {
            return normalizedSlideUrl;
        }
        return buildThumbnailUrl(contentVersionId);
    }
}