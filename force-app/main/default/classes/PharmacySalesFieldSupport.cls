public with sharing class PharmacySalesFieldSupport {
    public class BrickContext {
        public Map<Id, Id> pharmacyToBrick = new Map<Id, Id>();
        public Map<Id, String> brickNames = new Map<Id, String>();
        public Set<Id> activePharmacyIds = new Set<Id>();
    }

    public static Boolean hasField(Schema.SObjectType sobjectType, String fieldApiName) {
        if (sobjectType == null || String.isBlank(fieldApiName)) {
            return false;
        }
        Schema.SObjectField fieldToken = sobjectType.getDescribe().fields.getMap()
            .get(fieldApiName.toLowerCase());
        return fieldToken != null && fieldToken.getDescribe().isAccessible();
    }

    public static BrickContext loadBrickContext() {
        BrickContext context = new BrickContext();
        for (Brick__c brick : [
            SELECT Id, Name
            FROM Brick__c
            WITH USER_MODE
            ORDER BY Name
        ]) {
            context.brickNames.put(brick.Id, brick.Name);
        }

        String membershipSoql = 'SELECT Brick__c, Pharmacy_Account__c FROM Brick_Pharmacy__c';
        if (hasField(Brick_Pharmacy__c.SObjectType, 'Is_Active__c')) {
            membershipSoql += ' WHERE Is_Active__c = TRUE';
        }
        membershipSoql += ' WITH USER_MODE';
        for (Brick_Pharmacy__c membership : Database.query(membershipSoql)) {
            context.pharmacyToBrick.put(membership.Pharmacy_Account__c, membership.Brick__c);
            context.activePharmacyIds.add(membership.Pharmacy_Account__c);
        }
        return context;
    }

    public static List<Pharmacy_Sales_Withdrawal__c> queryWithdrawals(
        Date startMonth,
        Date endMonth,
        String dataSource,
        Id brickId,
        List<Id> pharmacyIds,
        BrickContext brickContext
    ) {
        List<String> selectFields = new List<String>{
            'Id',
            'Data_Source__c',
            'Report_Month__c',
            'Pharmacy_Account__c',
            'Pharmacy_Account__r.Name',
            'Product2_Id__c',
            'Quantity_Withdrawn__c'
        };
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Brick__c')) {
            selectFields.add('Brick__c');
            selectFields.add('Brick__r.Name');
        }
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Unit_Price__c')) {
            selectFields.add('Unit_Price__c');
        }
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Revenue__c')) {
            selectFields.add('Revenue__c');
        }

        String soql = 'SELECT ' + String.join(selectFields, ', ') +
            ' FROM Pharmacy_Sales_Withdrawal__c' +
            ' WHERE Report_Month__c >= :startMonth AND Report_Month__c <= :endMonth';

        List<String> conditions = new List<String>();
        String dataSourceFilter = dataSource;
        Id brickIdFilter = brickId;
        List<Id> pharmacyIdsFilter = pharmacyIds;

        if (String.isNotBlank(dataSource) && dataSource != 'All') {
            conditions.add('Data_Source__c = :dataSourceFilter');
        }
        if (brickId != null && hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Brick__c')) {
            conditions.add('Brick__c = :brickIdFilter');
        }
        if (pharmacyIds != null && !pharmacyIds.isEmpty()) {
            conditions.add('Pharmacy_Account__c IN :pharmacyIdsFilter');
        }
        if (!conditions.isEmpty()) {
            soql += ' AND ' + String.join(conditions, ' AND ');
        }
        soql += ' WITH USER_MODE ORDER BY Report_Month__c DESC, Pharmacy_Account__r.Name';

        List<Pharmacy_Sales_Withdrawal__c> rows = Database.query(soql);
        if (brickId == null || hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Brick__c')) {
            return rows;
        }

        List<Pharmacy_Sales_Withdrawal__c> filtered = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            Id rowBrickId = resolveBrickId(row, brickContext);
            if (rowBrickId == brickId) {
                filtered.add(row);
            }
        }
        return filtered;
    }

    public static Id resolveBrickId(
        Pharmacy_Sales_Withdrawal__c row,
        BrickContext brickContext
    ) {
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Brick__c')) {
            Object brickValue = row.get('Brick__c');
            if (brickValue != null) {
                return (Id) brickValue;
            }
        }
        return brickContext.pharmacyToBrick.get(row.Pharmacy_Account__c);
    }

    public static String resolveBrickName(
        Pharmacy_Sales_Withdrawal__c row,
        BrickContext brickContext
    ) {
        Id brickId = resolveBrickId(row, brickContext);
        return brickId != null && brickContext.brickNames.containsKey(brickId)
            ? brickContext.brickNames.get(brickId)
            : '';
    }

    public static Decimal resolveRevenue(
        Pharmacy_Sales_Withdrawal__c row,
        Map<Id, Decimal> priceByProduct
    ) {
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Revenue__c')) {
            Object revenueValue = row.get('Revenue__c');
            if (revenueValue != null) {
                return (Decimal) revenueValue;
            }
        }
        Decimal quantity = row.Quantity_Withdrawn__c == null ? 0 : row.Quantity_Withdrawn__c;
        Decimal unitPrice = null;
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Unit_Price__c')) {
            Object unitPriceValue = row.get('Unit_Price__c');
            if (unitPriceValue != null) {
                unitPrice = (Decimal) unitPriceValue;
            }
        }
        if (unitPrice == null && String.isNotBlank(row.Product2_Id__c)) {
            unitPrice = priceByProduct.get((Id) row.Product2_Id__c);
        }
        return quantity * (unitPrice == null ? 0 : unitPrice);
    }

    public static Decimal resolveUnitPrice(
        Pharmacy_Sales_Withdrawal__c row,
        Map<Id, Decimal> priceByProduct
    ) {
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Unit_Price__c')) {
            Object unitPriceValue = row.get('Unit_Price__c');
            if (unitPriceValue != null) {
                return (Decimal) unitPriceValue;
            }
        }
        if (String.isNotBlank(row.Product2_Id__c)) {
            return priceByProduct.get((Id) row.Product2_Id__c);
        }
        return null;
    }

    public static Map<Id, Decimal> loadStandardPrices(Set<Id> productIds) {
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (productIds == null || productIds.isEmpty()) {
            return prices;
        }
        List<Pricebook2> pricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = TRUE
            WITH USER_MODE
            LIMIT 1
        ];
        if (pricebooks.isEmpty()) {
            return prices;
        }
        for (PricebookEntry entry : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebooks[0].Id
            AND Product2Id IN :productIds
            AND IsActive = TRUE
            WITH USER_MODE
        ]) {
            prices.put(entry.Product2Id, entry.UnitPrice);
        }
        return prices;
    }

    public static String selectClause(Schema.SObjectType sobjectType, List<String> fieldApiNames) {
        List<String> fields = new List<String>{ 'Id' };
        if (fieldApiNames != null) {
            for (String fieldApiName : fieldApiNames) {
                if (fieldApiName != 'Id' && hasField(sobjectType, fieldApiName)) {
                    fields.add(fieldApiName);
                }
            }
        }
        return String.join(fields, ', ');
    }

    public static Object getFieldValue(SObject record, String fieldApiName) {
        if (record == null || !hasField(record.getSObjectType(), fieldApiName)) {
            return null;
        }
        return record.get(fieldApiName);
    }

    public static void putFieldValue(SObject record, String fieldApiName, Object value) {
        if (record != null && hasField(record.getSObjectType(), fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }
}
