@IsTest
private class PharmacySalesFieldSupportTest {
    @IsTest
    static void fieldHelpersAndQueries() {
        System.assertEquals(false, PharmacySalesFieldSupport.hasField(null, 'Name'));
        System.assertEquals(false, PharmacySalesFieldSupport.hasField(Account.SObjectType, null));
        PharmacySalesFieldSupport.hasField(Account.SObjectType, 'Name');
        PharmacySalesFieldSupport.hasField(Employee_Time_Card__c.SObjectType, 'Visit_Target__c');
        PharmacySalesFieldSupport.selectClause(Account.SObjectType, null);
        System.assert(PharmacySalesFieldSupport.selectClause(Account.SObjectType, new List<String>{ 'Name', 'Missing__c' }).contains('Id'));

        Account pharmacy = new Account(Name = 'Pharmacy Support');
        insert pharmacy;
        Product2 product = new Product2(Name = 'Support Product', IsActive = true);
        insert product;
        System.assertEquals('Pharmacy Support', PharmacySalesFieldSupport.getFieldValue(pharmacy, 'Name'));
        System.assertEquals(null, PharmacySalesFieldSupport.getFieldValue(null, 'Name'));
        PharmacySalesFieldSupport.putFieldValue(null, 'Name', 'x');
        PharmacySalesFieldSupport.putFieldValue(pharmacy, 'Name', 'Renamed');
        PharmacySalesFieldSupport.putFieldValue(pharmacy, 'Missing__c', 'x');

        PharmacySalesFieldSupport.loadStandardPrices(new Set<Id>());
        PharmacySalesFieldSupport.loadStandardPrices(new Set<Id>{ product.Id });

        Brick__c brick = new Brick__c(Name = 'Coverage Brick', Brick_Code__c = 'CVB1', Is_Active__c = true);
        insert brick;

        PharmacySalesFieldSupport.BrickContext context = PharmacySalesFieldSupport.loadBrickContext();
        context.brickNames.put(brick.Id, 'Coverage Brick');
        context.pharmacyToBrick.put(pharmacy.Id, brick.Id);

        Pharmacy_Sales_Withdrawal__c withBrick = new Pharmacy_Sales_Withdrawal__c(
            Quantity_Withdrawn__c = 2,
            Unit_Price__c = 5,
            Product2_Id__c = product.Id,
            Pharmacy_Account__c = pharmacy.Id,
            Brick__c = brick.Id
        );
        PharmacySalesFieldSupport.resolveBrickId(withBrick, context);
        PharmacySalesFieldSupport.resolveBrickName(withBrick, context);
        PharmacySalesFieldSupport.resolveRevenue(withBrick, new Map<Id, Decimal>{ product.Id => 9 });
        PharmacySalesFieldSupport.resolveUnitPrice(withBrick, new Map<Id, Decimal>{ product.Id => 9 });

        Pharmacy_Sales_Withdrawal__c noBrick = new Pharmacy_Sales_Withdrawal__c(
            Quantity_Withdrawn__c = 2,
            Product2_Id__c = product.Id,
            Pharmacy_Account__c = pharmacy.Id
        );
        PharmacySalesFieldSupport.resolveBrickId(noBrick, context);
        PharmacySalesFieldSupport.resolveBrickName(noBrick, context);
        PharmacySalesFieldSupport.resolveRevenue(noBrick, new Map<Id, Decimal>{ product.Id => 4 });
        PharmacySalesFieldSupport.resolveUnitPrice(noBrick, new Map<Id, Decimal>{ product.Id => 4 });
        PharmacySalesFieldSupport.resolveRevenue(noBrick, new Map<Id, Decimal>());
        PharmacySalesFieldSupport.resolveUnitPrice(noBrick, new Map<Id, Decimal>());

        Date month = Date.today().toStartOfMonth();
        Test.startTest();
        PharmacySalesFieldSupport.queryWithdrawals(month, month, 'All', null, new List<Id>(), context);
        PharmacySalesFieldSupport.queryWithdrawals(month, month, 'Ebda', brick.Id, new List<Id>{ pharmacy.Id }, context);
        PharmacySalesFieldSupport.queryWithdrawals(month.addYears(-20), month.addYears(-19), 'All', null, null, context);
        Test.stopTest();
    }
}
