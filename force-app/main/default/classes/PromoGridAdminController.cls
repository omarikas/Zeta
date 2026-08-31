public with sharing class PromoGridAdminController {
    private static final String F_TERRITORY_TYPE = 'Territory_Type__c';
    private static final String TYPE_LINE = 'Line';
    private static final String TYPE_POSITION = 'Position';
    private static final String TYPE_BU = 'Business_Unit';
    private static final String TYPE_OTHER = 'Other';

    @TestVisible
    private static Boolean skipLineTerritoryValidation = false;

    public class LineRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String level;
        @AuraEnabled public Boolean isLine;
        @AuraEnabled public Boolean isVacant;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public List<LineRow> children;
        @AuraEnabled public Decimal weightTotal;
        @AuraEnabled public Integer productWeightCount;
        @AuraEnabled public Integer specialtyFocusCount;
        @AuraEnabled public Integer classTargetingCount;
    }

    public class ProductWeightRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal weightPercentage;
    }

    public class SpecialtyFocusRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String specialty;
        @AuraEnabled public String specialtyLabel;
        @AuraEnabled public Decimal listPercentage;
    }

    public class ClassTargetingRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String classCode;
        @AuraEnabled public Decimal listPercentage;
        @AuraEnabled public Decimal targetMonthlyVisits;
    }

    public class PromoGridDto {
        @AuraEnabled public Id lineTerritoryId;
        @AuraEnabled public String lineName;
        @AuraEnabled public List<ProductWeightRow> productWeights;
        @AuraEnabled public List<SpecialtyFocusRow> specialtyFocus;
        @AuraEnabled public List<ClassTargetingRow> classTargeting;
        @AuraEnabled public Decimal productWeightTotal;
        @AuraEnabled public Decimal specialtyFocusTotal;
        @AuraEnabled public Decimal classTargetingTotal;
    }

    public class PicklistOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class ProductOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class ProductWeightInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public Id product2Id;
        @AuraEnabled public Decimal weightPercentage;
    }

    public class SpecialtyFocusInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public String specialty;
        @AuraEnabled public Decimal listPercentage;
    }

    public class ClassTargetingInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public String classCode;
        @AuraEnabled public Decimal listPercentage;
        @AuraEnabled public Decimal targetMonthlyVisits;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineRow> getLineTerritories() {
        List<Territory2> territories = queryTerritoriesForTree();
        if (territories.isEmpty()) {
            return new List<LineRow>();
        }

        Set<Id> territoryIds = new Map<Id, Territory2>(territories).keySet();
        Set<Id> vacantTerritoryIds = loadVacantTerritoryIds(territoryIds);

        Set<String> lineKeys = new Set<String>();
        for (Territory2 territory : territories) {
            if (isLineTerritory(territory)) {
                lineKeys.add(String.valueOf(territory.Id));
            }
        }

        Map<String, Decimal> weightTotals = new Map<String, Decimal>();
        Map<String, Integer> weightCounts = new Map<String, Integer>();
        if (!lineKeys.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Territory2_Id__c territoryKey, SUM(Weight_Percentage__c) weightSum, COUNT(Id) recordCount
                FROM Promo_Grid_Product_Weight__c
                WHERE Territory2_Id__c IN :lineKeys
                WITH SYSTEM_MODE
                GROUP BY Territory2_Id__c
            ]) {
                String key = (String) ar.get('territoryKey');
                weightTotals.put(key, (Decimal) ar.get('weightSum'));
                weightCounts.put(key, (Integer) ar.get('recordCount'));
            }
        }

        Map<String, Integer> specialtyCounts = lineKeys.isEmpty()
            ? new Map<String, Integer>()
            : countByTerritory('Promo_Grid_Specialty_Focus__c', lineKeys);
        Map<String, Integer> classCounts = lineKeys.isEmpty()
            ? new Map<String, Integer>()
            : countByTerritory('Promo_Grid_Class_Targeting__c', lineKeys);

        Map<Id, List<LineRow>> childrenByParent = new Map<Id, List<LineRow>>();
        Map<Id, LineRow> nodesById = new Map<Id, LineRow>();

        for (Territory2 territory : territories) {
            String key = String.valueOf(territory.Id);
            Boolean isLine = isLineTerritory(territory);
            LineRow row = new LineRow();
            row.id = territory.Id;
            row.name = territory.Name;
            row.externalId = (String) territory.get('External_ID__c');
            row.parentId = territory.ParentTerritory2Id;
            row.level = resolveNodeLevel(row.externalId, territory);
            row.isLine = isLine;
            row.isVacant = vacantTerritoryIds.contains(territory.Id);
            row.hasChildren = false;
            row.children = new List<LineRow>();
            row.weightTotal = isLine && weightTotals.containsKey(key) ? weightTotals.get(key) : 0;
            row.productWeightCount = isLine && weightCounts.containsKey(key) ? weightCounts.get(key) : 0;
            row.specialtyFocusCount = isLine && specialtyCounts.containsKey(key)
                ? specialtyCounts.get(key)
                : 0;
            row.classTargetingCount = isLine && classCounts.containsKey(key)
                ? classCounts.get(key)
                : 0;
            nodesById.put(territory.Id, row);

            if (territory.ParentTerritory2Id != null) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<LineRow>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(row);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                LineRow parent = nodesById.get(parentId);
                parent.children = childrenByParent.get(parentId);
                parent.hasChildren = !parent.children.isEmpty();
            }
        }

        List<LineRow> roots = new List<LineRow>();
        for (Territory2 territory : territories) {
            LineRow node = nodesById.get(territory.Id);
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                roots.add(node);
            }
        }

        roots.sort(new LineRowNameComparator());
        sortChildrenRecursively(roots);
        return roots;
    }

    @AuraEnabled(cacheable=true)
    public static PromoGridDto getPromoGrid(Id lineTerritoryId) {
        if (lineTerritoryId == null) {
            throw new AuraHandledException('Line territory Id is required.');
        }

        Territory2 line = queryTerritoryById(lineTerritoryId);
        if (!skipLineTerritoryValidation && (line == null || !isLineTerritory(line))) {
            throw new AuraHandledException('Selected territory is not a Line territory.');
        }

        String territoryKey = String.valueOf(lineTerritoryId);
        PromoGridDto dto = new PromoGridDto();
        dto.lineTerritoryId = lineTerritoryId;
        dto.lineName = line != null ? line.Name : 'Line Territory';
        dto.productWeights = new List<ProductWeightRow>();
        dto.specialtyFocus = new List<SpecialtyFocusRow>();
        dto.classTargeting = new List<ClassTargetingRow>();
        dto.productWeightTotal = 0;
        dto.specialtyFocusTotal = 0;
        dto.classTargetingTotal = 0;

        Map<String, String> specialtyLabels = picklistLabelMap(
            Promo_Grid_Specialty_Focus__c.Specialty__c.getDescribe()
        );

        for (Promo_Grid_Product_Weight__c record : [
            SELECT Id, Product2__c, Product2__r.Name, Weight_Percentage__c
            FROM Promo_Grid_Product_Weight__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
            ORDER BY Product2__r.Name
        ]) {
            ProductWeightRow row = new ProductWeightRow();
            row.id = record.Id;
            row.product2Id = record.Product2__c;
            row.productName = record.Product2__r != null ? record.Product2__r.Name : null;
            row.weightPercentage = record.Weight_Percentage__c;
            dto.productWeights.add(row);
            if (record.Weight_Percentage__c != null) {
                dto.productWeightTotal += record.Weight_Percentage__c;
            }
        }

        for (Promo_Grid_Specialty_Focus__c record : [
            SELECT Id, Specialty__c, List_Percentage__c
            FROM Promo_Grid_Specialty_Focus__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
            ORDER BY Specialty__c
        ]) {
            SpecialtyFocusRow row = new SpecialtyFocusRow();
            row.id = record.Id;
            row.specialty = record.Specialty__c;
            row.specialtyLabel = specialtyLabels.containsKey(record.Specialty__c)
                ? specialtyLabels.get(record.Specialty__c)
                : record.Specialty__c;
            row.listPercentage = record.List_Percentage__c;
            dto.specialtyFocus.add(row);
            if (record.List_Percentage__c != null) {
                dto.specialtyFocusTotal += record.List_Percentage__c;
            }
        }

        for (Promo_Grid_Class_Targeting__c record : [
            SELECT Id, Class__c, List_Percentage__c, Target_Monthly_Visits__c
            FROM Promo_Grid_Class_Targeting__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
            ORDER BY Class__c
        ]) {
            ClassTargetingRow row = new ClassTargetingRow();
            row.id = record.Id;
            row.classCode = record.Class__c;
            row.listPercentage = record.List_Percentage__c;
            row.targetMonthlyVisits = record.Target_Monthly_Visits__c;
            dto.classTargeting.add(row);
            if (record.List_Percentage__c != null) {
                dto.classTargetingTotal += record.List_Percentage__c;
            }
        }

        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getSpecialtyOptions() {
        return toPicklistOptions(Promo_Grid_Specialty_Focus__c.Specialty__c.getDescribe());
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getClassOptions() {
        return toPicklistOptions(Promo_Grid_Class_Targeting__c.Class__c.getDescribe());
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductOption> searchProducts(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '%' : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<ProductOption> options = new List<ProductOption>();
        for (Product2 product : [
            SELECT Id, Name
            FROM Product2
            WHERE IsActive = TRUE AND Name LIKE :term
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 25
        ]) {
            ProductOption option = new ProductOption();
            option.value = product.Id;
            option.label = product.Name;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static Id upsertProductWeight(ProductWeightInput input) {
        if (input == null || input.territory2Id == null || input.product2Id == null) {
            throw new AuraHandledException('Territory and Product are required.');
        }
        if (input.weightPercentage == null) {
            throw new AuraHandledException('Weight percentage is required.');
        }
        assertLineTerritory(input.territory2Id);

        String territoryKey = String.valueOf(input.territory2Id);
        Promo_Grid_Product_Weight__c record = input.recordId == null
            ? new Promo_Grid_Product_Weight__c()
            : [
                SELECT Id, Territory2_Id__c, Product2__c, Weight_Percentage__c, Unique_Key__c
                FROM Promo_Grid_Product_Weight__c
                WHERE Id = :input.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

        record.Territory2_Id__c = territoryKey;
        record.Product2__c = input.product2Id;
        record.Weight_Percentage__c = input.weightPercentage;
        record.Unique_Key__c = territoryKey + ':' + String.valueOf(input.product2Id);

        if (input.recordId == null) {
            insert as system record;
        } else {
            update as system record;
        }
        return record.Id;
    }

    @AuraEnabled
    public static void deleteProductWeight(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        delete as system [
            SELECT Id
            FROM Promo_Grid_Product_Weight__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
        ];
    }

    @AuraEnabled
    public static Id upsertSpecialtyFocus(SpecialtyFocusInput input) {
        if (input == null || input.territory2Id == null || String.isBlank(input.specialty)) {
            throw new AuraHandledException('Territory and Specialty are required.');
        }
        if (input.listPercentage == null) {
            throw new AuraHandledException('List percentage is required.');
        }
        assertLineTerritory(input.territory2Id);

        String territoryKey = String.valueOf(input.territory2Id);
        Promo_Grid_Specialty_Focus__c record = input.recordId == null
            ? new Promo_Grid_Specialty_Focus__c()
            : [
                SELECT Id, Territory2_Id__c, Specialty__c, List_Percentage__c, Unique_Key__c
                FROM Promo_Grid_Specialty_Focus__c
                WHERE Id = :input.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

        record.Territory2_Id__c = territoryKey;
        record.Specialty__c = input.specialty;
        record.List_Percentage__c = input.listPercentage;
        record.Unique_Key__c = buildSpecialtyKey(territoryKey, input.specialty);

        if (input.recordId == null) {
            insert as system record;
        } else {
            update as system record;
        }
        return record.Id;
    }

    @AuraEnabled
    public static void deleteSpecialtyFocus(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        delete as system [
            SELECT Id
            FROM Promo_Grid_Specialty_Focus__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
        ];
    }

    @AuraEnabled
    public static Id upsertClassTargeting(ClassTargetingInput input) {
        if (input == null || input.territory2Id == null || String.isBlank(input.classCode)) {
            throw new AuraHandledException('Territory and Class are required.');
        }
        if (input.listPercentage == null) {
            throw new AuraHandledException('List percentage is required.');
        }
        assertLineTerritory(input.territory2Id);

        String territoryKey = String.valueOf(input.territory2Id);
        Promo_Grid_Class_Targeting__c record = input.recordId == null
            ? new Promo_Grid_Class_Targeting__c()
            : [
                SELECT Id,
                    Territory2_Id__c,
                    Class__c,
                    List_Percentage__c,
                    Target_Monthly_Visits__c,
                    Unique_Key__c
                FROM Promo_Grid_Class_Targeting__c
                WHERE Id = :input.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

        record.Territory2_Id__c = territoryKey;
        record.Class__c = input.classCode;
        record.List_Percentage__c = input.listPercentage;
        record.Target_Monthly_Visits__c = input.targetMonthlyVisits;
        record.Unique_Key__c = territoryKey + ':' + input.classCode;

        if (input.recordId == null) {
            insert as system record;
        } else {
            update as system record;
        }
        return record.Id;
    }

    @AuraEnabled
    public static void deleteClassTargeting(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        delete as system [
            SELECT Id
            FROM Promo_Grid_Class_Targeting__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
        ];
    }

    private static List<Territory2> queryTerritoriesForTree() {
        return Database.query(buildTerritorySelectSoql(null) + ' ORDER BY Name LIMIT 5000');
    }

    private static Territory2 queryTerritoryById(Id territoryId) {
        if (territoryId == null) {
            return null;
        }
        List<Territory2> rows = Database.query(buildTerritorySelectSoql(territoryId));
        return rows.isEmpty() ? null : rows[0];
    }

    private static String buildTerritorySelectSoql(Id territoryId) {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Territory2.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'Name', 'ParentTerritory2Id' };
        if (fields.containsKey('External_ID__c')) {
            selectFields.add('External_ID__c');
        }
        if (fields.containsKey(F_TERRITORY_TYPE)) {
            selectFields.add(F_TERRITORY_TYPE);
        }
        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Territory2';
        if (territoryId != null) {
            soql += ' WHERE Id = :territoryId';
        }
        soql += ' WITH SYSTEM_MODE';
        if (territoryId != null) {
            soql += ' LIMIT 1';
        }
        return soql;
    }

    private static Set<Id> loadVacantTerritoryIds(Set<Id> territoryIds) {
        Set<Id> vacantIds = new Set<Id>(territoryIds);
        if (territoryIds == null || territoryIds.isEmpty()) {
            return vacantIds;
        }
        for (UserTerritory2Association association : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
        ]) {
            vacantIds.remove(association.Territory2Id);
        }
        return vacantIds;
    }

    private static String resolveNodeLevel(String externalId, Territory2 territory) {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Territory2.fields.getMap();
        if (fields.containsKey(F_TERRITORY_TYPE)) {
            String territoryType = (String) territory.get(F_TERRITORY_TYPE);
            if (String.isNotBlank(territoryType)) {
                if (territoryType == 'Head_Office') {
                    return 'Head Office';
                }
                if (territoryType == TYPE_BU) {
                    return 'Business Unit';
                }
                if (territoryType == TYPE_LINE) {
                    return 'Line';
                }
                if (territoryType == 'District') {
                    return 'District';
                }
                if (territoryType == TYPE_POSITION) {
                    return 'Position';
                }
            }
        }
        return resolveLevelFromExternalId(externalId);
    }

    private static void sortChildrenRecursively(List<LineRow> nodes) {
        if (nodes == null) {
            return;
        }
        nodes.sort(new LineRowNameComparator());
        for (LineRow node : nodes) {
            if (node.children != null && !node.children.isEmpty()) {
                sortChildrenRecursively(node.children);
            }
        }
    }

    private class LineRowNameComparator implements Comparator<LineRow> {
        public Integer compare(LineRow a, LineRow b) {
            String left = a != null && a.name != null ? a.name : '';
            String right = b != null && b.name != null ? b.name : '';
            return left.compareTo(right);
        }
    }

    private static Boolean isLineTerritory(Territory2 territory) {
        if (territory == null) {
            return false;
        }
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Territory2.fields.getMap();
        if (fields.containsKey(F_TERRITORY_TYPE)) {
            String typeValue = (String) territory.get(F_TERRITORY_TYPE);
            if (String.isNotBlank(typeValue)) {
                return typeValue == TYPE_LINE;
            }
        }
        String externalId = fields.containsKey('External_ID__c')
            ? (String) territory.get('External_ID__c')
            : null;
        return resolveLevelFromExternalId(externalId) == 'Line';
    }

    private static void assertLineTerritory(Id territoryId) {
        if (skipLineTerritoryValidation) {
            return;
        }
        Territory2 territory = queryTerritoryById(territoryId);
        if (!isLineTerritory(territory)) {
            throw new AuraHandledException('Promo Grid rows can only be saved against Line territories.');
        }
    }

    @TestVisible
    private static String resolveLevelFromExternalId(String externalId) {
        if (String.isBlank(externalId)) {
            return 'Unknown';
        }
        if (externalId == 'TERR_HEAD_OFFICE') {
            return 'Head Office';
        }
        if (externalId.contains('_MR_')) {
            return 'MR';
        }
        if (externalId.contains('_DM_')) {
            return 'District';
        }
        return 'Line';
    }

    private static Map<String, Integer> countByTerritory(String objectApiName, Set<String> territoryKeys) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String soql =
            'SELECT Territory2_Id__c territoryKey, COUNT(Id) recordCount FROM ' +
            objectApiName +
            ' WHERE Territory2_Id__c IN :territoryKeys WITH SYSTEM_MODE GROUP BY Territory2_Id__c';
        for (AggregateResult ar : Database.query(soql)) {
            counts.put((String) ar.get('territoryKey'), (Integer) ar.get('recordCount'));
        }
        return counts;
    }

    private static List<PicklistOption> toPicklistOptions(Schema.DescribeFieldResult fieldDescribe) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.value = entry.getValue();
            option.label = entry.getLabel();
            options.add(option);
        }
        return options;
    }

    private static Map<String, String> picklistLabelMap(Schema.DescribeFieldResult fieldDescribe) {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }

    private static String buildSpecialtyKey(String territoryKey, String specialty) {
        String raw = territoryKey + ':' + specialty;
        return raw.length() > 80 ? raw.left(80) : raw;
    }

    @TestVisible
    private static String mapLevelToTerritoryType(String level) {
        if (level == 'Line') {
            return TYPE_LINE;
        }
        if (level == 'MR') {
            return TYPE_POSITION;
        }
        if (level == 'Head Office') {
            return TYPE_BU;
        }
        return TYPE_OTHER;
    }
}