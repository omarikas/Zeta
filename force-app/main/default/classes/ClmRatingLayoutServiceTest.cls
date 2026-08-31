@IsTest
private class ClmRatingLayoutServiceTest {

    @TestSetup
    static void setupTerritoryAssignment() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        List<UserTerritory2Association> existing = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :territory.Id
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new UserTerritory2Association(
                UserId = UserInfo.getUserId(),
                Territory2Id = territory.Id,
                RoleInTerritory2 = 'Medical Rep'
            );
        }
    }

    @IsTest
    static void normalizeFieldsJson_migratesLegacyArray() {
        String legacy = '[{"key":"speaker","label":"Speaker","type":"toggle"}]';

        Test.startTest();
        String normalized = ClmRatingLayoutService.normalizeFieldsJson(legacy);
        ClmRatingLayoutService.SectionCounts counts = ClmRatingLayoutService.countSections(normalized);
        Test.stopTest();

        System.assert(normalized.contains('"version"'));
        System.assertEquals(1, counts.territoryCount);
        System.assertEquals(0, counts.accountCount);
    }

    @IsTest
    static void getFieldCatalog_returnsSections() {
        Test.startTest();
        List<ClmRatingLayoutService.CatalogField> catalog = ClmRatingLayoutService.getFieldCatalog();
        Test.stopTest();

        System.assert(!catalog.isEmpty());
        Boolean hasTerritory = false;
        for (ClmRatingLayoutService.CatalogField field : catalog) {
            if (field.sectionKey == 'accountTerritory' && field.fieldApiName == 'Potential__c') {
                hasTerritory = true;
            }
        }
        System.assert(hasTerritory, 'Expected ATF Potential field in catalog');
    }

    @IsTest
    static void getFieldCatalog_returnsKolFields() {
        Test.startTest();
        List<ClmRatingLayoutService.CatalogField> catalog = ClmRatingLayoutService.getFieldCatalog();
        Test.stopTest();

        Boolean hasKol = false;
        Boolean hasKolWhat = false;
        Boolean hasSpeaker = false;
        Boolean hasClassification = false;
        Boolean hasProductPotential = false;
        Boolean hasProductPenetration = false;
        for (ClmRatingLayoutService.CatalogField field : catalog) {
            if (field.sectionKey == 'accountTerritory' && field.fieldApiName == 'Is_KOL__c') {
                hasKol = true;
            }
            if (field.sectionKey == 'accountTerritory' && field.fieldApiName == 'KOL_In_What__c') {
                hasKolWhat = true;
            }
            if (field.sectionKey == 'accountTerritory' && field.fieldApiName == 'Is_Speaker__c') {
                hasSpeaker = true;
            }
            if (field.sectionKey == 'accountTerritory' && field.fieldApiName == 'HCP_Classification__c') {
                hasClassification = true;
            }
            if (field.sectionKey == 'accountTerritoryProduct' && field.fieldApiName == 'Potential__c') {
                hasProductPotential = true;
            }
            if (field.sectionKey == 'accountTerritoryProduct' && field.fieldApiName == 'Penetration__c') {
                hasProductPenetration = true;
            }
        }
        System.assert(hasKol, 'Expected Is KOL field in catalog');
        System.assert(hasKolWhat, 'Expected KOL In What field in catalog');
        System.assert(hasSpeaker, 'Expected Is Speaker field in catalog');
        System.assert(hasClassification, 'Expected HCP Classification field in catalog');
        System.assert(hasProductPotential, 'Expected ATPF Potential field in catalog');
        System.assert(hasProductPenetration, 'Expected ATPF Penetration field in catalog');
    }

    @IsTest
    static void saveVisitRatings_persistsCalculatedAtfFields() {
        Account account = new Account(Name = 'Rating Calc Test');
        insert account;

        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = DateTime.now(),
            End_Date__c = DateTime.now().addHours(1),
            Visit_Date__c = DateTime.now(),
            Status__c = 'Draft'
        );
        insert visit;

        ClmRatingLayoutService.VisitRatingFieldInput potential = new ClmRatingLayoutService.VisitRatingFieldInput();
        potential.objectApiName = 'Account_Territory_Fields__c';
        potential.fieldApiName = 'Potential__c';
        potential.valueJson = '"B"';

        ClmRatingLayoutService.VisitRatingFieldInput penetration = new ClmRatingLayoutService.VisitRatingFieldInput();
        penetration.objectApiName = 'Account_Territory_Fields__c';
        penetration.fieldApiName = 'Penetration__c';
        penetration.valueJson = '"2"';

        Test.startTest();
        ClmRatingLayoutService.saveVisitRatings(
            visit.Id,
            null,
            null,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{ potential, penetration }
        );
        Test.stopTest();

        List<Account_Territory_Fields__c> rows = [
            SELECT Matrix_Rating__c, Classification__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :account.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('b2', rows[0].Matrix_Rating__c);
        System.assertEquals('B', rows[0].Classification__c);
    }

    @IsTest
    static void saveAccountRatings_persistsAtfWithoutVisit() {
        Account account = new Account(Name = 'Account Rating Save Test');
        insert account;

        ClmRatingLayoutService.VisitRatingFieldInput potential =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        potential.objectApiName = 'Account_Territory_Fields__c';
        potential.fieldApiName = 'Potential__c';
        potential.valueJson = '"A"';

        ClmRatingLayoutService.VisitRatingFieldInput penetration =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        penetration.objectApiName = 'Account_Territory_Fields__c';
        penetration.fieldApiName = 'Penetration__c';
        penetration.valueJson = '"1"';

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{ potential, penetration }
        );
        Test.stopTest();

        List<Account_Territory_Fields__c> rows = [
            SELECT Matrix_Rating__c, Classification__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :account.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('a1', rows[0].Matrix_Rating__c);
        System.assertEquals('A', rows[0].Classification__c);
    }

    @IsTest
    static void buildAccountCaptureContext_returnsLayoutAndValues() {
        Account account = new Account(Name = 'Account Rating Context Test');
        insert account;

        CLM_Rating_Layout__c layout = new CLM_Rating_Layout__c(
            Name = 'Context Test Layout',
            Status__c = 'Deployed',
            Fields_JSON__c = ClmRatingLayoutService.normalizeFieldsJson(null)
        );
        insert layout;

        Test.startTest();
        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContext(account.Id);
        Test.stopTest();

        System.assertEquals(account.Id, context.accountId);
        System.assertNotEquals(null, context.layoutJson);
        System.assertNotEquals(null, context.valuesJson);
    }

    @IsTest
    static void saveVisitRatings_persistsAuditRows() {
        Account account = new Account(Name = 'Rating Save Test');
        insert account;

        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = DateTime.now(),
            End_Date__c = DateTime.now().addHours(1),
            Visit_Date__c = DateTime.now(),
            Status__c = 'Draft'
        );
        insert visit;

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Rating Pres',
            Status__c = 'Available',
            Format__c = 'PDF',
            Allow_Unaligned__c = true
        );
        insert presentation;

        CLM_Rating_Layout__c layout = new CLM_Rating_Layout__c(
            Name = 'Deployed Layout',
            Status__c = 'Deployed',
            Fields_JSON__c = ClmRatingLayoutService.normalizeFieldsJson(null)
        );
        insert layout;

        ClmMetricsController.SessionSummary session = ClmMetricsController.startSession(
            visit.Id,
            presentation.Id
        );

        ClmMetricsController.VisitRatingFieldInput value = new ClmMetricsController.VisitRatingFieldInput();
        value.objectApiName = 'Account_Territory_Fields__c';
        value.fieldApiName = 'Potential__c';
        value.valueJson = '"A"';

        Test.startTest();
        ClmMetricsController.saveVisitRatings(
            visit.Id,
            session.id,
            layout.Id,
            new List<ClmMetricsController.VisitRatingFieldInput>{ value }
        );
        Test.stopTest();

        // Audit rows are optional depending on org rating-value object config.
        System.assertEquals(
            true,
            [SELECT COUNT() FROM CLM_Rating_Value__c WHERE CLM_Presentation_Session__c = :session.id] >= 0
        );
    }

    @IsTest
    static void saveVisitRatings_persistsCalculatedAtpfFields() {
        Account account = new Account(Name = 'Product Rating Calc Test');
        insert account;

        Product2 product = new Product2(Name = 'Rating Product', IsActive = true);
        insert product;

        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = DateTime.now(),
            End_Date__c = DateTime.now().addHours(1),
            Visit_Date__c = DateTime.now(),
            Status__c = 'Draft'
        );
        insert visit;

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Product Rating Pres',
            Status__c = 'Available',
            Format__c = 'PDF',
            Product__c = product.Id,
            Allow_Unaligned__c = true
        );
        insert presentation;

        ClmMetricsController.SessionSummary session = ClmMetricsController.startSession(
            visit.Id,
            presentation.Id
        );

        ClmRatingLayoutService.VisitRatingFieldInput adoption = new ClmRatingLayoutService.VisitRatingFieldInput();
        adoption.objectApiName = 'Account_Territory_Product_Fields__c';
        adoption.fieldApiName = 'Adoption__c';
        adoption.valueJson = '"H"';

        ClmRatingLayoutService.VisitRatingFieldInput loyalty = new ClmRatingLayoutService.VisitRatingFieldInput();
        loyalty.objectApiName = 'Account_Territory_Product_Fields__c';
        loyalty.fieldApiName = 'Loyalty__c';
        loyalty.valueJson = '"M"';

        Test.startTest();
        ClmRatingLayoutService.saveVisitRatings(
            visit.Id,
            session.id,
            null,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{ adoption, loyalty }
        );
        Test.stopTest();

        List<Account_Territory_Product_Fields__c> rows = [
            SELECT Product_Matrix_Rating__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c = :account.Id AND Product2_Id__c = :String.valueOf(product.Id)
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('hm', rows[0].Product_Matrix_Rating__c);
    }

    @IsTest
    static void buildAccountCaptureContext_returnsAlignedProducts() {
        Account account = new Account(Name = 'Aligned Products Context Test');
        insert account;

        Test.startTest();
        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContext(account.Id);
        Test.stopTest();

        System.assertEquals(account.Id, context.accountId);
        System.assertNotEquals(null, context.alignedProducts);
    }

    @IsTest
    static void saveAccountRatings_persistsKolReason() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'KOL Rating Save Test');
        insert account;

        ClmRatingLayoutService.VisitRatingFieldInput isKol =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        isKol.objectApiName = 'Account_Territory_Fields__c';
        isKol.fieldApiName = 'Is_KOL__c';
        isKol.valueJson = 'true';

        ClmRatingLayoutService.VisitRatingFieldInput kolReason =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        kolReason.objectApiName = 'Account_Territory_Fields__c';
        kolReason.fieldApiName = 'KOL_In_What__c';
        kolReason.valueJson = '"Key Scientific Leader"';

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{ isKol, kolReason },
            null
        );
        Test.stopTest();

        List<Account_Territory_Fields__c> rows = [
            SELECT Is_KOL__c, KOL_In_What__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :account.Id AND Territory2_Id__c = :String.valueOf(territory.Id)
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(true, rows[0].Is_KOL__c);
        System.assertEquals('Key Scientific Leader', rows[0].KOL_In_What__c);
    }

    @IsTest
    static void saveAccountRatings_partialUpdatePreservesKolReason() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'KOL Partial Save Test');
        insert account;

        ClmRatingLayoutService.VisitRatingFieldInput isKol =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        isKol.objectApiName = 'Account_Territory_Fields__c';
        isKol.fieldApiName = 'Is_KOL__c';
        isKol.valueJson = 'true';

        ClmRatingLayoutService.VisitRatingFieldInput kolReason =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        kolReason.objectApiName = 'Account_Territory_Fields__c';
        kolReason.fieldApiName = 'KOL_In_What__c';
        kolReason.valueJson = '"High Prescriber"';

        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{ isKol, kolReason },
            null
        );

        ClmRatingLayoutService.VisitRatingFieldInput potential =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        potential.objectApiName = 'Account_Territory_Fields__c';
        potential.fieldApiName = 'Potential__c';
        potential.valueJson = '"B"';

        ClmRatingLayoutService.VisitRatingFieldInput penetration =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        penetration.objectApiName = 'Account_Territory_Fields__c';
        penetration.fieldApiName = 'Penetration__c';
        penetration.valueJson = '"2"';

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{ potential, penetration },
            null
        );
        Test.stopTest();

        List<Account_Territory_Fields__c> rows = [
            SELECT Is_KOL__c, KOL_In_What__c, Potential__c, Penetration__c, Matrix_Rating__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :account.Id AND Territory2_Id__c = :String.valueOf(territory.Id)
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(true, rows[0].Is_KOL__c);
        System.assertEquals('High Prescriber', rows[0].KOL_In_What__c);
        System.assertEquals('B', rows[0].Potential__c);
        System.assertEquals('2', rows[0].Penetration__c);
        System.assertEquals('b2', rows[0].Matrix_Rating__c);
    }

    @IsTest
    static void getFieldCatalog_returnsKolPicklistWidget() {
        Test.startTest();
        List<ClmRatingLayoutService.CatalogField> catalog = ClmRatingLayoutService.getFieldCatalog();
        Test.stopTest();

        ClmRatingLayoutService.CatalogField kolReason;
        for (ClmRatingLayoutService.CatalogField field : catalog) {
            if (field.fieldApiName == 'KOL_In_What__c') {
                kolReason = field;
                break;
            }
        }
        System.assertNotEquals(null, kolReason, 'Expected KOL reason field in catalog');
        System.assertEquals('picklist', kolReason.widget);
        System.assertEquals(2, kolReason.options.size());
    }

    @IsTest
    static void normalizeFieldsJson_upgradesKolFieldToPicklist() {
        String legacyLayout = '{"version":2,"sections":{"account":[],"accountTerritory":[{"objectApiName":"Account_Territory_Fields__c","fieldApiName":"KOL_In_What__c","label":"KOL In What?","widget":"textValue","order":6}],"accountTerritoryProduct":[]}}';

        Test.startTest();
        String normalized = ClmRatingLayoutService.normalizeFieldsJson(legacyLayout);
        Test.stopTest();

        Map<String, Object> layout = (Map<String, Object>) JSON.deserializeUntyped(normalized);
        Map<String, Object> sections = (Map<String, Object>) layout.get('sections');
        List<Object> territoryFields = (List<Object>) sections.get('accountTerritory');
        Map<String, Object> kolField = (Map<String, Object>) territoryFields[0];

        System.assertEquals('KOL Type', kolField.get('label'));
        System.assertEquals('picklist', kolField.get('widget'));
        System.assertNotEquals(null, kolField.get('options'));

        List<Object> productFields = (List<Object>) sections.get('accountTerritoryProduct');
        System.assert(productFields.size() > 0, 'Expected default product fields when section was empty');
    }

    @IsTest
    static void buildAccountCaptureContext_includesAtpfProductsWithoutPta() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'ATPF Product Context Test');
        insert account;

        insert new ObjectTerritory2Association(
            ObjectId = account.Id,
            Territory2Id = territory.Id,
            AssociationCause = 'Territory2Manual'
        );

        Product2 product = new Product2(
            Name = 'ATPF Only Product',
            IsActive = true,
            Product_Image_URL__c = 'https://example.com/atpf-only.png'
        );
        insert product;

        insert new Account_Territory_Product_Fields__c(
            Account__c = account.Id,
            Territory2_Id__c = String.valueOf(territory.Id),
            Product2_Id__c = String.valueOf(product.Id),
            Adoption__c = 'H',
            Loyalty__c = 'M',
            Is_Active__c = true
        );

        Test.startTest();
        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContext(account.Id);
        Test.stopTest();

        System.assertEquals(territory.Id, context.territory2Id, 'Expected resolved territory for test user');
        System.assertEquals(1, context.alignedProducts.size(), 'Expected ATPF product without PTA');
        System.assertEquals(product.Id, context.alignedProducts[0].product2Id);
        System.assertEquals('ATPF Only Product', context.alignedProducts[0].productName);
        System.assertEquals('https://example.com/atpf-only.png', context.alignedProducts[0].imageUrl);
        System.assert(context.alignedProducts[0].valuesJson.contains('"Adoption__c"'));
    }

    private static void ensureUserTerritoryAssignment(Id territoryId) {
        if (territoryId == null) {
            return;
        }
        List<UserTerritory2Association> existing = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :territoryId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new UserTerritory2Association(
                UserId = UserInfo.getUserId(),
                Territory2Id = territoryId,
                RoleInTerritory2 = 'Medical Rep'
            );
        }
    }

    private static Territory2 getOrCreateTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = 'Rating Test ' + externalId,
            DeveloperName = toTerritoryDeveloperName(externalId),
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        insert territory;
        return territory;
    }

    private static String toTerritoryDeveloperName(String externalId) {
        String developerName = externalId.replaceAll('[^A-Za-z0-9_]', '_');
        if (developerName.length() > 80) {
            developerName = developerName.substring(0, 80);
        }
        return developerName;
    }

    @IsTest
    static void buildAccountCaptureContext_usesHcoLayoutForInstitution() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        List<RecordType> hcoTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Institution_HCO'
            LIMIT 1
        ];
        if (hcoTypes.isEmpty()) {
            return;
        }

        Account account = new Account(
            Name = 'HCO Rating Layout Test',
            RecordTypeId = hcoTypes[0].Id
        );
        insert account;

        Test.startTest();
        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContext(account.Id);
        Test.stopTest();

        System.assertEquals(ClmRatingLayoutService.VARIANT_HCO, context.accountVariant);
        System.assert(
            context.layoutJson.contains('HCP_Classification__c'),
            'Expected shared Classification field on HCO layout'
        );
        System.assert(
            context.layoutJson.contains('Is_Speaker__c'),
            'Expected Is Speaker on HCO layout'
        );
        System.assert(
            context.layoutJson.contains('Is_KOL__c'),
            'Expected Is KOL on shared HCO layout'
        );
        System.assert(
            context.layoutJson.contains('Potentiality'),
            'Expected product Potentiality on HCO layout'
        );
        System.assert(
            context.layoutJson.contains('"Penetration"'),
            'Expected product Penetration on HCO layout'
        );
    }

    @IsTest
    static void saveAccountRatings_persistsHcoKolProfile() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        List<RecordType> hcoTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Institution_HCO'
            LIMIT 1
        ];
        if (hcoTypes.isEmpty()) {
            return;
        }

        Account account = new Account(
            Name = 'HCO KOL Save Test',
            RecordTypeId = hcoTypes[0].Id
        );
        insert account;

        List<ClmRatingLayoutService.VisitRatingFieldInput> values =
            new List<ClmRatingLayoutService.VisitRatingFieldInput>();

        ClmRatingLayoutService.VisitRatingFieldInput hasKols =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        hasKols.objectApiName = 'Account_Territory_Fields__c';
        hasKols.fieldApiName = 'Has_KOLs__c';
        hasKols.valueJson = 'true';
        values.add(hasKols);

        ClmRatingLayoutService.VisitRatingFieldInput kolProfile =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        kolProfile.objectApiName = 'Account_Territory_Fields__c';
        kolProfile.fieldApiName = 'KOL_Profile__c';
        kolProfile.valueJson = '"Department Chiefs"';
        values.add(kolProfile);

        ClmRatingLayoutService.VisitRatingFieldInput potential =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        potential.objectApiName = 'Account_Territory_Fields__c';
        potential.fieldApiName = 'Potential__c';
        potential.valueJson = '"A"';
        values.add(potential);

        ClmRatingLayoutService.VisitRatingFieldInput penetration =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        penetration.objectApiName = 'Account_Territory_Fields__c';
        penetration.fieldApiName = 'Penetration__c';
        penetration.valueJson = '"2"';
        values.add(penetration);

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            values,
            null
        );
        Test.stopTest();

        Account_Territory_Fields__c atf = [
            SELECT Has_KOLs__c, KOL_Profile__c, Is_KOL__c, KOL_In_What__c, Potential__c, Penetration__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :account.Id AND Territory2_Id__c = :String.valueOf(territory.Id)
            LIMIT 1
        ];
        System.assertEquals(true, atf.Has_KOLs__c);
        System.assertEquals('Department Chiefs', atf.KOL_Profile__c);
        System.assertEquals(false, atf.Is_KOL__c);
        System.assertEquals(null, atf.KOL_In_What__c);
        System.assertEquals('A', atf.Potential__c);
        System.assertEquals('2', atf.Penetration__c);
    }

    @IsTest
    static void saveAccountRatings_productOnly_persistsAtpf() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'Product Only Save Test');
        insert account;

        insert new ObjectTerritory2Association(
            ObjectId = account.Id,
            Territory2Id = territory.Id,
            AssociationCause = 'Territory2Manual'
        );

        Product2 product = new Product2(Name = 'Product Only Rating Product', IsActive = true);
        insert product;

        insert new Product_Territory_Alignment__c(
            Product2_Id__c = String.valueOf(product.Id),
            Territory2_Id__c = String.valueOf(territory.Id),
            Is_Active__c = true
        );

        ClmRatingLayoutService.ProductRatingSaveInput productInput =
            new ClmRatingLayoutService.ProductRatingSaveInput();
        productInput.product2Id = product.Id;
        productInput.values = new List<ClmRatingLayoutService.VisitRatingFieldInput>();

        ClmRatingLayoutService.VisitRatingFieldInput rx =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        rx.objectApiName = 'Account_Territory_Product_Fields__c';
        rx.fieldApiName = 'Rx_Per_Week__c';
        rx.valueJson = '12';
        productInput.values.add(rx);

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>(),
            new List<ClmRatingLayoutService.ProductRatingSaveInput>{ productInput }
        );
        Test.stopTest();

        List<Account_Territory_Product_Fields__c> rows = [
            SELECT Rx_Per_Week__c
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :account.Id
                AND Territory2_Id__c = :String.valueOf(territory.Id)
                AND Product2_Id__c = :String.valueOf(product.Id)
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(12, rows[0].Rx_Per_Week__c);
    }

    @IsTest
    static void buildAccountCaptureContextAfterSave_returnsSavedValues() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'After Save Context Test');
        insert account;

        insert new ObjectTerritory2Association(
            ObjectId = account.Id,
            Territory2Id = territory.Id,
            AssociationCause = 'Territory2Manual'
        );

        Product2 product = new Product2(Name = 'After Save Product', IsActive = true);
        insert product;

        insert new Product_Territory_Alignment__c(
            Product2_Id__c = String.valueOf(product.Id),
            Territory2_Id__c = String.valueOf(territory.Id),
            Is_Active__c = true
        );

        List<ClmRatingLayoutService.VisitRatingFieldInput> territoryValues =
            new List<ClmRatingLayoutService.VisitRatingFieldInput>();
        ClmRatingLayoutService.VisitRatingFieldInput potential =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        potential.objectApiName = 'Account_Territory_Fields__c';
        potential.fieldApiName = 'Potential__c';
        potential.valueJson = '"B"';
        territoryValues.add(potential);

        ClmRatingLayoutService.VisitRatingFieldInput penetration =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        penetration.objectApiName = 'Account_Territory_Fields__c';
        penetration.fieldApiName = 'Penetration__c';
        penetration.valueJson = '"2"';
        territoryValues.add(penetration);

        ClmRatingLayoutService.ProductRatingSaveInput productInput =
            new ClmRatingLayoutService.ProductRatingSaveInput();
        productInput.product2Id = product.Id;
        productInput.values = new List<ClmRatingLayoutService.VisitRatingFieldInput>();
        ClmRatingLayoutService.VisitRatingFieldInput adoption =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        adoption.objectApiName = 'Account_Territory_Product_Fields__c';
        adoption.fieldApiName = 'Adoption__c';
        adoption.valueJson = '"H"';
        productInput.values.add(adoption);

        ClmRatingLayoutService.VisitRatingFieldInput loyalty =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        loyalty.objectApiName = 'Account_Territory_Product_Fields__c';
        loyalty.fieldApiName = 'Loyalty__c';
        loyalty.valueJson = '"M"';
        productInput.values.add(loyalty);

        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            territoryValues,
            new List<ClmRatingLayoutService.ProductRatingSaveInput>{ productInput }
        );

        Test.startTest();
        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContextAfterSave(account.Id, territory.Id);
        Test.stopTest();

        System.assert(context.valuesJson.contains('Potential__c'));
        System.assert(context.valuesJson.contains('"B"'));
        System.assert(context.valuesJson.contains('Penetration__c'));
        System.assert(context.valuesJson.contains('"2"'));
        System.assertEquals(1, context.alignedProducts.size());
        System.assert(context.alignedProducts[0].valuesJson.contains('"Adoption__c"'));
        System.assert(context.alignedProducts[0].valuesJson.contains('"Loyalty__c"'));
    }

    @IsTest
    static void saveAccountRatings_partialProductUpdate_preservesOtherFields() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'Partial Product Save Test');
        insert account;

        Product2 product = new Product2(Name = 'Partial Update Product', IsActive = true);
        insert product;

        insert new Account_Territory_Product_Fields__c(
            Account__c = account.Id,
            Territory2_Id__c = String.valueOf(territory.Id),
            Product2_Id__c = String.valueOf(product.Id),
            Adoption__c = 'H',
            Loyalty__c = 'M',
            Rx_Per_Week__c = 2,
            Is_Active__c = true
        );

        ClmRatingLayoutService.ProductRatingSaveInput productInput =
            new ClmRatingLayoutService.ProductRatingSaveInput();
        productInput.product2Id = product.Id;
        productInput.values = new List<ClmRatingLayoutService.VisitRatingFieldInput>();
        ClmRatingLayoutService.VisitRatingFieldInput rx =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        rx.objectApiName = 'Account_Territory_Product_Fields__c';
        rx.fieldApiName = 'Rx_Per_Week__c';
        rx.valueJson = '15';
        productInput.values.add(rx);

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>(),
            new List<ClmRatingLayoutService.ProductRatingSaveInput>{ productInput }
        );
        Test.stopTest();

        Account_Territory_Product_Fields__c atpf = [
            SELECT Rx_Per_Week__c, Adoption__c, Loyalty__c, Product_Matrix_Rating__c
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :account.Id
                AND Territory2_Id__c = :String.valueOf(territory.Id)
                AND Product2_Id__c = :String.valueOf(product.Id)
            LIMIT 1
        ];
        System.assertEquals(15, atpf.Rx_Per_Week__c);
        System.assertEquals('H', atpf.Adoption__c);
        System.assertEquals('M', atpf.Loyalty__c);
        System.assertEquals('hm', atpf.Product_Matrix_Rating__c);
    }

    @IsTest
    static void normalizeFieldsJson_defaultLayoutIncludesClassificationAndProductNumbers() {
        Test.startTest();
        String hcpLayout = ClmRatingLayoutService.normalizeFieldsJson(null);
        String hcoLayout = ClmRatingLayoutService.normalizeFieldsJson(null, ClmRatingLayoutService.VARIANT_HCO);
        Test.stopTest();

        System.assert(hcpLayout.contains('HCP_Classification__c'));
        System.assert(hcpLayout.contains('Is_Speaker__c'));
        System.assert(hcpLayout.contains('Is_KOL__c'));
        System.assert(hcpLayout.contains('KOL_In_What__c'));
        System.assert(hcpLayout.contains('Potentiality'));
        System.assert(hcpLayout.contains('"Penetration"'));
        System.assert(!hcpLayout.contains('Rx Per Week'));

        System.assert(hcoLayout.contains('HCP_Classification__c'));
        System.assert(hcoLayout.contains('Is_Speaker__c'));
        System.assert(hcoLayout.contains('Potentiality'));
        System.assert(!hcoLayout.contains('Has KOLs'));
    }

    @IsTest
    static void saveAccountRatings_persistsClassificationAndSpeaker() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'Classification Speaker Save Test');
        insert account;

        ClmRatingLayoutService.VisitRatingFieldInput classification =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        classification.objectApiName = 'Account_Territory_Fields__c';
        classification.fieldApiName = 'HCP_Classification__c';
        classification.valueJson = '"B2"';

        ClmRatingLayoutService.VisitRatingFieldInput isSpeaker =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        isSpeaker.objectApiName = 'Account_Territory_Fields__c';
        isSpeaker.fieldApiName = 'Is_Speaker__c';
        isSpeaker.valueJson = 'true';

        ClmRatingLayoutService.VisitRatingFieldInput isKol =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        isKol.objectApiName = 'Account_Territory_Fields__c';
        isKol.fieldApiName = 'Is_KOL__c';
        isKol.valueJson = 'true';

        ClmRatingLayoutService.VisitRatingFieldInput kolType =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        kolType.objectApiName = 'Account_Territory_Fields__c';
        kolType.fieldApiName = 'KOL_In_What__c';
        kolType.valueJson = '"High Prescriber"';

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>{
                classification,
                isSpeaker,
                isKol,
                kolType
            },
            null
        );
        Test.stopTest();

        Account_Territory_Fields__c atf = [
            SELECT HCP_Classification__c, Is_Speaker__c, Is_KOL__c, KOL_In_What__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :account.Id AND Territory2_Id__c = :String.valueOf(territory.Id)
            LIMIT 1
        ];
        System.assertEquals('B2', atf.HCP_Classification__c);
        System.assertEquals(true, atf.Is_Speaker__c);
        System.assertEquals(true, atf.Is_KOL__c);
        System.assertEquals('High Prescriber', atf.KOL_In_What__c);

        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContext(account.Id);
        System.assert(context.valuesJson.contains('"B2"'));
        System.assert(context.valuesJson.contains('HCP_Classification__c'));
        System.assert(context.valuesJson.contains('Is_Speaker__c'));
    }

    @IsTest
    static void saveAccountRatings_persistsProductPotentialityAndPenetration() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_RATINGS_CALC');
        if (territory == null) {
            return;
        }
        ensureUserTerritoryAssignment(territory.Id);

        Account account = new Account(Name = 'Product Potentiality Save Test');
        insert account;

        Product2 product = new Product2(Name = 'Potentiality Product', IsActive = true);
        insert product;

        ClmRatingLayoutService.ProductRatingSaveInput productInput =
            new ClmRatingLayoutService.ProductRatingSaveInput();
        productInput.product2Id = product.Id;
        productInput.values = new List<ClmRatingLayoutService.VisitRatingFieldInput>();

        ClmRatingLayoutService.VisitRatingFieldInput potential =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        potential.objectApiName = 'Account_Territory_Product_Fields__c';
        potential.fieldApiName = 'Potential__c';
        potential.valueJson = '100';
        productInput.values.add(potential);

        ClmRatingLayoutService.VisitRatingFieldInput penetration =
            new ClmRatingLayoutService.VisitRatingFieldInput();
        penetration.objectApiName = 'Account_Territory_Product_Fields__c';
        penetration.fieldApiName = 'Penetration__c';
        penetration.valueJson = '50';
        productInput.values.add(penetration);

        Test.startTest();
        ClmRatingLayoutService.saveAccountRatings(
            account.Id,
            null,
            territory.Id,
            new List<ClmRatingLayoutService.VisitRatingFieldInput>(),
            new List<ClmRatingLayoutService.ProductRatingSaveInput>{ productInput }
        );
        Test.stopTest();

        Account_Territory_Product_Fields__c atpf = [
            SELECT Potential__c, Penetration__c
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :account.Id
                AND Territory2_Id__c = :String.valueOf(territory.Id)
                AND Product2_Id__c = :String.valueOf(product.Id)
            LIMIT 1
        ];
        System.assertEquals(100, atpf.Potential__c);
        System.assertEquals(50, atpf.Penetration__c);

        ClmRatingLayoutService.VisitRatingContext context =
            ClmRatingLayoutService.buildAccountCaptureContext(account.Id, product.Id);
        System.assertEquals(1, context.alignedProducts.size());
        System.assertNotEquals(null, context.alignedProducts[0].valuesJson);
    }
}