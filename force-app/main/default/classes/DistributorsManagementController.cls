/**
 * Admin Apex for Distributors Management: product/sellout mapping, Excel row ingest, batches.
 */
public with sharing class DistributorsManagementController {
    private static final Integer MAX_CHUNK = 2000;

    public class ProductAliasRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String distributorCode;
        @AuraEnabled public String itemCode;
        @AuraEnabled public String itemName;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productUrl;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String zetaCode;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String matchMethod;
        @AuraEnabled public String status;
        @AuraEnabled public String uniqueKey;
    }

    public class NavGroup {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
    }

    public class ProductMappingNav {
        @AuraEnabled public List<NavGroup> distributors;
        @AuraEnabled public List<NavGroup> productLines;
    }

    public class SelloutAliasRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordUrl;
        @AuraEnabled public String distributorCode;
        @AuraEnabled public String clientCode;
        @AuraEnabled public String clientName;
        @AuraEnabled public String address;
        @AuraEnabled public String governorate;
        @AuraEnabled public String brickCode;
        @AuraEnabled public String brickName;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String geocodeStatus;
        @AuraEnabled public String geocodeMessage;
        @AuraEnabled public String geocodeRecommendation;
        @AuraEnabled public Id pharmacyId;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public String pharmacyUrl;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String matchMethod;
        @AuraEnabled public String status;
        @AuraEnabled public String uniqueKey;
        @AuraEnabled public List<String> linkedDistributors;
    }

    public class ProductOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
        @AuraEnabled public String zetaCode;
    }

    public class PharmacyOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class ImportChunkResult {
        @AuraEnabled public Id batchId;
        @AuraEnabled public Integer productAliasesUpserted;
        @AuraEnabled public Integer selloutAliasesUpserted;
        @AuraEnabled public Integer rowsAccepted;
        @AuraEnabled public Integer rowsFailed;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean jobEnqueued;
    }

    public class BatchRow {
        @AuraEnabled public Id batchId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String distributorCode;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Integer rowsInserted;
        @AuraEnabled public Integer rowsUpdated;
        @AuraEnabled public Integer rowsFailed;
        @AuraEnabled public Integer aliasesCreated;
        @AuraEnabled public Integer needsReview;
        @AuraEnabled public String errorLog;
    }

    public class PreviewResolveResult {
        @AuraEnabled public Integer distinctProducts;
        @AuraEnabled public Integer distinctSellouts;
        @AuraEnabled public Integer productsMapped;
        @AuraEnabled public Integer selloutsMapped;
        @AuraEnabled public Integer productsSuggested;
        @AuraEnabled public List<ProductAliasRow> newProductSuggestions;
        @AuraEnabled public List<SelloutAliasRow> newSelloutSuggestions;
    }

    public class GeocodeConfigStatus {
        @AuraEnabled public Boolean hasGoogleKey;
        @AuraEnabled public String providerLabel;
        @AuraEnabled public Decimal proximityMeters;
        @AuraEnabled public Decimal autoConfirmThreshold;
    }

    @AuraEnabled(cacheable=false)
    public static GeocodeConfigStatus getGeocodeConfigStatus() {
        GeocodeConfigStatus s = new GeocodeConfigStatus();
        s.hasGoogleKey = DistributorGeocodeService.hasGoogleApiKey();
        s.providerLabel = s.hasGoogleKey ? 'Google Geocoding' : 'OpenStreetMap Nominatim (fallback)';
        s.proximityMeters = DistributorMatchingUtil.proximityMeters();
        s.autoConfirmThreshold = DistributorMatchingUtil.autoConfirmThreshold();
        return s;
    }

    @AuraEnabled
    public static GeocodeConfigStatus saveGeocodeApiKey(String apiKey) {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) {
            cfg = new Distributor_Geocode_Config__c();
            cfg.SetupOwnerId = UserInfo.getOrganizationId();
            cfg.Proximity_Meters__c = 250;
            cfg.Auto_Confirm_Threshold__c = 85;
        }
        cfg.Google_API_Key__c = String.isBlank(apiKey) ? null : apiKey.trim();
        upsert cfg;
        return getGeocodeConfigStatus();
    }

    // ---------- Product mapping ----------

    @AuraEnabled(cacheable=false)
    public static List<ProductAliasRow> getProductAliases(
        String distributorCode,
        String statusFilter,
        Boolean unmappedOnly,
        Integer limitSize,
        String productLineFilter,
        String searchTerm
    ) {
        Integer lim = limitSize == null || limitSize <= 0 ? 500 : Math.min(limitSize, 2000);
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distributorCode);
        String soql =
            'SELECT Id, Distributor_Code__c, Distributor_Item_Code__c, Distributor_Item_Name__c, ' +
            'Product2_Id__c, Product2_Id__r.Name, Product2_Id__r.Family, Zeta_Code__c, Match_Confidence__c, ' +
            'Match_Method__c, Status__c, Unique_Key__c ' +
            'FROM Distributor_Product_Alias__c WHERE Id != null';
        if (!distCodes.isEmpty()) {
            soql += ' AND Distributor_Code__c IN :distCodes';
        }
        if (String.isNotBlank(statusFilter)) {
            soql += ' AND Status__c = :statusFilter';
        }
        if (unmappedOnly == true) {
            soql += ' AND (Product2_Id__c = null OR Status__c = \'Suggested\')';
        }
        if (String.isNotBlank(productLineFilter)) {
            if (productLineFilter == '__UNASSIGNED__') {
                soql +=
                    ' AND (Product2_Id__c = null OR Product2_Id__r.Family = null OR Product2_Id__r.Family = \'\')';
            } else {
                soql += ' AND Product2_Id__r.Family = :productLineFilter';
            }
        }
        String likeTerm;
        if (String.isNotBlank(searchTerm)) {
            likeTerm = '%' + searchTerm.trim() + '%';
            soql +=
                ' AND (Distributor_Item_Name__c LIKE :likeTerm OR Distributor_Item_Code__c LIKE :likeTerm' +
                ' OR Zeta_Code__c LIKE :likeTerm OR Product2_Id__r.Name LIKE :likeTerm' +
                ' OR Product2_Id__r.Family LIKE :likeTerm)';
        }
        soql +=
            ' ORDER BY Distributor_Code__c, Product2_Id__r.Family NULLS LAST, Distributor_Item_Name__c LIMIT :lim';

        List<ProductAliasRow> rows = new List<ProductAliasRow>();
        for (Distributor_Product_Alias__c a : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            rows.add(toProductRow(a));
        }
        return rows;
    }

    @AuraEnabled(cacheable=false)
    public static ProductMappingNav getProductMappingNav(
        String distributorCode,
        String statusFilter,
        Boolean unmappedOnly
    ) {
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distributorCode);
        String soql =
            'SELECT Distributor_Code__c, Product2_Id__r.Family ' +
            'FROM Distributor_Product_Alias__c WHERE Id != null';
        if (!distCodes.isEmpty()) {
            soql += ' AND Distributor_Code__c IN :distCodes';
        }
        if (String.isNotBlank(statusFilter)) {
            soql += ' AND Status__c = :statusFilter';
        }
        if (unmappedOnly == true) {
            soql += ' AND (Product2_Id__c = null OR Status__c = \'Suggested\')';
        }
        soql += ' LIMIT 10000';

        Map<String, Integer> byDist = new Map<String, Integer>();
        Map<String, Integer> byLine = new Map<String, Integer>();
        for (Distributor_Product_Alias__c a : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            String dist = String.isNotBlank(a.Distributor_Code__c)
                ? DistributorMatchingUtil.displayDistributorLabel(a.Distributor_Code__c)
                : 'Unknown';
            byDist.put(dist, (byDist.containsKey(dist) ? byDist.get(dist) : 0) + 1);
            String line =
                a.Product2_Id__r != null && String.isNotBlank(a.Product2_Id__r.Family)
                    ? a.Product2_Id__r.Family
                    : '__UNASSIGNED__';
            byLine.put(line, (byLine.containsKey(line) ? byLine.get(line) : 0) + 1);
        }

        ProductMappingNav nav = new ProductMappingNav();
        nav.distributors = toSortedNavGroups(byDist, false);
        nav.productLines = toSortedNavGroups(byLine, true);
        return nav;
    }

    @AuraEnabled
    public static ProductAliasRow updateProductAlias(
        Id aliasId,
        Id productId,
        String status,
        Decimal confidence
    ) {
        Distributor_Product_Alias__c alias = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Item_Code__c,
                Distributor_Item_Name__c,
                Product2_Id__c,
                Product2_Id__r.Name,
                Product2_Id__r.Family,
                Zeta_Code__c,
                Match_Confidence__c,
                Match_Method__c,
                Status__c,
                Unique_Key__c
            FROM Distributor_Product_Alias__c
            WHERE Id = :aliasId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (productId != null) {
            alias.Product2_Id__c = productId;
            List<Product2> products = [
                SELECT Id, External_ID__c, ProductCode, Name
                FROM Product2
                WHERE Id = :productId
            WITH SYSTEM_MODE
            LIMIT 1
            ];
            if (!products.isEmpty()) {
                alias.Zeta_Code__c = String.isNotBlank(products[0].External_ID__c)
                    ? products[0].External_ID__c
                    : products[0].ProductCode;
            }
        }
        if (String.isNotBlank(status)) {
            alias.Status__c = status;
        }
        alias.Match_Method__c = 'Manual';
        alias.Match_Confidence__c = confidence != null ? confidence : 100;
        Database.update(alias, AccessLevel.SYSTEM_MODE);
        alias = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Item_Code__c,
                Distributor_Item_Name__c,
                Product2_Id__c,
                Product2_Id__r.Name,
                Product2_Id__r.Family,
                Zeta_Code__c,
                Match_Confidence__c,
                Match_Method__c,
                Status__c,
                Unique_Key__c
            FROM Distributor_Product_Alias__c
            WHERE Id = :aliasId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return toProductRow(alias);
    }

    @AuraEnabled
    public static Integer saveProductAliasDrafts(String draftsJson) {
        if (String.isBlank(draftsJson)) {
            return 0;
        }
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(draftsJson);
        if (raw.isEmpty()) {
            return 0;
        }
        Set<Id> aliasIds = new Set<Id>();
        Set<String> zetaCodes = new Set<String>();
        for (Object o : raw) {
            Map<String, Object> d = (Map<String, Object>) o;
            String rid = String.valueOf(d.get('recordId'));
            if (String.isNotBlank(rid)) {
                aliasIds.add((Id) rid);
            }
            if (d.containsKey('zetaCode') && d.get('zetaCode') != null) {
                String zc = String.valueOf(d.get('zetaCode')).trim();
                if (String.isNotBlank(zc)) {
                    zetaCodes.add(zc);
                }
            }
        }
        Map<Id, Distributor_Product_Alias__c> existing = new Map<Id, Distributor_Product_Alias__c>(
            [
                SELECT
                    Id,
                    Distributor_Item_Name__c,
                    Product2_Id__c,
                    Zeta_Code__c,
                    Match_Confidence__c,
                    Match_Method__c,
                    Status__c
                FROM Distributor_Product_Alias__c
                WHERE Id IN :aliasIds
                WITH SYSTEM_MODE
            ]
        );
        Map<String, Id> productByCode = new Map<String, Id>();
        if (!zetaCodes.isEmpty()) {
            for (Product2 p : [
                SELECT Id, External_ID__c, ProductCode
                FROM Product2
                WHERE External_ID__c IN :zetaCodes OR ProductCode IN :zetaCodes
                WITH SYSTEM_MODE
            ]) {
                if (String.isNotBlank(p.External_ID__c)) {
                    productByCode.put(p.External_ID__c, p.Id);
                }
                if (String.isNotBlank(p.ProductCode)) {
                    productByCode.put(p.ProductCode, p.Id);
                }
            }
        }
        List<Distributor_Product_Alias__c> toUpdate = new List<Distributor_Product_Alias__c>();
        for (Object o : raw) {
            Map<String, Object> d = (Map<String, Object>) o;
            Id rid = (Id) String.valueOf(d.get('recordId'));
            Distributor_Product_Alias__c alias = existing.get(rid);
            if (alias == null) {
                continue;
            }
            Boolean dirty = false;
            if (d.containsKey('itemName')) {
                alias.Distributor_Item_Name__c = d.get('itemName') == null
                    ? null
                    : String.valueOf(d.get('itemName'));
                dirty = true;
            }
            if (d.containsKey('status') && d.get('status') != null) {
                String st = String.valueOf(d.get('status')).trim();
                if (st == 'Suggested' || st == 'Confirmed' || st == 'Rejected') {
                    alias.Status__c = st;
                    dirty = true;
                }
            }
            if (d.containsKey('confidence') && d.get('confidence') != null) {
                alias.Match_Confidence__c = Decimal.valueOf(String.valueOf(d.get('confidence')));
                dirty = true;
            }
            if (d.containsKey('zetaCode')) {
                String zc = d.get('zetaCode') == null ? null : String.valueOf(d.get('zetaCode')).trim();
                alias.Zeta_Code__c = zc;
                if (String.isNotBlank(zc) && productByCode.containsKey(zc)) {
                    alias.Product2_Id__c = productByCode.get(zc);
                } else if (String.isBlank(zc)) {
                    alias.Product2_Id__c = null;
                }
                dirty = true;
            }
            if (d.containsKey('productId') && d.get('productId') != null) {
                String pid = String.valueOf(d.get('productId')).trim();
                if (String.isNotBlank(pid)) {
                    alias.Product2_Id__c = (Id) pid;
                    dirty = true;
                }
            }
            if (dirty) {
                alias.Match_Method__c = 'Manual';
                toUpdate.add(alias);
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
        }
        return toUpdate.size();
    }

    @AuraEnabled
    public static Integer bulkConfirmProductAliases(Decimal minConfidence, String distributorCode) {
        Decimal threshold = minConfidence != null ? minConfidence : 90;
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distributorCode);
        String soql =
            'SELECT Id, Status__c FROM Distributor_Product_Alias__c ' +
            'WHERE Status__c = \'Suggested\' AND Product2_Id__c != null AND Match_Confidence__c >= :threshold';
        if (!distCodes.isEmpty()) {
            soql += ' AND Distributor_Code__c IN :distCodes';
        }
        soql += ' LIMIT 2000';
        List<Distributor_Product_Alias__c> rows = Database.query(soql, AccessLevel.SYSTEM_MODE);
        for (Distributor_Product_Alias__c a : rows) {
            a.Status__c = 'Confirmed';
        }
        if (!rows.isEmpty()) {
            Database.update(rows, AccessLevel.SYSTEM_MODE);
        }
        return rows.size();
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductOption> searchProducts(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '%' : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<ProductOption> options = new List<ProductOption>();
        for (Product2 p : [
            SELECT Id, Name, External_ID__c, ProductCode
            FROM Product2
            WHERE Name LIKE :term OR ProductCode LIKE :term OR External_ID__c LIKE :term
           
            ORDER BY Name
            LIMIT 50
        ]) {
            ProductOption o = new ProductOption();
            o.value = p.Id;
            o.zetaCode = String.isNotBlank(p.External_ID__c) ? p.External_ID__c : p.ProductCode;
            o.label = p.Name + (String.isNotBlank(o.zetaCode) ? ' (' + o.zetaCode + ')' : '');
            options.add(o);
        }
        return options;
    }

    // ---------- Sellout mapping ----------

    @AuraEnabled(cacheable=false)
    public static List<SelloutAliasRow> getSelloutAliases(
        String distributorCode,
        String statusFilter,
        Boolean needsReviewOnly,
        Integer limitSize
    ) {
        Integer lim = limitSize == null || limitSize <= 0 ? 500 : Math.min(limitSize, 2000);
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distributorCode);
        String soql =
            'SELECT Id, Distributor_Code__c, Distributor_Client_Code__c, Distributor_Client_Name__c, ' +
            'Address__c, Governorate__c, Brick_Code__c, Brick_Name__c, Latitude__c, Longitude__c, ' +
            'Geocode_Status__c, Geocode_Message__c, Pharmacy_Account__c, Pharmacy_Account__r.Name, Match_Confidence__c, ' +
            'Match_Method__c, Status__c, Unique_Key__c ' +
            'FROM Distributor_Sellout_Alias__c WHERE Id != null';
        if (!distCodes.isEmpty()) {
            soql += ' AND Distributor_Code__c IN :distCodes';
        }
        if (String.isNotBlank(statusFilter)) {
            soql += ' AND Status__c = :statusFilter';
        }
        if (needsReviewOnly == true) {
            soql += ' AND Status__c IN (\'Suggested\',\'Unmatched\')';
        }
        soql += ' ORDER BY Match_Confidence__c ASC NULLS FIRST, Distributor_Client_Name__c LIMIT :lim';

        List<SelloutAliasRow> rows = new List<SelloutAliasRow>();
        Set<Id> pharmacyIds = new Set<Id>();
        for (Distributor_Sellout_Alias__c a : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            SelloutAliasRow row = toSelloutRow(a);
            rows.add(row);
            if (a.Pharmacy_Account__c != null) {
                pharmacyIds.add(a.Pharmacy_Account__c);
            }
        }
        Map<Id, List<String>> linked = loadLinkedDistributors(pharmacyIds);
        for (SelloutAliasRow row : rows) {
            if (row.pharmacyId != null && linked.containsKey(row.pharmacyId)) {
                row.linkedDistributors = linked.get(row.pharmacyId);
            }
        }
        return rows;
    }

    @AuraEnabled
    public static SelloutAliasRow updateSelloutAlias(
        Id aliasId,
        Id pharmacyId,
        String status,
        Decimal confidence,
        Boolean createPharmacy
    ) {
        Distributor_Sellout_Alias__c alias = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Client_Code__c,
                Distributor_Client_Name__c,
                Address__c,
                Governorate__c,
                Brick_Code__c,
                Brick_Name__c,
                Latitude__c,
                Longitude__c,
                Geocode_Status__c,
                Geocode_Message__c,
                Pharmacy_Account__c,
                Match_Confidence__c,
                Match_Method__c,
                Status__c,
                Unique_Key__c
            FROM Distributor_Sellout_Alias__c
            WHERE Id = :aliasId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (createPharmacy == true && pharmacyId == null) {
            pharmacyId = createPharmacyAccount(alias);
        }
        if (pharmacyId != null) {
            alias.Pharmacy_Account__c = pharmacyId;
        }
        if (String.isNotBlank(status)) {
            alias.Status__c = status;
        } else if (pharmacyId != null) {
            alias.Status__c = 'Confirmed';
        }
        alias.Match_Method__c = 'Manual';
        alias.Match_Confidence__c = confidence != null ? confidence : 100;
        Database.update(alias, AccessLevel.SYSTEM_MODE);
        return getSelloutAliases(null, null, false, 1).isEmpty()
            ? reloadSellout(alias.Id)
            : reloadSellout(alias.Id);
    }

    @AuraEnabled
    public static Integer mergeSelloutAliases(Id sourceAliasId, Id targetPharmacyId) {
        if (sourceAliasId == null || targetPharmacyId == null) {
            throw new AuraHandledException('Source alias and target pharmacy are required.');
        }
        Distributor_Sellout_Alias__c alias = [
            SELECT Id, Pharmacy_Account__c, Status__c, Match_Method__c, Match_Confidence__c
            FROM Distributor_Sellout_Alias__c
            WHERE Id = :sourceAliasId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        alias.Pharmacy_Account__c = targetPharmacyId;
        alias.Status__c = 'Confirmed';
        alias.Match_Method__c = 'Manual';
        alias.Match_Confidence__c = 100;
        Database.update(alias, AccessLevel.SYSTEM_MODE);
        return 1;
    }

    @AuraEnabled(cacheable=true)
    public static List<PharmacyOption> searchPharmacies(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '%' : '%' + searchTerm.trim() + '%';
        Id pharmacyRtId = getPharmacyRecordTypeId();
        List<PharmacyOption> options = new List<PharmacyOption>();
        String soql =
            'SELECT Id, Name FROM Account WHERE Name LIKE :term';
        if (pharmacyRtId != null) {
            soql += ' AND RecordTypeId = :pharmacyRtId';
        }
        soql += ' ORDER BY Name LIMIT 50';
        for (Account a : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            PharmacyOption o = new PharmacyOption();
            o.value = a.Id;
            o.label = a.Name;
            options.add(o);
        }
        return options;
    }

    // ---------- Import ----------

    /**
     * Accepts a JSON array of normalized sales rows from client SheetJS adapters.
     * Expected keys: distributorCode, itemCode, itemName, clientCode, clientName,
     * address, governorate, brickCode, brickName, quantity, unitPrice, revenue, reportMonth (YYYY-MM-DD or YYYY-MM), transactionDate
     */
    @AuraEnabled
    public static ImportChunkResult ingestNormalizedRows(
        String distributorCode,
        String fileName,
        String reportMonth,
        String rowsJson,
        Id existingBatchId,
        Boolean finalize
    ) {
        if (String.isBlank(rowsJson)) {
            throw new AuraHandledException('No rows provided.');
        }
        List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(rowsJson);
        if (rawRows.size() > MAX_CHUNK) {
            throw new AuraHandledException('Chunk exceeds maximum of ' + MAX_CHUNK + ' rows.');
        }

        String distCode = DistributorMatchingUtil.normalizeDistributorCode(distributorCode);
        Date monthDate = parseMonth(reportMonth);

        Sales_Data_Import_Batch__c batch;
        if (existingBatchId != null) {
            batch = [
                SELECT Id, File_Name__c, Distributor_Code__c, Status__c, Aliases_Created__c, Needs_Review__c
                FROM Sales_Data_Import_Batch__c
                WHERE Id = :existingBatchId
            WITH SYSTEM_MODE
            LIMIT 1
            ];
        } else {
            batch = new Sales_Data_Import_Batch__c();
            batch.File_Name__c = String.isBlank(fileName) ? 'distributor.xlsx' : fileName;
            batch.Distributor_Code__c = distCode;
            batch.Status__c = 'Processing';
            batch.Report_Month__c = monthDate;
            batch.Aliases_Created__c = 0;
            batch.Needs_Review__c = 0;
            batch.Rows_Inserted__c = 0;
            batch.Rows_Updated__c = 0;
            batch.Rows_Failed__c = 0;
            Database.insert(batch, AccessLevel.SYSTEM_MODE);
        }

        Map<String, Id> productByZeta = loadProductIds();
        Map<String, Distributor_Product_Alias__c> existingProductAliases = loadProductAliases(distCode);
        Map<String, Distributor_Sellout_Alias__c> existingSellouts = loadSelloutAliases(distCode);
        List<Product2> allProducts = [
            SELECT Id, Name, External_ID__c, ProductCode
            FROM Product2
            WHERE IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 5000
        ];

        Map<String, Distributor_Product_Alias__c> productAliasUpserts = new Map<String, Distributor_Product_Alias__c>();
        Map<String, Distributor_Sellout_Alias__c> selloutAliasUpserts = new Map<String, Distributor_Sellout_Alias__c>();
        List<Map<String, Object>> stagingRows = new List<Map<String, Object>>();
        Integer failed = 0;

        for (Object raw : rawRows) {
            Map<String, Object> row = (Map<String, Object>) raw;
            String itemCode = DistributorMatchingUtil.normalizeCode(asString(row.get('itemCode')));
            String clientCode = DistributorMatchingUtil.normalizeCode(asString(row.get('clientCode')));
            if (String.isBlank(itemCode) || String.isBlank(clientCode)) {
                failed++;
                continue;
            }
            String itemName = asString(row.get('itemName'));
            String clientName = asString(row.get('clientName'));
            String pKey = DistributorMatchingUtil.buildProductUniqueKey(distCode, itemCode);
            String sKey = DistributorMatchingUtil.buildSelloutUniqueKey(distCode, clientCode);

            if (!existingProductAliases.containsKey(pKey) && !productAliasUpserts.containsKey(pKey)) {
                Distributor_Product_Alias__c pa = suggestProductAlias(
                    distCode,
                    itemCode,
                    itemName,
                    allProducts,
                    productByZeta
                );
                productAliasUpserts.put(pKey, pa);
            }

            if (!existingSellouts.containsKey(sKey) && !selloutAliasUpserts.containsKey(sKey)) {
                Distributor_Sellout_Alias__c sa = new Distributor_Sellout_Alias__c(
                    Distributor_Code__c = distCode,
                    Distributor_Client_Code__c = clientCode,
                    Distributor_Client_Name__c = clientName,
                    Address__c = asString(row.get('address')),
                    Governorate__c = asString(row.get('governorate')),
                    Brick_Code__c = asString(row.get('brickCode')),
                    Brick_Name__c = asString(row.get('brickName')),
                    Geocode_Status__c = 'Pending',
                    Status__c = 'Unmatched',
                    Unique_Key__c = sKey
                );
                selloutAliasUpserts.put(sKey, sa);
            } else if (existingSellouts.containsKey(sKey)) {
                // refresh address if blank
                Distributor_Sellout_Alias__c existing = existingSellouts.get(sKey);
                Boolean dirty = false;
                if (String.isBlank(existing.Address__c) && String.isNotBlank(asString(row.get('address')))) {
                    existing.Address__c = asString(row.get('address'));
                    dirty = true;
                }
                if (dirty) {
                    selloutAliasUpserts.put(sKey, existing);
                }
            }

            stagingRows.add(row);
        }

        Integer aliasesCreated = 0;
        Integer needsReview = 0;
        if (!productAliasUpserts.isEmpty()) {
            List<Distributor_Product_Alias__c> toUpsert = productAliasUpserts.values();
            Database.UpsertResult[] urs = Database.upsert(toUpsert, Distributor_Product_Alias__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < urs.size(); i++) {
                if (urs[i].isSuccess()) {
                    aliasesCreated++;
                    if (toUpsert[i].Status__c == 'Suggested') {
                        needsReview++;
                    }
                    existingProductAliases.put(toUpsert[i].Unique_Key__c, toUpsert[i]);
                } else {
                    failed++;
                }
            }
        }
        if (!selloutAliasUpserts.isEmpty()) {
            List<Distributor_Sellout_Alias__c> toUpsert = selloutAliasUpserts.values();
            // Cross-match against known sellouts before insert
            matchSellouts(toUpsert);
            Database.UpsertResult[] urs = Database.upsert(toUpsert, Distributor_Sellout_Alias__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < urs.size(); i++) {
                if (urs[i].isSuccess()) {
                    aliasesCreated++;
                    if (toUpsert[i].Status__c == 'Suggested' || toUpsert[i].Status__c == 'Unmatched') {
                        needsReview++;
                    }
                    existingSellouts.put(toUpsert[i].Unique_Key__c, toUpsert[i]);
                } else {
                    failed++;
                }
            }
        }

        // Persist staging payload on batch error log append (lightweight) ? full withdrawal in batch job
        String stagingKey = 'DIST_IMPORT_' + batch.Id;
        // Store rows for batch via ContentVersion JSON attachment
        appendStagingContent(batch.Id, stagingRows);

        batch.Aliases_Created__c = (batch.Aliases_Created__c == null ? 0 : batch.Aliases_Created__c) + aliasesCreated;
        batch.Needs_Review__c = (batch.Needs_Review__c == null ? 0 : batch.Needs_Review__c) + needsReview;
        batch.Rows_Failed__c = (batch.Rows_Failed__c == null ? 0 : batch.Rows_Failed__c) + failed;
        if (finalize == true) {
            batch.Status__c = 'Queued';
            Database.update(batch, AccessLevel.SYSTEM_MODE);
            // Nominatim requires ~1 req/sec; keep scope tiny when Google key is absent
            Integer scopeSize = DistributorGeocodeService.hasGoogleApiKey() ? 20 : 1;
            Database.executeBatch(new DistributorSalesImportBatch(batch.Id, true), scopeSize);
        } else {
            Database.update(batch, AccessLevel.SYSTEM_MODE);
        }

        ImportChunkResult result = new ImportChunkResult();
        result.batchId = batch.Id;
        result.productAliasesUpserted = productAliasUpserts.size();
        result.selloutAliasesUpserted = selloutAliasUpserts.size();
        result.rowsAccepted = stagingRows.size();
        result.rowsFailed = failed;
        result.jobEnqueued = finalize == true;
        result.message = finalize == true
            ? 'Import queued for processing.'
            : 'Chunk accepted. Send finalize=true after last chunk.';
        return result;
    }

    @AuraEnabled
    public static PreviewResolveResult previewMappingCoverage(String distributorCode, String rowsJson) {
        PreviewResolveResult result = new PreviewResolveResult();
        result.newProductSuggestions = new List<ProductAliasRow>();
        result.newSelloutSuggestions = new List<SelloutAliasRow>();
        if (String.isBlank(rowsJson)) {
            return result;
        }
        String distCode = DistributorMatchingUtil.normalizeDistributorCode(distributorCode);
        List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(rowsJson);
        Map<String, Distributor_Product_Alias__c> existingP = loadProductAliases(distCode);
        Map<String, Distributor_Sellout_Alias__c> existingS = loadSelloutAliases(distCode);
        Set<String> productKeys = new Set<String>();
        Set<String> selloutKeys = new Set<String>();
        Integer mappedP = 0;
        Integer mappedS = 0;
        Integer suggestedP = 0;

        for (Object raw : rawRows) {
            Map<String, Object> row = (Map<String, Object>) raw;
            String itemCode = DistributorMatchingUtil.normalizeCode(asString(row.get('itemCode')));
            String clientCode = DistributorMatchingUtil.normalizeCode(asString(row.get('clientCode')));
            if (String.isNotBlank(itemCode)) {
                productKeys.add(itemCode);
                String pk = DistributorMatchingUtil.buildProductUniqueKey(distCode, itemCode);
                if (existingP.containsKey(pk) && existingP.get(pk).Product2_Id__c != null) {
                    mappedP++;
                }
            }
            if (String.isNotBlank(clientCode)) {
                selloutKeys.add(clientCode);
                String sk = DistributorMatchingUtil.buildSelloutUniqueKey(distCode, clientCode);
                if (existingS.containsKey(sk) && existingS.get(sk).Pharmacy_Account__c != null) {
                    mappedS++;
                }
            }
        }
        result.distinctProducts = productKeys.size();
        result.distinctSellouts = selloutKeys.size();
        // mapped counts above counted per row occurrence ? recompute unique
        mappedP = 0;
        mappedS = 0;
        for (String ic : productKeys) {
            String pk = DistributorMatchingUtil.buildProductUniqueKey(distCode, ic);
            if (existingP.containsKey(pk) && existingP.get(pk).Status__c == 'Confirmed' && existingP.get(pk).Product2_Id__c != null) {
                mappedP++;
            } else if (existingP.containsKey(pk) && existingP.get(pk).Status__c == 'Suggested') {
                suggestedP++;
            }
        }
        for (String cc : selloutKeys) {
            String sk = DistributorMatchingUtil.buildSelloutUniqueKey(distCode, cc);
            if (existingS.containsKey(sk) && existingS.get(sk).Pharmacy_Account__c != null) {
                mappedS++;
            }
        }
        result.productsMapped = mappedP;
        result.selloutsMapped = mappedS;
        result.productsSuggested = suggestedP;
        return result;
    }

    @AuraEnabled
    public static List<BatchRow> getImportBatches(Integer limitSize) {
        Integer lim = limitSize == null || limitSize <= 0 ? 50 : Math.min(limitSize, 200);
        List<BatchRow> rows = new List<BatchRow>();
        String soql =
            'SELECT Id, File_Name__c, Distributor_Code__c, Status__c, CreatedDate, ' +
            'Rows_Inserted__c, Rows_Updated__c, Rows_Failed__c, Aliases_Created__c, Needs_Review__c, Error_Log__c ' +
            'FROM Sales_Data_Import_Batch__c ORDER BY CreatedDate DESC LIMIT :lim';
        for (Sales_Data_Import_Batch__c b : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            BatchRow row = new BatchRow();
            row.batchId = b.Id;
            row.fileName = b.File_Name__c;
            row.distributorCode = DistributorMatchingUtil.displayDistributorLabel(b.Distributor_Code__c);
            row.status = b.Status__c;
            row.createdDate = b.CreatedDate;
            row.rowsInserted = b.Rows_Inserted__c == null ? 0 : Integer.valueOf(b.Rows_Inserted__c);
            row.rowsUpdated = b.Rows_Updated__c == null ? 0 : Integer.valueOf(b.Rows_Updated__c);
            row.rowsFailed = b.Rows_Failed__c == null ? 0 : Integer.valueOf(b.Rows_Failed__c);
            row.aliasesCreated = b.Aliases_Created__c == null ? 0 : Integer.valueOf(b.Aliases_Created__c);
            row.needsReview = b.Needs_Review__c == null ? 0 : Integer.valueOf(b.Needs_Review__c);
            row.errorLog = b.Error_Log__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static SeedResultWrapper seedProductMapping() {
        DistributorProductMappingSeed.SeedResult seed = DistributorProductMappingSeed.seedFromStaticResources();
        SeedResultWrapper w = new SeedResultWrapper();
        w.productsUpserted = seed.productsUpserted;
        w.aliasesUpserted = seed.aliasesUpserted;
        w.aliasesSkipped = seed.aliasesSkipped;
        w.message = seed.message;
        return w;
    }

    public class SeedResultWrapper {
        @AuraEnabled public Integer productsUpserted;
        @AuraEnabled public Integer aliasesUpserted;
        @AuraEnabled public Integer aliasesSkipped;
        @AuraEnabled public String message;
    }

    // ---------- helpers ----------

    private static ProductAliasRow toProductRow(Distributor_Product_Alias__c a) {
        ProductAliasRow row = new ProductAliasRow();
        row.recordId = a.Id;
        row.distributorCode = DistributorMatchingUtil.displayDistributorLabel(a.Distributor_Code__c);
        row.itemName = a.Distributor_Item_Name__c;
        row.productId = a.Product2_Id__c;
        row.productName = a.Product2_Id__r != null ? a.Product2_Id__r.Name : null;
        row.productUrl = a.Product2_Id__c != null ? '/' + a.Product2_Id__c : null;
        row.productFamily =
            a.Product2_Id__r != null && String.isNotBlank(a.Product2_Id__r.Family)
                ? a.Product2_Id__r.Family
                : null;
        row.zetaCode = a.Zeta_Code__c;
        row.confidence = a.Match_Confidence__c;
        row.matchMethod = a.Match_Method__c;
        row.status = a.Status__c;
        row.uniqueKey = a.Unique_Key__c;
        return row;
    }

    private static List<NavGroup> toSortedNavGroups(Map<String, Integer> counts, Boolean unassignedLabel) {
        List<String> keys = new List<String>(counts.keySet());
        keys.sort();
        List<NavGroup> groups = new List<NavGroup>();
        for (String key : keys) {
            NavGroup g = new NavGroup();
            g.key = key;
            if (unassignedLabel == true && key == '__UNASSIGNED__') {
                g.label = 'Unassigned / unmapped';
            } else {
                g.label = DistributorMatchingUtil.displayDistributorLabel(key);
            }
            g.count = counts.get(key);
            groups.add(g);
        }
        return groups;
    }

    private static SelloutAliasRow toSelloutRow(Distributor_Sellout_Alias__c a) {
        SelloutAliasRow row = new SelloutAliasRow();
        row.recordId = a.Id;
        row.recordUrl = a.Id != null ? '/' + a.Id : null;
        row.distributorCode = DistributorMatchingUtil.displayDistributorLabel(a.Distributor_Code__c);
        row.clientCode = a.Distributor_Client_Code__c;
        row.clientName = a.Distributor_Client_Name__c;
        row.address = a.Address__c;
        row.governorate = a.Governorate__c;
        row.brickCode = a.Brick_Code__c;
        row.brickName = a.Brick_Name__c;
        row.latitude = a.Latitude__c;
        row.longitude = a.Longitude__c;
        row.geocodeStatus = a.Geocode_Status__c;
        row.geocodeMessage = resolveGeocodeMessage(a);
        row.geocodeRecommendation = DistributorGeocodeService.recommendationForStatus(
            a.Geocode_Status__c,
            row.geocodeMessage
        );
        // Prefer recommendation stored after "Recommendation:" in message body
        if (String.isNotBlank(a.Geocode_Message__c) && a.Geocode_Message__c.contains('Recommendation:')) {
            Integer idx = a.Geocode_Message__c.indexOf('Recommendation:');
            row.geocodeRecommendation = a.Geocode_Message__c.substring(idx + 'Recommendation:'.length()).trim();
            String reasonOnly = a.Geocode_Message__c.substring(0, idx).trim();
            if (String.isNotBlank(reasonOnly)) {
                row.geocodeMessage = reasonOnly;
            }
        }
        row.pharmacyId = a.Pharmacy_Account__c;
        row.pharmacyName = a.Pharmacy_Account__r != null ? a.Pharmacy_Account__r.Name : null;
        row.pharmacyUrl = a.Pharmacy_Account__c != null ? '/' + a.Pharmacy_Account__c : null;
        row.confidence = a.Match_Confidence__c;
        row.matchMethod = a.Match_Method__c;
        row.status = a.Status__c;
        row.uniqueKey = a.Unique_Key__c;
        row.linkedDistributors = new List<String>();
        return row;
    }

    private static String resolveGeocodeMessage(Distributor_Sellout_Alias__c a) {
        if (String.isNotBlank(a.Geocode_Message__c)) {
            return a.Geocode_Message__c;
        }
        if (a.Geocode_Status__c == 'Failed') {
            return 'No coordinates returned for this address (provider could not resolve street/locality).';
        }
        if (a.Geocode_Status__c == 'Skipped') {
            return 'Geocode skipped — address/governorate missing.';
        }
        if (a.Geocode_Status__c == 'Pending') {
            return 'Geocode pending — waiting for import batch.';
        }
        return null;
    }

    private static SelloutAliasRow reloadSellout(Id aliasId) {
        Distributor_Sellout_Alias__c a = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Client_Code__c,
                Distributor_Client_Name__c,
                Address__c,
                Governorate__c,
                Brick_Code__c,
                Brick_Name__c,
                Latitude__c,
                Longitude__c,
                Geocode_Status__c,
                Geocode_Message__c,
                Pharmacy_Account__c,
                Pharmacy_Account__r.Name,
                Match_Confidence__c,
                Match_Method__c,
                Status__c,
                Unique_Key__c
            FROM Distributor_Sellout_Alias__c
            WHERE Id = :aliasId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        SelloutAliasRow row = toSelloutRow(a);
        if (a.Pharmacy_Account__c != null) {
            Map<Id, List<String>> linked = loadLinkedDistributors(new Set<Id>{ a.Pharmacy_Account__c });
            row.linkedDistributors = linked.get(a.Pharmacy_Account__c);
        }
        return row;
    }

    private static Map<Id, List<String>> loadLinkedDistributors(Set<Id> pharmacyIds) {
        Map<Id, List<String>> result = new Map<Id, List<String>>();
        if (pharmacyIds == null || pharmacyIds.isEmpty()) {
            return result;
        }
        for (Distributor_Sellout_Alias__c a : [
            SELECT Pharmacy_Account__c, Distributor_Code__c
            FROM Distributor_Sellout_Alias__c
            WHERE Pharmacy_Account__c IN :pharmacyIds
            WITH SYSTEM_MODE
        ]) {
            if (!result.containsKey(a.Pharmacy_Account__c)) {
                result.put(a.Pharmacy_Account__c, new List<String>());
            }
            String label = DistributorMatchingUtil.displayDistributorLabel(a.Distributor_Code__c);
            if (!result.get(a.Pharmacy_Account__c).contains(label)) {
                result.get(a.Pharmacy_Account__c).add(label);
            }
        }
        return result;
    }

    private static Distributor_Product_Alias__c suggestProductAlias(
        String distCode,
        String itemCode,
        String itemName,
        List<Product2> products,
        Map<String, Id> productByZeta
    ) {
        Distributor_Product_Alias__c alias = new Distributor_Product_Alias__c(
            Distributor_Code__c = distCode,
            Distributor_Item_Code__c = itemCode,
            Distributor_Item_Name__c = itemName,
            Unique_Key__c = DistributorMatchingUtil.buildProductUniqueKey(distCode, itemCode),
            Status__c = 'Suggested',
            Match_Method__c = 'FuzzyName',
            Match_Confidence__c = 0
        );
        Decimal best = 0;
        Product2 bestProduct;
        for (Product2 p : products) {
            Decimal score = DistributorMatchingUtil.nameSimilarity(itemName, p.Name);
            if (score > best) {
                best = score;
                bestProduct = p;
            }
        }
        if (bestProduct != null && best >= 40) {
            alias.Product2_Id__c = bestProduct.Id;
            alias.Zeta_Code__c = String.isNotBlank(bestProduct.External_ID__c)
                ? bestProduct.External_ID__c
                : bestProduct.ProductCode;
            alias.Match_Confidence__c = best;
            if (best >= DistributorMatchingUtil.autoConfirmThreshold()) {
                alias.Status__c = 'Confirmed';
                alias.Match_Method__c = best >= 99 ? 'ExactCode' : 'FuzzyName';
            }
        }
        return alias;
    }

    private static void matchSellouts(List<Distributor_Sellout_Alias__c> candidates) {
        if (candidates == null || candidates.isEmpty()) {
            return;
        }
        List<Distributor_Sellout_Alias__c> known = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Client_Name__c,
                Brick_Code__c,
                Latitude__c,
                Longitude__c,
                Pharmacy_Account__c,
                Status__c
            FROM Distributor_Sellout_Alias__c
            WHERE Pharmacy_Account__c != NULL AND Status__c IN ('Confirmed', 'Suggested')
            WITH SYSTEM_MODE
            LIMIT 5000
        ];
        Decimal prox = DistributorMatchingUtil.proximityMeters();
        Decimal threshold = DistributorMatchingUtil.autoConfirmThreshold();
        for (Distributor_Sellout_Alias__c cand : candidates) {
            if (cand.Pharmacy_Account__c != null) {
                continue;
            }
            Decimal bestScore = 0;
            Distributor_Sellout_Alias__c best;
            String method;
            for (Distributor_Sellout_Alias__c k : known) {
                if (k.Distributor_Code__c == cand.Distributor_Code__c) {
                    continue;
                }
                Decimal score = 0;
                String m = 'FuzzyName';
                if (
                    String.isNotBlank(cand.Brick_Code__c) &&
                    String.isNotBlank(k.Brick_Code__c) &&
                    cand.Brick_Code__c.trim() == k.Brick_Code__c.trim()
                ) {
                    Decimal nameScore = DistributorMatchingUtil.nameSimilarity(
                        cand.Distributor_Client_Name__c,
                        k.Distributor_Client_Name__c
                    );
                    score = Math.max(nameScore, 70);
                    m = 'BrickCode';
                }
                Decimal nameOnly = DistributorMatchingUtil.nameSimilarity(
                    cand.Distributor_Client_Name__c,
                    k.Distributor_Client_Name__c
                );
                if (nameOnly > score) {
                    score = nameOnly;
                    m = 'FuzzyName';
                }
                if (cand.Latitude__c != null && k.Latitude__c != null) {
                    Decimal meters = DistributorMatchingUtil.haversineMeters(
                        cand.Latitude__c,
                        cand.Longitude__c,
                        k.Latitude__c,
                        k.Longitude__c
                    );
                    if (meters != null && meters <= prox) {
                        Decimal geoScore = 60 + (nameOnly * 0.4);
                        if (geoScore > score) {
                            score = geoScore;
                            m = 'GeoProximity+Name';
                        }
                    }
                }
                if (score > bestScore) {
                    bestScore = score;
                    best = k;
                    method = m;
                }
            }
            if (best != null && bestScore >= 50) {
                cand.Pharmacy_Account__c = best.Pharmacy_Account__c;
                cand.Match_Confidence__c = bestScore;
                cand.Match_Method__c = method;
                cand.Status__c = bestScore >= threshold ? 'Confirmed' : 'Suggested';
            }
        }
    }

    private static Id createPharmacyAccount(Distributor_Sellout_Alias__c alias) {
        Account a = new Account();
        a.Name = String.isNotBlank(alias.Distributor_Client_Name__c)
            ? alias.Distributor_Client_Name__c
            : alias.Distributor_Client_Code__c;
        Id rtId = getPharmacyRecordTypeId();
        if (rtId != null) {
            a.RecordTypeId = rtId;
        }
        if (String.isNotBlank(alias.Address__c)) {
            a.BillingStreet = alias.Address__c.left(255);
        }
        if (String.isNotBlank(alias.Governorate__c)) {
            a.BillingState = alias.Governorate__c.left(80);
        }
        a.BillingCountry = 'Egypt';
        if (alias.Latitude__c != null && alias.Longitude__c != null) {
            a.BillingLatitude = alias.Latitude__c;
            a.BillingLongitude = alias.Longitude__c;
        }
        if (Schema.SObjectType.Account.fields.getMap().containsKey('External_ID__c') &&
            Schema.SObjectType.Account.fields.getMap().get('External_ID__c').getDescribe().isCreateable()) {
            a.put(
                'External_ID__c',
                ('DIST_' + alias.Distributor_Code__c + '_' + alias.Distributor_Client_Code__c).left(80)
            );
        }
        Database.insert(a, AccessLevel.SYSTEM_MODE);
        return a.Id;
    }

    private static Id getPharmacyRecordTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && info.getDeveloperName() == 'Pharmacy') {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    private static Map<String, Id> loadProductIds() {
        Map<String, Id> m = new Map<String, Id>();
        for (Product2 p : [
            SELECT Id, External_ID__c, ProductCode
            FROM Product2
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            if (String.isNotBlank(p.External_ID__c)) {
                m.put(p.External_ID__c, p.Id);
            }
            if (String.isNotBlank(p.ProductCode)) {
                m.put(p.ProductCode, p.Id);
            }
        }
        return m;
    }

    private static Map<String, Distributor_Product_Alias__c> loadProductAliases(String distCode) {
        Map<String, Distributor_Product_Alias__c> m = new Map<String, Distributor_Product_Alias__c>();
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distCode);
        for (Distributor_Product_Alias__c a : [
            SELECT
                Id,
                Unique_Key__c,
                Product2_Id__c,
                Status__c,
                Distributor_Code__c,
                Distributor_Item_Code__c,
                Distributor_Item_Name__c,
                Zeta_Code__c,
                Match_Confidence__c
            FROM Distributor_Product_Alias__c
            WHERE Distributor_Code__c IN :distCodes
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            m.put(a.Unique_Key__c, a);
            String canonicalKey = DistributorMatchingUtil.buildProductUniqueKey(
                distCode,
                a.Distributor_Item_Code__c
            );
            m.put(canonicalKey, a);
        }
        return m;
    }

    private static Map<String, Distributor_Sellout_Alias__c> loadSelloutAliases(String distCode) {
        Map<String, Distributor_Sellout_Alias__c> m = new Map<String, Distributor_Sellout_Alias__c>();
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distCode);
        for (Distributor_Sellout_Alias__c a : [
            SELECT
                Id,
                Unique_Key__c,
                Pharmacy_Account__c,
                Status__c,
                Address__c,
                Distributor_Code__c,
                Distributor_Client_Code__c,
                Distributor_Client_Name__c,
                Brick_Code__c,
                Latitude__c,
                Longitude__c
            FROM Distributor_Sellout_Alias__c
            WHERE Distributor_Code__c IN :distCodes
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            m.put(a.Unique_Key__c, a);
            String canonicalKey = DistributorMatchingUtil.buildSelloutUniqueKey(
                distCode,
                a.Distributor_Client_Code__c
            );
            m.put(canonicalKey, a);
        }
        return m;
    }

    private static void appendStagingContent(Id batchId, List<Map<String, Object>> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        String title = 'DistributorImport_' + batchId;
        List<ContentVersion> existing = [
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE Title = :title AND IsLatest = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        List<Object> combined = new List<Object>();
        if (!existing.isEmpty() && existing[0].VersionData != null) {
            try {
                Object parsed = JSON.deserializeUntyped(existing[0].VersionData.toString());
                if (parsed instanceof List<Object>) {
                    combined.addAll((List<Object>) parsed);
                }
            } catch (Exception e) {
                // start fresh
            }
        }
        combined.addAll(rows);
        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = title + '.json';
        cv.VersionData = Blob.valueOf(JSON.serialize(combined));
        if (!existing.isEmpty()) {
            // new version via ContentDocument
            List<ContentVersion> cvWithDoc = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :existing[0].Id
            WITH SYSTEM_MODE
            LIMIT 1
            ];
            if (!cvWithDoc.isEmpty()) {
                cv.ContentDocumentId = cvWithDoc[0].ContentDocumentId;
            }
        }
        Database.insert(cv, AccessLevel.SYSTEM_MODE);
        // link ContentVersion Id onto batch
        Sales_Data_Import_Batch__c b = new Sales_Data_Import_Batch__c(Id = batchId);
        List<ContentVersion> latest = [
            SELECT Id
            FROM ContentVersion
            WHERE Title = :title AND IsLatest = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!latest.isEmpty()) {
            b.ContentVersion_Id__c = latest[0].Id;
            Database.update(b, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Date parseMonth(String reportMonth) {
        if (String.isBlank(reportMonth)) {
            Date today = Date.today();
            return Date.newInstance(today.year(), today.month(), 1);
        }
        String s = reportMonth.trim();
        if (s.length() >= 7) {
            Integer y = Integer.valueOf(s.substring(0, 4));
            Integer m = Integer.valueOf(s.substring(5, 7));
            return Date.newInstance(y, m, 1);
        }
        return Date.today().toStartOfMonth();
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o).trim();
    }
}