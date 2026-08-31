@IsTest
private class ProductCatalogAdminControllerTest {

    @IsTest
    static void getProductCatalogTree_groupsByFamily() {
        insert new Product2(
            Name = 'Empacoza Test',
            ProductCode = 'ZETA-TEST-1',
            External_ID__c = 'ZETA_TEST_1',
            Primary_Brand__c = 'Empacoza',
            Product_Image_URL__c = 'https://example.com/empacoza-test.png',
            IsActive = true
        );
        insert new Product2(
            Name = 'Dozova Test',
            ProductCode = 'ZETA-TEST-2',
            External_ID__c = 'ZETA_TEST_2',
            Primary_Brand__c = 'Dozova',
            IsActive = true
        );

        Test.startTest();
        List<ProductCatalogAdminController.ProductTreeNode> tree =
            ProductCatalogAdminController.getProductCatalogTree();
        Test.stopTest();

        System.assert(tree.size() >= 2);

        Boolean foundImageUrl = false;
        for (ProductCatalogAdminController.ProductTreeNode familyNode : tree) {
            for (ProductCatalogAdminController.ProductTreeNode productNode : familyNode.children) {
                if (productNode.label == 'Empacoza Test') {
                    System.assertEquals('https://example.com/empacoza-test.png', productNode.imageUrl);
                    foundImageUrl = true;
                }
            }
        }
        System.assertEquals(true, foundImageUrl, 'Expected product image URL in catalog tree');
    }

    @IsTest
    static void saveProductTerritoryAlignments_createsAndRemovesRows() {
        Product2 product = new Product2(
            Name = 'Alignment Test Product',
            ProductCode = 'ZETA-ALIGN',
            External_ID__c = 'ZETA_ALIGN_TEST',
            Primary_Brand__c = 'Empacoza',
            IsActive = true
        );
        insert product;

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }
        Territory2Model model = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        Territory2 territory = new Territory2(
            Name = 'Product Align Test Territory',
            DeveloperName = 'Product_Align_Test',
            Territory2ModelId = model.Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_PRODUCT_ALIGN_TEST'
        );
        insert territory;

        Test.startTest();
        ProductCatalogAdminController.saveProductTerritoryAlignments(
            product.Id,
            new List<Id>{ territory.Id }
        );
        Integer cleared = ProductCatalogAdminController.saveProductTerritoryAlignments(
            product.Id,
            new List<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, cleared);
    }

    @IsTest
    static void getTerritoryTreeForProduct_andNullSave() {
        Product2 product = new Product2(
            Name = 'Tree Test Product',
            ProductCode = 'ZETA-TREE',
            External_ID__c = 'ZETA_TREE_TEST',
            Primary_Brand__c = 'Empacoza',
            IsActive = true
        );
        insert product;

        Test.startTest();
        List<ProductCatalogAdminController.TerritoryTreeNode> tree =
            ProductCatalogAdminController.getTerritoryTreeForProduct(product.Id);
        Boolean threw = false;
        try {
            ProductCatalogAdminController.saveProductTerritoryAlignments(null, new List<Id>());
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertNotEquals(null, tree);
        System.assertEquals(true, threw, 'Null product should be rejected');
    }
}