/**
 * Fuzzy matching helpers for distributor product and sellout alias resolution.
 */
public with sharing class DistributorMatchingUtil {
    public static final Decimal DEFAULT_AUTO_CONFIRM = 85;

    public static String normalizeName(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String s = raw.toUpperCase();
        String cleaned = '';
        for (Integer i = 0; i < s.length(); i++) {
            Integer cp = s.charAt(i);
            Boolean isDigit = cp >= 48 && cp <= 57;
            Boolean isLatin = cp >= 65 && cp <= 90;
            Boolean isArabic = cp >= 1536 && cp <= 1791;
            Boolean isSpace = cp == 32 || cp == 47;
            if (isDigit || isLatin || isArabic || isSpace) {
                cleaned += s.substring(i, i + 1);
            } else {
                cleaned += ' ';
            }
        }
        s = cleaned.replaceAll('\\s+', ' ').trim();
        if (s.startsWith('PHARMACY ')) {
            s = s.substring(9).trim();
        } else if (s.startsWith('PH ')) {
            s = s.substring(3).trim();
        } else if (s.startsWith('DR. ')) {
            s = s.substring(4).trim();
        } else if (s.startsWith('DR ')) {
            s = s.substring(3).trim();
        }
        // Skip short Arabic letter prefixes when followed by space (common pharmacy naming)
        if (s.length() > 2 && s.substring(1, 2) == ' ' && s.charAt(0) >= 1536 && s.charAt(0) <= 1791) {
            s = s.substring(2).trim();
        }
        return s.trim();
    }

    public static String buildProductUniqueKey(String distributorCode, String itemCode) {
        return normalizeCode(distributorCode) + '|' + normalizeCode(itemCode);
    }

    public static String buildSelloutUniqueKey(String distributorCode, String clientCode) {
        return normalizeCode(distributorCode) + '|' + normalizeCode(clientCode);
    }

    public static String normalizeCode(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        return raw.trim().replaceAll('\\s+', '');
    }

    public static String normalizeDistributorCode(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String s = raw.trim();
        String upper = s.toUpperCase();
        if (upper == 'IBNSINA' || upper == 'IBN SINA' || upper == 'IBN-SINA') {
            return 'IBNSINA';
        }
        if (upper == 'EZZABI' || upper == 'EZZABY' || upper == 'ELEZABY' || upper == 'EL EZABY') {
            return 'Elezaby';
        }
        if (upper == 'EGYDRUG' || upper == 'EGYDURG') {
            return 'Egydrug';
        }
        if (
            upper == 'EBDA CUST' ||
            upper == 'EBDA_CUST' ||
            upper == 'EPDA CUST' ||
            upper == 'EPDA_CUST'
        ) {
            return 'EPDA Cust';
        }
        if (upper == 'SOFICO') {
            return 'Sofico';
        }
        if (upper == 'POS') {
            return 'POS';
        }
        // EPDA is correct; Ebda is a common typo accepted on import
        if (upper == 'EBDA' || upper == 'EPDA') {
            return 'EPDA';
        }
        if (upper == 'PHARMAOVERSEAS') {
            return 'Pharmaoverseas';
        }
        return s;
    }

    /** UI / related-list friendly label (EPDA, not the Ebda typo). */
    public static String displayDistributorLabel(String raw) {
        return normalizeDistributorCode(raw);
    }

    /**
     * Codes that should be treated as the same distributor when querying
     * (covers historical Ebda rows and the correct EPDA spelling).
     */
    public static List<String> distributorCodeVariants(String raw) {
        String code = normalizeDistributorCode(raw);
        if (code == 'EPDA') {
            return new List<String>{ 'EPDA', 'Ebda', 'EBDA' };
        }
        if (code == 'EPDA Cust') {
            return new List<String>{ 'EPDA Cust', 'Ebda Cust', 'EBDA Cust' };
        }
        if (String.isBlank(code)) {
            return new List<String>();
        }
        return new List<String>{ code };
    }

    public static String toDataSource(String distributorCode) {
        String code = normalizeDistributorCode(distributorCode);
        if (code == 'IBNSINA') {
            return 'IbnSina';
        }
        // Restricted picklist API value remains Ebda; label is EPDA
        if (code == 'EPDA' || code == 'EPDA Cust') {
            return 'Ebda';
        }
        return code;
    }

    public static Decimal nameSimilarity(String a, String b) {
        String na = normalizeName(a);
        String nb = normalizeName(b);
        if (String.isBlank(na) || String.isBlank(nb)) {
            return 0;
        }
        if (na == nb) {
            return 100;
        }
        if (na.contains(nb) || nb.contains(na)) {
            Decimal shorter = Math.min(na.length(), nb.length());
            Decimal longer = Math.max(na.length(), nb.length());
            return ((shorter / longer) * 100).setScale(2);
        }
        Set<String> ta = new Set<String>(na.split('\\s+'));
        Set<String> tb = new Set<String>(nb.split('\\s+'));
        ta.remove('');
        tb.remove('');
        if (ta.isEmpty() || tb.isEmpty()) {
            return 0;
        }
        Set<String> inter = new Set<String>(ta);
        inter.retainAll(tb);
        Set<String> uni = new Set<String>(ta);
        uni.addAll(tb);
        if (uni.isEmpty()) {
            return 0;
        }
        return ((Decimal.valueOf(inter.size()) / Decimal.valueOf(uni.size())) * 100).setScale(2);
    }

    public static Decimal haversineMeters(Decimal lat1, Decimal lng1, Decimal lat2, Decimal lng2) {
        if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
            return null;
        }
        Double r = 6371000;
        Double p1 = lat1.doubleValue() * Math.PI / 180;
        Double p2 = lat2.doubleValue() * Math.PI / 180;
        Double dp = (lat2.doubleValue() - lat1.doubleValue()) * Math.PI / 180;
        Double dl = (lng2.doubleValue() - lng1.doubleValue()) * Math.PI / 180;
        Double a =
            Math.sin(dp / 2) * Math.sin(dp / 2) +
            Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return Decimal.valueOf(r * c).setScale(2);
    }

    public static Decimal autoConfirmThreshold() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        if (cfg != null && cfg.Auto_Confirm_Threshold__c != null) {
            return cfg.Auto_Confirm_Threshold__c;
        }
        return DEFAULT_AUTO_CONFIRM;
    }

    public static Decimal proximityMeters() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        if (cfg != null && cfg.Proximity_Meters__c != null) {
            return cfg.Proximity_Meters__c;
        }
        return 250;
    }
}