/**
 * Production-safe slim ClmAdminController for Rating Layouts admin UI.
 * Keeps stub method signatures expected by other CLM admin LWCs in Zeta Pharma.
 */
public with sharing class ClmAdminController {
    public class RatingLayoutRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String fieldsJson;
        @AuraEnabled public Integer accountCount;
        @AuraEnabled public Integer territoryCount;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Integer toolsCount;
        @AuraEnabled public Integer teamCount;
    }

    public class RatingFieldCatalogEntry {
        @AuraEnabled public String sectionKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public String widget;
        @AuraEnabled public Boolean readOnly;
        @AuraEnabled public List<Map<String, String>> options;
    }

    @AuraEnabled(cacheable=true)
    public static List<RatingLayoutRow> getRatingLayouts() {
        List<RatingLayoutRow> rows = new List<RatingLayoutRow>();
        for (CLM_Rating_Layout__c layout : [
            SELECT Id, Name, Status__c, Fields_JSON__c, Account_Count__c, Territory_Count__c,
                   Product_Count__c, Tools_Count__c, Team_Count__c
            FROM CLM_Rating_Layout__c
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            rows.add(mapRatingLayout(layout));
        }
        return rows;
    }

    @AuraEnabled
    public static RatingLayoutRow saveRatingLayout(RatingLayoutRow layout) {
        if (layout == null || String.isBlank(layout.name)) {
            throw new AuraHandledException('Layout name is required.');
        }
        String fieldsJson = String.isBlank(layout.fieldsJson)
            ? ClmRatingLayoutSeed.standardLayoutJson('HCP')
            : layout.fieldsJson;
        CLM_Rating_Layout__c record = new CLM_Rating_Layout__c(
            Id = layout.id,
            Name = layout.name,
            Status__c = String.isBlank(layout.status) ? 'Draft' : layout.status,
            Fields_JSON__c = fieldsJson,
            Account_Count__c = 0,
            Territory_Count__c = 4,
            Product_Count__c = 2,
            Tools_Count__c = layout.toolsCount != null ? layout.toolsCount : 0,
            Team_Count__c = layout.teamCount != null ? layout.teamCount : 0
        );
        upsert as user record;
        return mapRatingLayout([
            SELECT Id, Name, Status__c, Fields_JSON__c, Account_Count__c, Territory_Count__c,
                   Product_Count__c, Tools_Count__c, Team_Count__c
            FROM CLM_Rating_Layout__c
            WHERE Id = :record.Id
            WITH USER_MODE
            LIMIT 1
        ]);
    }

    @AuraEnabled(cacheable=true)
    public static List<RatingFieldCatalogEntry> getRatingFieldCatalog() {
        List<RatingFieldCatalogEntry> rows = new List<RatingFieldCatalogEntry>();
        rows.add(catalog('accountTerritory', 'Account_Territory_Fields__c', 'HCP_Classification__c', 'Classification', 'PICKLIST', 'picklist', false));
        rows.add(catalog('accountTerritory', 'Account_Territory_Fields__c', 'Is_Speaker__c', 'Is Speaker', 'BOOLEAN', 'toggle', false));
        rows.add(catalog('accountTerritory', 'Account_Territory_Fields__c', 'Is_KOL__c', 'Is KOL', 'BOOLEAN', 'toggle', false));
        rows.add(catalog('accountTerritory', 'Account_Territory_Fields__c', 'KOL_In_What__c', 'KOL Type', 'STRING', 'picklist', false));
        rows.add(catalog('accountTerritoryProduct', 'Account_Territory_Product_Fields__c', 'Potential__c', 'Potentiality', 'DOUBLE', 'numberDonut', false));
        rows.add(catalog('accountTerritoryProduct', 'Account_Territory_Product_Fields__c', 'Penetration__c', 'Penetration', 'DOUBLE', 'numberDonut', false));
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static String getRatingLayoutPreviewSample() {
        return JSON.serialize(
            new Map<String, Object>{
                'HCP_Classification__c' => 'A1',
                'Is_Speaker__c' => false,
                'Is_KOL__c' => true,
                'KOL_In_What__c' => 'High Prescriber',
                'Potential__c' => 100,
                'Penetration__c' => 50
            }
        );
    }

    @AuraEnabled
    public static void deployRatingLayout(Id layoutId) {
        if (layoutId == null) {
            throw new AuraHandledException('Layout Id is required.');
        }
        CLM_Rating_Layout__c targetLayout = [
            SELECT Id, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Id = :layoutId
            WITH USER_MODE
            LIMIT 1
        ];
        String targetVariant = ClmRatingLayoutSeed.resolveVariant(targetLayout.Fields_JSON__c);
        List<CLM_Rating_Layout__c> toDemote = new List<CLM_Rating_Layout__c>();
        for (CLM_Rating_Layout__c layout : [
            SELECT Id, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Status__c = 'Deployed' AND Id != :layoutId
            WITH USER_MODE
        ]) {
            if (ClmRatingLayoutSeed.resolveVariant(layout.Fields_JSON__c) == targetVariant) {
                layout.Status__c = 'Draft';
                toDemote.add(layout);
            }
        }
        if (!toDemote.isEmpty()) {
            update as user toDemote;
        }
        update as user new CLM_Rating_Layout__c(Id = layoutId, Status__c = 'Deployed');
    }

    @AuraEnabled
    public static List<Object> getPresentations(String statusFilter) {
        return new List<Object>();
    }
    @AuraEnabled
    public static Object createPresentationDraft(String fileName, String formatType, String base64Data, Integer pageCount) {
        return null;
    }
    @AuraEnabled
    public static List<Object> attachSlideImages(Id presentationId, List<Object> images) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> generateSequencesFromPageCount(Id presentationId, String fileName, Integer pageCount) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getSequences(Id presentationId) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> saveSequences(Id presentationId, List<Object> sequences) {
        return new List<Object>();
    }
    @AuraEnabled
    public static Object getPresentationDraft(Id presentationId) {
        return null;
    }
    @AuraEnabled
    public static Object finalizePresentation(
        Id presentationId,
        String name,
        String status,
        String formatType,
        Id productId,
        String products,
        Date startDate,
        Date endDate,
        String playerGesture,
        String pinchZoom,
        String doubleTapZoom,
        String tags,
        String publicContentUrl,
        Boolean allowEmail,
        String territoryIdsJson,
        Boolean allowUnaligned
    ) {
        return null;
    }
    @AuraEnabled
    public static void deactivatePresentation(Id presentationId) {
    }
    @AuraEnabled
    public static List<Object> getTerritories() {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getTerritoryProductAlignments(String productIdsJson) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Map<String, String>> getProductOptions() {
        return new List<Map<String, String>>();
    }

    private static RatingFieldCatalogEntry catalog(
        String sectionKey,
        String objectApiName,
        String fieldApiName,
        String label,
        String dataType,
        String widget,
        Boolean readOnly
    ) {
        RatingFieldCatalogEntry row = new RatingFieldCatalogEntry();
        row.sectionKey = sectionKey;
        row.objectApiName = objectApiName;
        row.fieldApiName = fieldApiName;
        row.label = label;
        row.dataType = dataType;
        row.widget = widget;
        row.readOnly = readOnly;
        row.options = new List<Map<String, String>>();
        return row;
    }

    private static RatingLayoutRow mapRatingLayout(CLM_Rating_Layout__c layout) {
        RatingLayoutRow row = new RatingLayoutRow();
        row.id = layout.Id;
        row.name = layout.Name;
        row.status = layout.Status__c;
        row.fieldsJson = layout.Fields_JSON__c;
        row.accountCount = layout.Account_Count__c == null ? 0 : Integer.valueOf(layout.Account_Count__c);
        row.territoryCount = layout.Territory_Count__c == null ? 0 : Integer.valueOf(layout.Territory_Count__c);
        row.productCount = layout.Product_Count__c == null ? 0 : Integer.valueOf(layout.Product_Count__c);
        row.toolsCount = layout.Tools_Count__c == null ? 0 : Integer.valueOf(layout.Tools_Count__c);
        row.teamCount = layout.Team_Count__c == null ? 0 : Integer.valueOf(layout.Team_Count__c);
        return row;
    }
}