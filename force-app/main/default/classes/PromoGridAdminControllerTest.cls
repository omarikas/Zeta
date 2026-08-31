@IsTest
private class PromoGridAdminControllerTest {
    @TestSetup
    static void setup() {
        insert new Product2(
            Name = 'Promo Grid Test Product',
            IsActive = true,
            ProductCode = 'PG_TEST_PROD'
        );
    }

    @IsTest
    static void picklists_lines_and_productSearch_areAvailable() {
        Test.startTest();
        List<PromoGridAdminController.PicklistOption> specialties =
            PromoGridAdminController.getSpecialtyOptions();
        List<PromoGridAdminController.PicklistOption> classes =
            PromoGridAdminController.getClassOptions();
        List<PromoGridAdminController.ProductOption> products =
            PromoGridAdminController.searchProducts('Promo Grid');
        List<PromoGridAdminController.ProductOption> blankSearch =
            PromoGridAdminController.searchProducts('');
        List<PromoGridAdminController.LineRow> roots =
            PromoGridAdminController.getLineTerritories();
        Test.stopTest();

        System.assert(!specialties.isEmpty());
        System.assert(!classes.isEmpty());
        System.assert(!products.isEmpty());
        System.assertNotEquals(null, blankSearch);
        System.assertNotEquals(null, roots);
        for (PromoGridAdminController.LineRow root : roots) {
            assertTreeNodeShape(root);
        }
    }

    private static void assertTreeNodeShape(PromoGridAdminController.LineRow node) {
        System.assertNotEquals(null, node);
        System.assertNotEquals(null, node.id);
        System.assertNotEquals(null, node.name);
        System.assertNotEquals(null, node.isLine);
        System.assertNotEquals(null, node.isVacant);
        System.assertNotEquals(null, node.hasChildren);
        System.assertNotEquals(null, node.children);
        if (node.hasChildren == true) {
            System.assert(!node.children.isEmpty());
            for (PromoGridAdminController.LineRow child : node.children) {
                System.assertEquals(node.id, child.parentId);
                assertTreeNodeShape(child);
            }
        }
    }

    @IsTest
    static void mapLevelHelpers_coverBranches() {
        System.assertEquals('Line', PromoGridAdminController.mapLevelToTerritoryType('Line'));
        System.assertEquals('Position', PromoGridAdminController.mapLevelToTerritoryType('MR'));
        System.assertEquals('Other', PromoGridAdminController.mapLevelToTerritoryType('District'));
        System.assertEquals('Business_Unit', PromoGridAdminController.mapLevelToTerritoryType('Head Office'));
        System.assertEquals('Other', PromoGridAdminController.mapLevelToTerritoryType('Unknown'));
        System.assertEquals('Unknown', PromoGridAdminController.resolveLevelFromExternalId(null));
        System.assertEquals('Unknown', PromoGridAdminController.resolveLevelFromExternalId(''));
        System.assertEquals('Head Office', PromoGridAdminController.resolveLevelFromExternalId('TERR_HEAD_OFFICE'));
        System.assertEquals('MR', PromoGridAdminController.resolveLevelFromExternalId('TERR_GIT_DM_1_MR_1'));
        System.assertEquals('District', PromoGridAdminController.resolveLevelFromExternalId('TERR_GIT_DM_1'));
        System.assertEquals('Line', PromoGridAdminController.resolveLevelFromExternalId('TERR_GIT'));
    }

    @IsTest
    static void productWeight_specialty_class_crud_roundTrip() {
        PromoGridAdminController.skipLineTerritoryValidation = true;
        Id fakeLineId = fakeTerritoryId();
        Product2 product = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'PG_TEST_PROD'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Test.startTest();
        PromoGridAdminController.ProductWeightInput weightInput =
            new PromoGridAdminController.ProductWeightInput();
        weightInput.territory2Id = fakeLineId;
        weightInput.product2Id = product.Id;
        weightInput.weightPercentage = 40;
        Id weightId = PromoGridAdminController.upsertProductWeight(weightInput);

        weightInput.recordId = weightId;
        weightInput.weightPercentage = 55;
        PromoGridAdminController.upsertProductWeight(weightInput);

        List<PromoGridAdminController.PicklistOption> specialties =
            PromoGridAdminController.getSpecialtyOptions();
        PromoGridAdminController.SpecialtyFocusInput specialtyInput =
            new PromoGridAdminController.SpecialtyFocusInput();
        specialtyInput.territory2Id = fakeLineId;
        specialtyInput.specialty = specialties[0].value;
        specialtyInput.listPercentage = 25;
        Id specialtyId = PromoGridAdminController.upsertSpecialtyFocus(specialtyInput);
        specialtyInput.recordId = specialtyId;
        specialtyInput.listPercentage = 30;
        PromoGridAdminController.upsertSpecialtyFocus(specialtyInput);

        List<PromoGridAdminController.PicklistOption> classes =
            PromoGridAdminController.getClassOptions();
        PromoGridAdminController.ClassTargetingInput classInput =
            new PromoGridAdminController.ClassTargetingInput();
        classInput.territory2Id = fakeLineId;
        classInput.classCode = classes[0].value;
        classInput.listPercentage = 10;
        classInput.targetMonthlyVisits = 5;
        Id classId = PromoGridAdminController.upsertClassTargeting(classInput);
        classInput.recordId = classId;
        classInput.listPercentage = 15;
        classInput.targetMonthlyVisits = 8;
        PromoGridAdminController.upsertClassTargeting(classInput);

        PromoGridAdminController.PromoGridDto grid = PromoGridAdminController.getPromoGrid(fakeLineId);
        List<PromoGridAdminController.LineRow> roots = PromoGridAdminController.getLineTerritories();

        PromoGridAdminController.deleteClassTargeting(classId);
        PromoGridAdminController.deleteSpecialtyFocus(specialtyId);
        PromoGridAdminController.deleteProductWeight(weightId);
        Test.stopTest();

        System.assertEquals(1, grid.productWeights.size());
        System.assertEquals(55, grid.productWeightTotal);
        System.assertEquals(1, grid.specialtyFocus.size());
        System.assertEquals(30, grid.specialtyFocusTotal);
        System.assertEquals(1, grid.classTargeting.size());
        System.assertEquals(15, grid.classTargetingTotal);
        System.assertNotEquals(null, roots);
        for (PromoGridAdminController.LineRow root : roots) {
            System.assertNotEquals(null, root.isVacant);
            System.assertNotEquals(null, root.children);
        }
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Promo_Grid_Product_Weight__c
                WHERE Id = :weightId
                WITH SYSTEM_MODE
            ]
        );
    }

    @IsTest
    static void validation_paths_throwHandledExceptions() {
        Boolean caughtMissingWeight = false;
        try {
            PromoGridAdminController.upsertProductWeight(new PromoGridAdminController.ProductWeightInput());
        } catch (AuraHandledException e) {
            caughtMissingWeight = true;
        }
        System.assert(caughtMissingWeight);

        PromoGridAdminController.ProductWeightInput weightNoPct =
            new PromoGridAdminController.ProductWeightInput();
        weightNoPct.territory2Id = fakeTerritoryId();
        weightNoPct.product2Id = UserInfo.getUserId();
        Boolean caughtMissingPct = false;
        try {
            PromoGridAdminController.upsertProductWeight(weightNoPct);
        } catch (AuraHandledException e) {
            caughtMissingPct = true;
        }
        System.assert(caughtMissingPct);

        Boolean caughtMissingSpecialty = false;
        try {
            PromoGridAdminController.upsertSpecialtyFocus(new PromoGridAdminController.SpecialtyFocusInput());
        } catch (AuraHandledException e) {
            caughtMissingSpecialty = true;
        }
        System.assert(caughtMissingSpecialty);

        PromoGridAdminController.SpecialtyFocusInput specialtyNoPct =
            new PromoGridAdminController.SpecialtyFocusInput();
        specialtyNoPct.territory2Id = fakeTerritoryId();
        specialtyNoPct.specialty = 'Cardiology';
        Boolean caughtSpecialtyPct = false;
        try {
            PromoGridAdminController.upsertSpecialtyFocus(specialtyNoPct);
        } catch (AuraHandledException e) {
            caughtSpecialtyPct = true;
        }
        System.assert(caughtSpecialtyPct);

        Boolean caughtMissingClass = false;
        try {
            PromoGridAdminController.upsertClassTargeting(new PromoGridAdminController.ClassTargetingInput());
        } catch (AuraHandledException e) {
            caughtMissingClass = true;
        }
        System.assert(caughtMissingClass);

        PromoGridAdminController.ClassTargetingInput classNoPct =
            new PromoGridAdminController.ClassTargetingInput();
        classNoPct.territory2Id = fakeTerritoryId();
        classNoPct.classCode = 'A1';
        Boolean caughtClassPct = false;
        try {
            PromoGridAdminController.upsertClassTargeting(classNoPct);
        } catch (AuraHandledException e) {
            caughtClassPct = true;
        }
        System.assert(caughtClassPct);

        Boolean caughtMissingGrid = false;
        try {
            PromoGridAdminController.getPromoGrid(null);
        } catch (AuraHandledException e) {
            caughtMissingGrid = true;
        }
        System.assert(caughtMissingGrid);

        Boolean caughtDeleteWeight = false;
        try {
            PromoGridAdminController.deleteProductWeight(null);
        } catch (AuraHandledException e) {
            caughtDeleteWeight = true;
        }
        System.assert(caughtDeleteWeight);

        Boolean caughtDeleteSpecialty = false;
        try {
            PromoGridAdminController.deleteSpecialtyFocus(null);
        } catch (AuraHandledException e) {
            caughtDeleteSpecialty = true;
        }
        System.assert(caughtDeleteSpecialty);

        Boolean caughtDeleteClass = false;
        try {
            PromoGridAdminController.deleteClassTargeting(null);
        } catch (AuraHandledException e) {
            caughtDeleteClass = true;
        }
        System.assert(caughtDeleteClass);

        PromoGridAdminController.skipLineTerritoryValidation = false;
        Boolean caughtAssertLine = false;
        try {
            PromoGridAdminController.ProductWeightInput input =
                new PromoGridAdminController.ProductWeightInput();
            input.territory2Id = fakeTerritoryId();
            input.product2Id = UserInfo.getUserId();
            input.weightPercentage = 10;
            PromoGridAdminController.upsertProductWeight(input);
        } catch (AuraHandledException e) {
            caughtAssertLine = true;
        }
        System.assert(caughtAssertLine, 'Expected line territory validation');
    }

    private static Id fakeTerritoryId() {
        // Valid-looking Territory2 Id prefix for text-key child records in tests.
        return Id.valueOf('0MIhk0000000001GAA');
    }
}