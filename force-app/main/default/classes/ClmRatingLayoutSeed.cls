/**
 * Upserts and deploys the standard HCP/HCO CLM rating layouts used by field reps.
 * Self-contained so it can deploy to orgs where ClmRatingLayoutService is still a stub.
 */
public without sharing class ClmRatingLayoutSeed {
    public static final String HCP_LAYOUT_NAME = 'Standard HCP Ratings';
    public static final String HCO_LAYOUT_NAME = 'Standard HCO Ratings';

    public class SeedResult {
        @AuraEnabled public Id hcpLayoutId;
        @AuraEnabled public Id hcoLayoutId;
        @AuraEnabled public String message;
    }

    public static SeedResult seedAndDeploy() {
        SeedResult result = new SeedResult();
        result.hcpLayoutId = upsertDeployedLayout(HCP_LAYOUT_NAME, standardLayoutJson('HCP'));
        result.hcoLayoutId = upsertDeployedLayout(HCO_LAYOUT_NAME, standardLayoutJson('HCO'));
        result.message =
            'Deployed HCP layout ' +
            result.hcpLayoutId +
            ' and HCO layout ' +
            result.hcoLayoutId +
            '.';
        return result;
    }

    public static String standardLayoutJson(String accountVariant) {
        String variant = String.isBlank(accountVariant) ? 'HCP' : accountVariant;
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 2,
                'accountVariant' => variant,
                'sections' => new Map<String, Object>{
                    'account' => new List<Object>(),
                    'accountTerritory' => new List<Object>{
                        fieldDef(
                            'Account_Territory_Fields__c',
                            'HCP_Classification__c',
                            'Classification',
                            'picklist',
                            10,
                            classificationOptions()
                        ),
                        fieldDef(
                            'Account_Territory_Fields__c',
                            'Is_Speaker__c',
                            'Is Speaker',
                            'toggle',
                            20,
                            null
                        ),
                        fieldDef('Account_Territory_Fields__c', 'Is_KOL__c', 'Is KOL', 'toggle', 30, null),
                        fieldDef(
                            'Account_Territory_Fields__c',
                            'KOL_In_What__c',
                            'KOL Type',
                            'picklist',
                            40,
                            kolTypeOptions()
                        )
                    },
                    'accountTerritoryProduct' => new List<Object>{
                        fieldDef(
                            'Account_Territory_Product_Fields__c',
                            'Potential__c',
                            'Potentiality',
                            'numberDonut',
                            10,
                            null
                        ),
                        fieldDef(
                            'Account_Territory_Product_Fields__c',
                            'Penetration__c',
                            'Penetration',
                            'numberDonut',
                            20,
                            null
                        )
                    }
                }
            }
        );
    }

    private static Id upsertDeployedLayout(String layoutName, String fieldsJson) {
        List<CLM_Rating_Layout__c> existing = [
            SELECT Id
            FROM CLM_Rating_Layout__c
            WHERE Name = :layoutName
            LIMIT 1
        ];

        CLM_Rating_Layout__c record = existing.isEmpty()
            ? new CLM_Rating_Layout__c(Name = layoutName)
            : existing[0];
        record.Status__c = 'Deployed';
        record.Fields_JSON__c = fieldsJson;
        record.Account_Count__c = 0;
        record.Territory_Count__c = 4;
        record.Product_Count__c = 2;
        record.Tools_Count__c = 0;
        record.Team_Count__c = 0;
        upsert record;

        demoteOtherDeployedLayouts(record.Id, fieldsJson);
        return record.Id;
    }

    private static void demoteOtherDeployedLayouts(Id keepLayoutId, String keepFieldsJson) {
        String keepVariant = resolveVariant(keepFieldsJson);
        List<CLM_Rating_Layout__c> toDemote = new List<CLM_Rating_Layout__c>();
        for (CLM_Rating_Layout__c layout : [
            SELECT Id, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Status__c = 'Deployed' AND Id != :keepLayoutId
        ]) {
            if (resolveVariant(layout.Fields_JSON__c) == keepVariant) {
                layout.Status__c = 'Draft';
                toDemote.add(layout);
            }
        }
        if (!toDemote.isEmpty()) {
            update toDemote;
        }
    }

    public static String resolveVariant(String fieldsJson) {
        if (String.isBlank(fieldsJson)) {
            return 'HCP';
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            Object variant = parsed.get('accountVariant');
            if (variant != null && String.isNotBlank(String.valueOf(variant))) {
                return String.valueOf(variant);
            }
        } catch (Exception ex) {
            // fall through
        }
        return 'HCP';
    }

    private static Map<String, Object> fieldDef(
        String objectApiName,
        String fieldApiName,
        String label,
        String widget,
        Integer orderNum,
        List<Object> options
    ) {
        Map<String, Object> field = new Map<String, Object>{
            'objectApiName' => objectApiName,
            'fieldApiName' => fieldApiName,
            'label' => label,
            'widget' => widget,
            'order' => orderNum,
            'readOnly' => false
        };
        if (options != null) {
            field.put('options', options);
        }
        return field;
    }

    private static List<Object> classificationOptions() {
        List<Object> options = new List<Object>();
        for (String value : new List<String>{ 'A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3' }) {
            options.add(new Map<String, Object>{ 'label' => value, 'value' => value });
        }
        return options;
    }

    private static List<Object> kolTypeOptions() {
        return new List<Object>{
            new Map<String, Object>{ 'label' => 'High Prescriber', 'value' => 'High Prescriber' },
            new Map<String, Object>{
                'label' => 'Key Scientific Leader',
                'value' => 'Key Scientific Leader'
            }
        };
    }
}