public with sharing class ClmPdfViewerController {

    @AuraEnabled(cacheable=false)
    public static String getPdfBase64ForPlayer(String contentDocumentId) {
        try {
            return loadPdfBase64(contentDocumentId);
        } catch (ClmViewerException error) {
            throw new AuraHandledException(error.getMessage());
        }
    }

    @RemoteAction
    public static String getPdfBase64(String contentDocumentId) {
        return loadPdfBase64(contentDocumentId);
    }

    private static String loadPdfBase64(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            throw new ClmViewerException('Presentation file is missing. Ask your admin to re-upload the deck.');
        }

        List<ContentVersion> versions = [
            SELECT VersionData, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new ClmViewerException(
                'Presentation file not found or not accessible. Confirm the deck is shared to your territory.'
            );
        }
        Decimal contentSize = versions[0].ContentSize;
        if (contentSize != null && contentSize > 4500000) {
            throw new ClmViewerException(
                'This presentation is too large to load through Apex (' +
                String.valueOf((contentSize / 1048576).setScale(1)) +
                ' MB). The mobile client downloads large decks from Files directly.'
            );
        }

        Blob versionData = versions[0].VersionData;
        if (versionData == null || versionData.size() == 0) {
            throw new ClmViewerException('Presentation file is empty or unavailable.');
        }

        return EncodingUtil.base64Encode(versionData);
    }

    public class ClmViewerException extends Exception {}
}