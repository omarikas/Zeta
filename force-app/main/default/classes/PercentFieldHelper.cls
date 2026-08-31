public with sharing class PercentFieldHelper {
    /**
     * Converts a Salesforce Percent field value to a 0–100 display scale.
     * Apex returns percent fields as a 0–1 ratio; legacy Reach_Percent__c values
     * may still be double-scaled from an old formula that multiplied by 100.
     */
    public static Decimal toDisplayScale(Decimal percentFieldValue) {
        if (percentFieldValue == null) {
            return null;
        }
        if (percentFieldValue > 100) {
            return percentFieldValue / 100;
        }
        if (percentFieldValue <= 1) {
            return percentFieldValue * 100;
        }
        return percentFieldValue;
    }
}