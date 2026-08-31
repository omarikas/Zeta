public with sharing class ClmPdfParser {

    public static Integer getPageCount(Blob pdfBlob) {
        if (pdfBlob == null || pdfBlob.size() == 0) {
            return 1;
        }

        String pdfText = blobToPdfText(pdfBlob);
        if (String.isBlank(pdfText)) {
            return 1;
        }

        Integer pageTypeCount = countPageObjects(pdfText);
        if (pageTypeCount > 0) {
            return pageTypeCount;
        }

        Integer catalogCount = extractCatalogPageCount(pdfText);
        return catalogCount > 0 ? catalogCount : 1;
    }

    private static String blobToPdfText(Blob pdfBlob) {
        try {
            return pdfBlob.toString();
        } catch (Exception ex) {
            return '';
        }
    }

    private static Integer countPageObjects(String pdfText) {
        if (String.isBlank(pdfText)) {
            return 0;
        }
        Matcher pageMatcher = Pattern.compile('/Type\\s*/Page(?!s)').matcher(pdfText);
        Integer count = 0;
        while (pageMatcher.find()) {
            count++;
        }
        return count;
    }

    private static Integer extractCatalogPageCount(String pdfText) {
        Integer maxCount = 0;
        Integer searchFrom = 0;
        while (true) {
            Integer countIndex = pdfText.indexOf('/Count', searchFrom);
            if (countIndex < 0) {
                break;
            }
            String tail = pdfText.substring(countIndex, Math.min(countIndex + 24, pdfText.length()));
            Matcher matcher = Pattern.compile('/Count\\s+(\\d+)').matcher(tail);
            if (matcher.find()) {
                Integer value = Integer.valueOf(matcher.group(1));
                if (value > maxCount) {
                    maxCount = value;
                }
            }
            searchFrom = countIndex + 6;
        }
        return maxCount;
    }
}