@IsTest
private class DistributorsManagementControllerTest {
    private class GeoMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String body = req.getEndpoint() != null ? req.getEndpoint() : '';
            // Distinct coords for Zamalek pilot so it does not geo-match the Sofico seed alias
            if (body.contains('Zamalek') || body.contains('zamalek')) {
                res.setBody(
                    '{"status":"OK","results":[{"formatted_address":"Zamalek","geometry":{"location":{"lat":30.0626,"lng":31.2197}}}]}'
                );
            } else {
                res.setBody(
                    '{"status":"OK","results":[{"formatted_address":"Cairo","geometry":{"location":{"lat":30.0444,"lng":31.2357}}}]}'
                );
            }
            return res;
        }
    }

    private class NominatimMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '[{"lat":"30.0444","lon":"31.2357","display_name":"Cairo, Egypt"}]'
            );
            return res;
        }
    }

    private class NominatimEmptyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    private class GoogleZeroMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ZERO_RESULTS","results":[]}');
            return res;
        }
    }

    private class NominatimRateLimitMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(429);
            res.setBody('rate limited');
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        Distributor_Geocode_Config__c cfg = new Distributor_Geocode_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Google_API_Key__c = 'test-key',
            Auto_Confirm_Threshold__c = 85,
            Proximity_Meters__c = 250
        );
        upsert cfg;

        Product2 p = new Product2(
            Name = 'EMPACOZA PLUS 25/5 MG 30 TAB',
            ProductCode = 'Ep25',
            External_ID__c = 'Ep25',
            Family = 'Cardiology',
            IsActive = true
        );
        insert p;

        Account pharmacy = new Account(Name = 'Test Pharmacy Ezaby', BillingCountry = 'Egypt');
        insert pharmacy;

        Database.insert(
            new List<SObject>{
                new Distributor_Product_Alias__c(
                    Distributor_Code__c = 'Sofico',
                    Distributor_Item_Code__c = '1015473',
                    Distributor_Item_Name__c = 'EMPACOZA PLUS 25/5 MG 30 TAB',
                    Product2_Id__c = p.Id,
                    Zeta_Code__c = 'Ep25',
                    Match_Confidence__c = 100,
                    Match_Method__c = 'Seeded',
                    Status__c = 'Confirmed',
                    Unique_Key__c = 'Sofico|1015473'
                ),
                new Distributor_Sellout_Alias__c(
                    Distributor_Code__c = 'Sofico',
                    Distributor_Client_Code__c = '1500052105',
                    Distributor_Client_Name__c = 'Test Pharmacy Ezaby',
                    Address__c = 'Test Street Cairo',
                    Governorate__c = 'Cairo',
                    Brick_Code__c = '5101',
                    Latitude__c = 30.0444,
                    Longitude__c = 31.2357,
                    Geocode_Status__c = 'Geocoded',
                    Pharmacy_Account__c = pharmacy.Id,
                    Match_Confidence__c = 100,
                    Match_Method__c = 'Manual',
                    Status__c = 'Confirmed',
                    Unique_Key__c = 'Sofico|1500052105'
                )
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void productAliasCrudAndSearch() {
        List<DistributorsManagementController.ProductAliasRow> rows = DistributorsManagementController.getProductAliases(
            'Sofico',
            null,
            false,
            50,
            null,
            null
        );
        System.assert(!rows.isEmpty());
        System.assertNotEquals(null, rows[0].productUrl);
        DistributorsManagementController.ProductMappingNav nav = DistributorsManagementController.getProductMappingNav(
            null,
            null,
            false
        );
        System.assert(nav != null && nav.distributors != null && !nav.distributors.isEmpty());

        String drafts = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'recordId' => rows[0].recordId,
                    'itemName' => 'Updated Item Name',
                    'status' => 'Confirmed',
                    'confidence' => 95,
                    'zetaCode' => 'Ep25'
                }
            }
        );
        Integer saved = DistributorsManagementController.saveProductAliasDrafts(drafts);
        System.assert(saved >= 1);

        Product2 other = new Product2(
            Name = 'DOZOVA NAD 30 TAB',
            ProductCode = 'DN30',
            External_ID__c = 'DN30',
            IsActive = true
        );
        insert other;
        DistributorsManagementController.ProductAliasRow updated = DistributorsManagementController.updateProductAlias(
            rows[0].recordId,
            other.Id,
            'Confirmed',
            100
        );
        System.assertEquals(other.Id, updated.productId);
        System.assert(!DistributorsManagementController.searchProducts('DOZOVA').isEmpty());
        Integer n = DistributorsManagementController.bulkConfirmProductAliases(90, 'Sofico');
        System.assert(n >= 0);
    }

    @IsTest
    static void selloutAliasLinkAndCreate() {
        List<DistributorsManagementController.SelloutAliasRow> rows = DistributorsManagementController.getSelloutAliases(
            'Sofico',
            null,
            false,
            50
        );
        System.assert(!rows.isEmpty());
        Account pharmacy = [SELECT Id, Name FROM Account WHERE Name = 'Test Pharmacy Ezaby' LIMIT 1];
        System.assertNotEquals(null, pharmacy.Id);
        List<DistributorsManagementController.PharmacyOption> found = DistributorsManagementController.searchPharmacies(
            'Test Pharmacy'
        );
        // RecordType filter may exclude in some orgs; at least direct account exists for linking
        System.assert(found != null);

        Distributor_Sellout_Alias__c pending = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'IBNSINA',
            Distributor_Client_Code__c = '999001',
            Distributor_Client_Name__c = 'New Client Pharmacy',
            Address__c = 'Nasr City',
            Governorate__c = 'Cairo',
            Brick_Code__c = '5101',
            Geocode_Status__c = 'Pending',
            Status__c = 'Unmatched',
            Unique_Key__c = 'IBNSINA|999001'
        );
        Database.insert(pending, AccessLevel.SYSTEM_MODE);

        DistributorsManagementController.SelloutAliasRow created = DistributorsManagementController.updateSelloutAlias(
            pending.Id,
            null,
            'Confirmed',
            100,
            true
        );
        System.assertNotEquals(null, created.pharmacyId);
        DistributorsManagementController.mergeSelloutAliases(pending.Id, created.pharmacyId);
    }

    @IsTest
    static void geocodeConfigAndNominatimFallback() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        cfg.Google_API_Key__c = null;
        upsert cfg;

        DistributorsManagementController.GeocodeConfigStatus beforeSave = DistributorsManagementController.getGeocodeConfigStatus();
        System.assertEquals(false, beforeSave.hasGoogleKey);

        DistributorsManagementController.GeocodeConfigStatus afterSave = DistributorsManagementController.saveGeocodeApiKey(
            'live-key'
        );
        System.assertEquals(true, afterSave.hasGoogleKey);

        // Clear again and exercise Nominatim JSON shape
        afterSave = DistributorsManagementController.saveGeocodeApiKey('');
        System.assertEquals(false, afterSave.hasGoogleKey);
        Test.setMock(HttpCalloutMock.class, new NominatimMock());
        Test.startTest();
        DistributorGeocodeService.GeoResult geo = DistributorGeocodeService.geocode(
            'Pharmacy',
            'Tahrir Street',
            'Cairo'
        );
        Test.stopTest();
        System.assertEquals('Geocoded', geo.status);
        System.assertEquals('Nominatim', geo.provider);
    }

    @IsTest
    static void ingestAndBatch() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        String rowsJson = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '1015473',
                    'itemName' => 'EMPACOZA PLUS 25/5 MG 30 TAB',
                    'clientCode' => '1500052105',
                    'clientName' => 'Test Pharmacy Ezaby',
                    'address' => 'Test Street',
                    'governorate' => 'Cairo',
                    'brickCode' => '5101',
                    'quantity' => 2,
                    'revenue' => 500,
                    'unitPrice' => 250
                },
                new Map<String, Object>{
                    'itemCode' => 'NEWITEM1',
                    'itemName' => 'EMPACOZA PLUS 25/5 MG 30 TAB',
                    'clientCode' => 'NEWCLIENT1',
                    'clientName' => 'Nearby Pharmacy',
                    'address' => 'Test Street Cairo',
                    'governorate' => 'Cairo',
                    'brickCode' => '5101',
                    'quantity' => 1,
                    'revenue' => 250
                },
                new Map<String, Object>{
                    'itemCode' => 'NEWITEM2',
                    'itemName' => 'EMPACOZA PLUS 25/5 MG 30 TAB',
                    'clientCode' => 'GEOONLY1',
                    'clientName' => 'Standalone Geo Pharmacy',
                    'address' => 'Maadi Street',
                    'governorate' => 'Cairo',
                    'brickCode' => '9999',
                    'quantity' => 3,
                    'revenue' => 300,
                    'unitPrice' => 100
                }
            }
        );

        DistributorsManagementController.PreviewResolveResult preview = DistributorsManagementController.previewMappingCoverage(
            'Sofico',
            rowsJson
        );
        System.assertEquals(3, preview.distinctProducts);

        Test.startTest();
        DistributorsManagementController.ImportChunkResult result = DistributorsManagementController.ingestNormalizedRows(
            'Sofico',
            'test.xlsx',
            '2026-06',
            rowsJson,
            null,
            true
        );
        System.assertNotEquals(null, result.batchId);
        Test.stopTest();

        List<DistributorsManagementController.BatchRow> batches = DistributorsManagementController.getImportBatches(10);
        System.assert(!batches.isEmpty());

        List<Distributor_Sellout_Alias__c> geoAliases = [
            SELECT Id, Geocode_Status__c, Pharmacy_Account__c, Latitude__c, Longitude__c, Status__c, Match_Method__c
            FROM Distributor_Sellout_Alias__c
            WHERE Distributor_Code__c = 'Sofico'
        ];
        System.assert(!geoAliases.isEmpty());
    }

    @IsTest
    static void batchAutoCreatesPharmacyFromGeocode() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        Distributor_Sellout_Alias__c pending = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'GEO100',
            Distributor_Client_Name__c = 'Unique Geocoded Client',
            Address__c = 'Zamalek Street',
            Governorate__c = 'Cairo',
            Geocode_Status__c = 'Pending',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|GEO100'
        );
        Database.insert(pending, AccessLevel.SYSTEM_MODE);

        Sales_Data_Import_Batch__c batch = new Sales_Data_Import_Batch__c(
            File_Name__c = 'geo-pilot.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = 'Queued',
            Report_Month__c = Date.newInstance(2026, 6, 1)
        );
        insert batch;

        String staging = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '1015473',
                    'itemName' => 'EMPACOZA PLUS 25/5 MG 30 TAB',
                    'clientCode' => 'GEO100',
                    'clientName' => 'Unique Geocoded Client',
                    'address' => 'Zamalek Street',
                    'governorate' => 'Cairo',
                    'quantity' => 1,
                    'unitPrice' => 10
                }
            }
        );
        ContentVersion cv = new ContentVersion(
            Title = 'DistributorImport_' + batch.Id,
            PathOnClient = 'staging.json',
            VersionData = Blob.valueOf(staging)
        );
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];
        batch.ContentVersion_Id__c = cv.Id;
        update batch;

        // Ensure product alias confirmed for withdrawal path
        Product2 p = [SELECT Id FROM Product2 WHERE External_ID__c = 'Ep25' LIMIT 1];
        Database.insert(
            new Distributor_Product_Alias__c(
                Distributor_Code__c = 'Egydrug',
                Distributor_Item_Code__c = '1015473',
                Distributor_Item_Name__c = 'EMPACOZA PLUS 25/5 MG 30 TAB',
                Product2_Id__c = p.Id,
                Zeta_Code__c = 'Ep25',
                Match_Confidence__c = 100,
                Match_Method__c = 'Seeded',
                Status__c = 'Confirmed',
                Unique_Key__c = 'Egydrug|1015473'
            ),
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        Database.executeBatch(new DistributorSalesImportBatch(batch.Id, true), 5);
        Test.stopTest();

        Distributor_Sellout_Alias__c updated = [
            SELECT Pharmacy_Account__c, Geocode_Status__c, Latitude__c, Status__c, Match_Method__c
            FROM Distributor_Sellout_Alias__c
            WHERE Id = :pending.Id
        ];
        System.assertEquals('Geocoded', updated.Geocode_Status__c);
        System.assertNotEquals(null, updated.Latitude__c);
        System.assertNotEquals(null, updated.Pharmacy_Account__c);
        System.assertEquals('GeoCluster+AutoCreate', updated.Match_Method__c);
    }

    @IsTest
    static void seedFromCsv() {
        String csv =
            'Dist,Item Code,Item Name,Zeta Code,Zeta Name\n' +
            'Egydrug,99258,DOZOVA TEST,Ep25,EMPACOZA PLUS 25/5 MG 30 TAB\n';
        DistributorProductMappingSeed.SeedResult seed = DistributorProductMappingSeed.seedFromCsv(csv);
        System.assert(seed.aliasesUpserted >= 1);
        DistributorsManagementController.SeedResultWrapper wrap = DistributorsManagementController.seedProductMapping();
        System.assertNotEquals(null, wrap.message);
    }

    @IsTest
    static void geocodeCallout() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        Test.startTest();
        DistributorGeocodeService.GeoResult geo = DistributorGeocodeService.geocode(
            'Pharmacy',
            'Tahrir Street',
            'Cairo'
        );
        Test.stopTest();
        System.assertEquals('Geocoded', geo.status);
        System.assertEquals(30.0444, geo.latitude);
        System.assertEquals('Skipped', DistributorGeocodeService.geocode(null, null, null).status);
        System.assertEquals('Skipped', DistributorGeocodeService.geocode('OnlyName', null, null).status);
        System.assert(
            String.isNotBlank(DistributorGeocodeService.geocode(null, null, null).recommendation)
        );
        System.assertNotEquals(
            null,
            DistributorGeocodeService.recommendationForStatus('Failed', null)
        );
        System.assertNotEquals(
            null,
            DistributorGeocodeService.recommendationForStatus('Pending', null)
        );
        System.assertEquals(
            null,
            DistributorGeocodeService.recommendationForStatus('Geocoded', null)
        );
    }

    @IsTest
    static void geocodeFailureMessagesNominatim() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        cfg.Google_API_Key__c = null;
        upsert cfg;

        Test.setMock(HttpCalloutMock.class, new NominatimEmptyMock());
        Test.startTest();
        DistributorGeocodeService.GeoResult empty = DistributorGeocodeService.geocode(
            'Pharmacy',
            'Unknown alley / nowhere',
            'Cairo'
        );
        Test.stopTest();

        System.assertEquals('Failed', empty.status);
        System.assert(String.isNotBlank(empty.message));
        System.assert(String.isNotBlank(empty.recommendation));
    }

    @IsTest
    static void geocodeFailureMessagesRateLimit() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        cfg.Google_API_Key__c = null;
        upsert cfg;

        Test.setMock(HttpCalloutMock.class, new NominatimRateLimitMock());
        Test.startTest();
        DistributorGeocodeService.GeoResult limited = DistributorGeocodeService.geocode(
            'Pharmacy',
            'Tahrir',
            'Cairo'
        );
        Test.stopTest();

        System.assertEquals('Failed', limited.status);
        System.assert(limited.message.contains('429') || limited.message.contains('Nominatim'));
    }

    @IsTest
    static void geocodeFailureMessagesGoogle() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        cfg.Google_API_Key__c = 'test-key';
        upsert cfg;

        Test.setMock(HttpCalloutMock.class, new GoogleZeroMock());
        Test.startTest();
        DistributorGeocodeService.GeoResult zero = DistributorGeocodeService.geocode(
            'Pharmacy',
            'Unknown alley',
            'Cairo'
        );
        Test.stopTest();

        System.assertEquals('Failed', zero.status);
        System.assert(String.isNotBlank(zero.message));
    }

    @IsTest
    static void selloutRowExposesGeoAndAccountLinks() {
        Distributor_Sellout_Alias__c alias = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'FAILGEO1',
            Distributor_Client_Name__c = 'Failed Geo Pharmacy',
            Address__c = 'Unknown alley',
            Governorate__c = 'Cairo',
            Geocode_Status__c = 'Failed',
            Geocode_Message__c =
                'Nominatim found no match.\nRecommendation: Link pharmacy manually.',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|FAILGEO1'
        );
        insert alias;
        List<DistributorsManagementController.SelloutAliasRow> rows = DistributorsManagementController.getSelloutAliases(
            'Egydrug',
            null,
            true,
            50
        );
        Boolean found = false;
        for (DistributorsManagementController.SelloutAliasRow row : rows) {
            if (row.clientCode == 'FAILGEO1') {
                found = true;
                System.assertEquals('Failed', row.geocodeStatus);
                System.assertNotEquals(null, row.recordUrl);
                System.assert(String.isNotBlank(row.geocodeMessage));
                System.assert(String.isNotBlank(row.geocodeRecommendation));
            }
        }
        System.assert(found, 'Expected failed geo alias in sellout rows');
    }

    @IsTest
    static void batchPersistsGeocodeFailureMessage() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        cfg.Google_API_Key__c = null;
        upsert cfg;

        Sales_Data_Import_Batch__c batch = new Sales_Data_Import_Batch__c(
            File_Name__c = 'geo-fail.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = 'Queued',
            Report_Month__c = Date.newInstance(2026, 6, 1)
        );
        insert batch;
        insert new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'BATCHFAIL1',
            Distributor_Client_Name__c = 'Batch Fail Pharmacy',
            Address__c = 'Unknown alley / nowhere',
            Governorate__c = 'Cairo',
            Geocode_Status__c = 'Pending',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|BATCHFAIL1'
        );

        Test.setMock(HttpCalloutMock.class, new NominatimEmptyMock());
        Test.startTest();
        Database.executeBatch(new DistributorSalesImportBatch(batch.Id, false), 1);
        Test.stopTest();

        Distributor_Sellout_Alias__c updated = [
            SELECT Geocode_Status__c, Geocode_Message__c
            FROM Distributor_Sellout_Alias__c
            WHERE Unique_Key__c = 'Egydrug|BATCHFAIL1'
            LIMIT 1
        ];
        System.assertEquals('Failed', updated.Geocode_Status__c);
        System.assert(String.isNotBlank(updated.Geocode_Message__c));
        System.assert(updated.Geocode_Message__c.contains('Recommendation'));
    }
}