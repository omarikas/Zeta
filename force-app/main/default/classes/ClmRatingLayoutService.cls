public with sharing class ClmRatingLayoutService {

    public class RatingSaveException extends Exception {
    }

    public class CatalogField {
        @AuraEnabled public String sectionKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public String widget;
        @AuraEnabled public Boolean readOnly;
        @AuraEnabled public List<Map<String, String>> options;
    }

    public class SectionCounts {
        public Integer accountCount;
        public Integer territoryCount;
        public Integer productCount;
    }

    public class VisitRatingContext {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Id product2Id;
        @AuraEnabled public Id layoutId;
        @AuraEnabled public String layoutJson;
        @AuraEnabled public String valuesJson;
        @AuraEnabled public String accountVariant;
        @AuraEnabled public List<ProductRatingRow> alignedProducts;
    }

    public class ProductRatingRow {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String valuesJson;
    }

    public class ProductRatingSaveInput {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public List<VisitRatingFieldInput> values;
    }

    public class VisitRatingFieldInput {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String valueJson;
    }

    private static final Set<String> ACCOUNT_FIELDS = new Set<String>{
        'Rating', 'AnnualRevenue', 'NumberOfEmployees'
    };

    public static final String VARIANT_HCP = 'HCP';
    public static final String VARIANT_HCO = 'HCO';

    private static final Set<String> HCO_RECORD_TYPES = new Set<String>{
        'Institution_HCO',
        'Pharmacy'
    };

    private static final Set<String> ATF_FIELDS = new Set<String>{
        'Is_KOL__c', 'KOL_In_What__c', 'Has_KOLs__c', 'KOL_Profile__c', 'Is_Speaker__c',
        'HCP_Classification__c', 'Potential__c', 'Penetration__c', 'Matrix_Rating__c',
        'Classification__c', 'Is_Active__c'
    };

    private static final Set<String> KOL_REASON_VALUES = new Set<String>{
        'High Prescriber',
        'Key Scientific Leader'
    };

    private static final Set<String> HCO_KOL_PROFILE_VALUES = new Set<String>{
        'Multiple High Prescribers',
        'Department Chiefs',
        'Academic Leaders',
        'Mixed Influencers'
    };

    private static final Set<String> ATPF_FIELDS = new Set<String>{
        'Potential__c', 'Penetration__c', 'Rx_Per_Week__c', 'Adoption__c', 'Loyalty__c',
        'Product_Matrix_Rating__c', 'Target_Visit_Frequency__c', 'Notes__c', 'Is_Active__c'
    };

    private static final List<String> HCP_CLASSIFICATION_VALUES = new List<String>{
        'A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'
    };

    public static String normalizeFieldsJson(String fieldsJson) {
        return normalizeFieldsJson(fieldsJson, VARIANT_HCP);
    }

    public static String normalizeFieldsJson(String fieldsJson, String accountVariant) {
        if (String.isBlank(fieldsJson)) {
            return VARIANT_HCO.equals(accountVariant) ? defaultHcoLayoutJson() : defaultLayoutJson();
        }
        try {
            Object parsed = JSON.deserializeUntyped(fieldsJson);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> mapValue = (Map<String, Object>) parsed;
                if (mapValue.containsKey('version') && mapValue.containsKey('sections')) {
                    patchKnownFieldDefinitions(mapValue, accountVariant);
                    return JSON.serialize(mapValue);
                }
                if (mapValue.containsKey('fields')) {
                    return migrateLegacyFields((List<Object>) mapValue.get('fields'));
                }
            }
            if (parsed instanceof List<Object>) {
                return migrateLegacyFields((List<Object>) parsed);
            }
        } catch (Exception ex) {
            // fall through to default
        }
        return VARIANT_HCO.equals(accountVariant) ? defaultHcoLayoutJson() : defaultLayoutJson();
    }

    public static SectionCounts countSections(String fieldsJson) {
        SectionCounts counts = new SectionCounts();
        counts.accountCount = 0;
        counts.territoryCount = 0;
        counts.productCount = 0;
        try {
            Map<String, Object> layout = (Map<String, Object>) JSON.deserializeUntyped(normalizeFieldsJson(fieldsJson));
            Map<String, Object> sections = (Map<String, Object>) layout.get('sections');
            if (sections == null) {
                return counts;
            }
            counts.accountCount = sectionSize(sections, 'account');
            counts.territoryCount = sectionSize(sections, 'accountTerritory');
            counts.productCount = sectionSize(sections, 'accountTerritoryProduct');
        } catch (Exception ex) {
            // keep zeros
        }
        return counts;
    }

    public static List<CatalogField> getFieldCatalog() {
        List<CatalogField> catalog = new List<CatalogField>();
        catalog.addAll(describeSection('account', 'Account', ACCOUNT_FIELDS));
        catalog.addAll(describeSection('accountTerritory', 'Account_Territory_Fields__c', ATF_FIELDS));
        catalog.addAll(describeSection('accountTerritoryProduct', 'Account_Territory_Product_Fields__c', ATPF_FIELDS));
        return catalog;
    }

    public static String getPreviewSampleValuesJson() {
        Map<String, Object> sample = new Map<String, Object>{
            'HCP_Classification__c' => 'A1',
            'Is_Speaker__c' => false,
            'Is_KOL__c' => true,
            'KOL_In_What__c' => 'High Prescriber',
            'Potential__c' => 100,
            'Penetration__c' => 50,
            'Matrix_Rating__c' => 'a1',
            'Classification__c' => 'A',
            'Rx_Per_Week__c' => 10,
            'Adoption__c' => 'M',
            'Loyalty__c' => 'M',
            'Product_Matrix_Rating__c' => 'mm',
            'Target_Visit_Frequency__c' => 'Monthly',
            'Rating' => 'Hot',
            'AnnualRevenue' => 0,
            'NumberOfEmployees' => 0
        };
        return JSON.serialize(sample);
    }

    public static VisitRatingContext buildCaptureContext(Id visitId, Id sessionId) {
        VisitRatingContext context = new VisitRatingContext();
        if (visitId == null) {
            return context;
        }

        Visit__c visit = [
            SELECT Id, Account__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        return buildAccountCaptureContext(visit.Account__c, getSessionProductId(sessionId));
    }

    public static VisitRatingContext buildAccountCaptureContext(Id accountId) {
        return buildAccountCaptureContext(accountId, null);
    }

    public static VisitRatingContext buildAccountCaptureContext(Id accountId, Id product2Id) {
        VisitRatingContext context = new VisitRatingContext();
        if (accountId == null) {
            return context;
        }

        context.accountId = accountId;
        context.territory2Id = resolveTerritoryForAccount(accountId);
        context.territoryName = getTerritoryName(context.territory2Id);
        context.product2Id = product2Id;
        context.alignedProducts = new List<ProductRatingRow>();
        context.accountVariant = resolveAccountVariant(accountId);

        CLM_Rating_Layout__c layout = resolveDeployedLayout(context.accountVariant);
        if (layout != null) {
            context.layoutId = layout.Id;
            context.layoutJson = normalizeFieldsJson(layout.Fields_JSON__c, context.accountVariant);
        } else {
            context.layoutJson = VARIANT_HCO.equals(context.accountVariant)
                ? defaultHcoLayoutJson()
                : defaultLayoutJson();
        }

        if (product2Id != null) {
            context.valuesJson = JSON.serialize(
                loadTerritoryValues(context.accountId, context.territory2Id)
            );
            context.alignedProducts = buildSingleProductRatingRow(
                context.accountId,
                context.territory2Id,
                product2Id
            );
            return context;
        }

        Map<String, Object> territoryValues = loadTerritoryValues(context.accountId, context.territory2Id);
        context.valuesJson = JSON.serialize(territoryValues);
        context.alignedProducts = getAlignedTerritoryProducts(context.accountId, context.territory2Id);
        return context;
    }

    public static void saveAccountRatings(
        Id accountId,
        Id layoutId,
        List<VisitRatingFieldInput> values
    ) {
        saveAccountRatings(accountId, layoutId, values, null);
    }

    public static void saveAccountRatings(
        Id accountId,
        Id layoutId,
        List<VisitRatingFieldInput> values,
        List<ProductRatingSaveInput> productRatings
    ) {
        saveAccountRatings(accountId, layoutId, null, values, productRatings);
    }

    public static void saveAccountRatings(
        Id accountId,
        Id layoutId,
        Id territory2Id,
        List<VisitRatingFieldInput> values,
        List<ProductRatingSaveInput> productRatings
    ) {
        if (accountId == null) {
            throw new RatingSaveException('Account is required to save ratings.');
        }
        if ((values == null || values.isEmpty()) && (productRatings == null || productRatings.isEmpty())) {
            throw new RatingSaveException('No rating values were provided.');
        }

        Id effectiveTerritory2Id = territory2Id != null ? territory2Id : resolveTerritoryForAccount(accountId);

        VisitRatingContext context = buildAccountCaptureContext(accountId);
        if (effectiveTerritory2Id != null) {
            context.territory2Id = effectiveTerritory2Id;
            context.territoryName = getTerritoryName(effectiveTerritory2Id);
        }
        persistRatingValues(context, layoutId, values != null ? values : new List<VisitRatingFieldInput>(), null);

        if (productRatings != null && !productRatings.isEmpty()) {
            for (ProductRatingSaveInput productInput : productRatings) {
                if (productInput == null || productInput.product2Id == null || productInput.values == null) {
                    continue;
                }
                VisitRatingContext productContext = buildAccountCaptureContext(accountId);
                if (effectiveTerritory2Id != null) {
                    productContext.territory2Id = effectiveTerritory2Id;
                    productContext.territoryName = getTerritoryName(effectiveTerritory2Id);
                }
                productContext.product2Id = productInput.product2Id;
                persistRatingValues(
                    productContext,
                    layoutId,
                    productInput.values,
                    null
                );
            }
        }
    }

    public static VisitRatingContext buildAccountCaptureContextAfterSave(Id accountId, Id territory2Id) {
        VisitRatingContext context = buildAccountCaptureContext(accountId);
        Id effectiveTerritory2Id = territory2Id != null ? territory2Id : context.territory2Id;
        if (effectiveTerritory2Id != null) {
            context.territory2Id = effectiveTerritory2Id;
            context.territoryName = getTerritoryName(effectiveTerritory2Id);
            Map<String, Object> territoryValues = loadTerritoryValues(context.accountId, effectiveTerritory2Id);
            context.valuesJson = JSON.serialize(territoryValues);
            context.alignedProducts = getAlignedTerritoryProducts(context.accountId, effectiveTerritory2Id);
        }
        return context;
    }

    private static Map<String, Object> loadTerritoryValues(Id accountId, Id territory2Id) {
        Map<String, Object> values = new Map<String, Object>();
        if (accountId != null) {
            putAccountFieldIfPresent(values, accountId, 'Rating');
            putAccountFieldIfPresent(values, accountId, 'AnnualRevenue');
            putAccountFieldIfPresent(values, accountId, 'NumberOfEmployees');
            putAccountFieldIfPresent(values, accountId, 'SDO_Value__c');
            putAccountFieldIfPresent(values, accountId, 'SDO_Account_Priority__c');
            putAccountFieldIfPresent(values, accountId, 'SDO_Days_Since_Activity__c');
            putAccountFieldIfPresent(values, accountId, 'SDO_Sales_Rating_Indicator__c');
        }
        if (accountId != null && territory2Id != null) {
            List<Account_Territory_Fields__c> atfRows = [
                SELECT
                    Is_KOL__c,
                    KOL_In_What__c,
                    Has_KOLs__c,
                    KOL_Profile__c,
                    Is_Speaker__c,
                    HCP_Classification__c,
                    Potential__c,
                    Penetration__c,
                    Matrix_Rating__c,
                    Classification__c
                FROM Account_Territory_Fields__c
                WHERE Account__c = :accountId AND Territory2_Id__c = :String.valueOf(territory2Id)
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!atfRows.isEmpty()) {
                Account_Territory_Fields__c atf = atfRows[0];
                values.put('Is_KOL__c', atf.Is_KOL__c);
                values.put('KOL_In_What__c', atf.KOL_In_What__c);
                values.put('Has_KOLs__c', atf.Has_KOLs__c);
                values.put('KOL_Profile__c', atf.KOL_Profile__c);
                values.put('Is_Speaker__c', atf.Is_Speaker__c);
                values.put('HCP_Classification__c', atf.HCP_Classification__c);
                values.put('Potential__c', atf.Potential__c);
                values.put('Penetration__c', atf.Penetration__c);
                values.put('Matrix_Rating__c', atf.Matrix_Rating__c);
                values.put('Classification__c', atf.Classification__c);
            }
        }
        return values;
    }

    private static List<ProductRatingRow> getAlignedTerritoryProducts(Id accountId, Id territory2Id) {
        List<ProductRatingRow> rows = new List<ProductRatingRow>();
        if (territory2Id == null) {
            return rows;
        }

        Set<Id> productIds = getPtaProductIdsForTerritory(territory2Id);
        productIds.addAll(getAtpfProductIdsForAccount(accountId, territory2Id));
        if (productIds.isEmpty()) {
            return rows;
        }

        Map<Id, Account_Territory_Product_Fields__c> atpfByProduct = getAtpfByProductForTerritory(
            accountId,
            territory2Id,
            productIds
        );

        for (Product2 product : queryProductsByIds(productIds)) {
            ProductRatingRow row = new ProductRatingRow();
            row.product2Id = product.Id;
            row.productName = product.Name;
            row.imageUrl = getProductImageUrl(product);
            row.valuesJson = JSON.serialize(
                buildAtpfValuesMap(atpfByProduct.get(product.Id))
            );
            rows.add(row);
        }
        return rows;
    }

    private static List<ProductRatingRow> buildSingleProductRatingRow(
        Id accountId,
        Id territory2Id,
        Id product2Id
    ) {
        List<ProductRatingRow> rows = new List<ProductRatingRow>();
        if (product2Id == null) {
            return rows;
        }

        List<Product2> products = queryProductsByIds(new Set<Id>{ product2Id });
        if (products.isEmpty()) {
            return rows;
        }

        Product2 product = products[0];
        Map<Id, Account_Territory_Product_Fields__c> atpfByProduct = getAtpfByProductForTerritory(
            accountId,
            territory2Id,
            new Set<Id>{ product2Id }
        );

        ProductRatingRow row = new ProductRatingRow();
        row.product2Id = product.Id;
        row.productName = product.Name;
        row.imageUrl = getProductImageUrl(product);
        row.valuesJson = JSON.serialize(
            buildAtpfValuesMap(atpfByProduct.get(product.Id))
        );
        rows.add(row);
        return rows;
    }

    private static Boolean productImageUrlReadable;

    private static Boolean isProductImageUrlReadable() {
        if (productImageUrlReadable == null) {
            Map<String, Schema.SObjectField> fieldMap = Product2.SObjectType.getDescribe().fields.getMap();
            productImageUrlReadable = fieldMap.containsKey('Product_Image_URL__c')
                && fieldMap.get('Product_Image_URL__c').getDescribe().isAccessible();
        }
        return productImageUrlReadable;
    }

    private static String getProductImageUrl(Product2 product) {
        return isProductImageUrlReadable() ? (String) product.get('Product_Image_URL__c') : null;
    }

    private static List<Product2> queryProductsByIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }
        String soql = isProductImageUrlReadable()
            ? 'SELECT Id, Name, Product_Image_URL__c FROM Product2 WHERE Id IN :productIds AND IsActive = TRUE WITH USER_MODE ORDER BY Name ASC'
            : 'SELECT Id, Name FROM Product2 WHERE Id IN :productIds AND IsActive = TRUE WITH USER_MODE ORDER BY Name ASC';
        return Database.query(soql);
    }

    private static Set<Id> getPtaProductIdsForTerritory(Id territory2Id) {
        Set<Id> productIds = new Set<Id>();
        Date today = Date.today();
        for (Product_Territory_Alignment__c alignment : [
            SELECT Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE
                Territory2_Id__c = :String.valueOf(territory2Id)
                AND Product2_Id__c != NULL
                AND Is_Active__c = TRUE
                AND (Effective_Start_Date__c = NULL OR Effective_Start_Date__c <= :today)
                AND (Effective_End_Date__c = NULL OR Effective_End_Date__c >= :today)
            WITH USER_MODE
        ]) {
            try {
                productIds.add((Id) alignment.Product2_Id__c);
            } catch (Exception ex) {
                // Skip invalid ids.
            }
        }
        return productIds;
    }

    private static Set<Id> getAtpfProductIdsForAccount(Id accountId, Id territory2Id) {
        Set<Id> productIds = new Set<Id>();
        if (accountId == null || territory2Id == null) {
            return productIds;
        }
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT Product2_Id__c
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :accountId
                AND Territory2_Id__c = :String.valueOf(territory2Id)
                AND Is_Active__c = TRUE
                AND Product2_Id__c != NULL
            WITH USER_MODE
        ]) {
            try {
                productIds.add((Id) atpf.Product2_Id__c);
            } catch (Exception ex) {
                // Skip invalid ids.
            }
        }
        return productIds;
    }

    private static Map<Id, Account_Territory_Product_Fields__c> getAtpfByProductForTerritory(
        Id accountId,
        Id territory2Id,
        Set<Id> productIds
    ) {
        Map<Id, Account_Territory_Product_Fields__c> result = new Map<Id, Account_Territory_Product_Fields__c>();
        if (accountId == null || territory2Id == null || productIds.isEmpty()) {
            return result;
        }
        Set<String> productKeys = new Set<String>();
        for (Id productId : productIds) {
            productKeys.add(String.valueOf(productId));
        }
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT
                Product2_Id__c,
                Potential__c,
                Penetration__c,
                Rx_Per_Week__c,
                Adoption__c,
                Loyalty__c,
                Product_Matrix_Rating__c,
                Target_Visit_Frequency__c,
                Notes__c
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :accountId
                AND Territory2_Id__c = :String.valueOf(territory2Id)
                AND Product2_Id__c IN :productKeys
                AND Is_Active__c = TRUE
            WITH USER_MODE
        ]) {
            try {
                result.put((Id) atpf.Product2_Id__c, atpf);
            } catch (Exception ex) {
                // Skip invalid ids.
            }
        }
        return result;
    }

    private static Map<String, Object> buildAtpfValuesMap(Account_Territory_Product_Fields__c atpf) {
        Map<String, Object> values = new Map<String, Object>();
        if (atpf == null) {
            return values;
        }
        values.put('Potential__c', atpf.Potential__c);
        values.put('Penetration__c', atpf.Penetration__c);
        values.put('Rx_Per_Week__c', atpf.Rx_Per_Week__c);
        values.put('Adoption__c', atpf.Adoption__c);
        values.put('Loyalty__c', atpf.Loyalty__c);
        values.put('Product_Matrix_Rating__c', atpf.Product_Matrix_Rating__c);
        values.put('Target_Visit_Frequency__c', atpf.Target_Visit_Frequency__c);
        values.put('Notes__c', atpf.Notes__c);
        return values;
    }

    private static String getTerritoryName(Id territory2Id) {
        if (territory2Id == null) {
            return null;
        }
        List<Territory2> territories = [
            SELECT Name
            FROM Territory2
            WHERE Id = :territory2Id
            WITH USER_MODE
            LIMIT 1
        ];
        return territories.isEmpty() ? null : territories[0].Name;
    }
    public static void saveVisitRatings(
        Id visitId,
        Id sessionId,
        Id layoutId,
        List<VisitRatingFieldInput> values
    ) {
        if (visitId == null || values == null || values.isEmpty()) {
            return;
        }

        VisitRatingContext context = buildCaptureContext(visitId, sessionId);
        persistRatingValues(context, layoutId, values, sessionId);
    }

    private static void persistRatingValues(
        VisitRatingContext context,
        Id layoutId,
        List<VisitRatingFieldInput> values,
        Id sessionId
    ) {
        Map<String, Object> accountValues = new Map<String, Object>();
        Map<String, Object> atfValues = new Map<String, Object>();
        Map<String, Object> atpfValues = new Map<String, Object>();
        List<RatingAuditRow> auditRows = new List<RatingAuditRow>();

        for (VisitRatingFieldInput input : values) {
            if (input == null || String.isBlank(input.fieldApiName) || String.isBlank(input.objectApiName)) {
                continue;
            }
            Object value = parseValueJson(input.valueJson);
            if (input.objectApiName == 'Account') {
                accountValues.put(input.fieldApiName, value);
            } else if (input.objectApiName == 'Account_Territory_Fields__c') {
                if (!isCalculatedAtfField(input.fieldApiName)) {
                    atfValues.put(input.fieldApiName, value);
                }
            } else if (input.objectApiName == 'Account_Territory_Product_Fields__c') {
                if (!isCalculatedAtpfField(input.fieldApiName)) {
                    atpfValues.put(input.fieldApiName, value);
                }
            }

            RatingAuditRow audit = new RatingAuditRow();
            audit.fieldKey = input.objectApiName + '.' + input.fieldApiName;
            audit.valueJson = input.valueJson;
            auditRows.add(audit);
        }

        if (!accountValues.isEmpty() && context.accountId != null) {
            Account account = new Account(Id = context.accountId);
            populateSObject(account, accountValues);
            update as user account;
        }

        if (!atfValues.isEmpty()) {
            if (context.accountId == null || context.territory2Id == null) {
                throw new RatingSaveException(
                    'Unable to save territory ratings. Confirm this account is aligned to your territory.'
                );
            }
            mergeExistingAtfValues(context.accountId, context.territory2Id, atfValues);
            sanitizeAtfValuesForVariant(atfValues, context.accountVariant);
            applyAtfCalculations(atfValues, context.accountVariant);
            Map<String, Object> calculatedAtfValues = extractCalculatedAtfValues(atfValues);
            Account_Territory_Fields__c atf = findOrCreateAtf(context.accountId, context.territory2Id);
            populateSObject(atf, atfValues);
            System.debug(
                LoggingLevel.ERROR,
                'RATINGS_SAVE_DEBUG atfUpsert accountId=' +
                    context.accountId +
                    ' territory2Id=' +
                    context.territory2Id +
                    ' atfId=' +
                    atf.Id +
                    ' Potential__c=' +
                    atfValues.get('Potential__c') +
                    ' Penetration__c=' +
                    atfValues.get('Penetration__c') +
                    ' atfValues=' +
                    JSON.serialize(atfValues)
            );
            upsert as user atf;
            applyCalculatedFieldUpdates(atf.Id, calculatedAtfValues);
        }

        if (!atpfValues.isEmpty()) {
            if (context.accountId == null || context.territory2Id == null || context.product2Id == null) {
                throw new RatingSaveException(
                    'Unable to save product ratings. Confirm this account is aligned to your territory and the product is active.'
                );
            }
            mergeExistingAtpfValues(context.accountId, context.territory2Id, context.product2Id, atpfValues);
            applyAtpfCalculations(atpfValues);
            Map<String, Object> calculatedAtpfValues = extractCalculatedAtpfValues(atpfValues);
            Account_Territory_Product_Fields__c atpf = findOrCreateAtpf(
                context.accountId,
                context.territory2Id,
                context.product2Id
            );
            populateSObject(atpf, atpfValues);
            upsert as user atpf;
            applyCalculatedFieldUpdates(atpf.Id, calculatedAtpfValues);
        }

        if (sessionId != null && !auditRows.isEmpty()) {
            persistRatingAuditRows(sessionId, layoutId, auditRows);
        }
    }

    private class RatingAuditRow {
        public String fieldKey;
        public String valueJson;
    }

    private static void persistRatingAuditRows(Id sessionId, Id layoutId, List<RatingAuditRow> auditRows) {
        // Prefer ClmMetricsController when available in the org; otherwise write audit rows directly.
        try {
            Type controllerType = Type.forName('ClmMetricsController');
            if (controllerType != null) {
                List<Object> metricRows = new List<Object>();
                for (RatingAuditRow audit : auditRows) {
                    Map<String, Object> row = new Map<String, Object>{
                        'fieldKey' => audit.fieldKey,
                        'valueJson' => audit.valueJson
                    };
                    metricRows.add(row);
                }
                // Direct DML fallback below is the supported path when the controller signature differs.
            }
        } catch (Exception ignore) {
            // Fall through to direct DML.
        }

        if (!Schema.sObjectType.CLM_Rating_Value__c.isCreateable()) {
            return;
        }
        List<CLM_Rating_Value__c> rows = new List<CLM_Rating_Value__c>();
        for (RatingAuditRow audit : auditRows) {
            CLM_Rating_Value__c row = new CLM_Rating_Value__c();
            row.CLM_Presentation_Session__c = sessionId;
            row.CLM_Rating_Layout__c = layoutId;
            row.Field_Key__c = audit.fieldKey;
            row.Value_JSON__c = audit.valueJson;
            rows.add(row);
        }
        if (!rows.isEmpty()) {
            insert as user rows;
        }
    }

    private static void putAccountFieldIfPresent(Map<String, Object> values, Id accountId, String fieldApiName) {
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApiName) || !fieldMap.get(fieldApiName).getDescribe().isAccessible()) {
            return;
        }
        String soql = 'SELECT ' + fieldApiName + ' FROM Account WHERE Id = :accountId LIMIT 1';
        try {
            Map<String, Object> binds = new Map<String, Object>{ 'accountId' => accountId };
            List<Account> accounts = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
            if (!accounts.isEmpty()) {
                values.put(fieldApiName, accounts[0].get(fieldApiName));
            }
        } catch (Exception ex) {
            // Skip optional Account fields that are not queryable in this org.
        }
    }

    private static String defaultLayoutJson() {
        Map<String, Object> layout = new Map<String, Object>{
            'version' => 2,
            'accountVariant' => VARIANT_HCP,
            'sections' => new Map<String, Object>{
                'account' => new List<Object>(),
                'accountTerritory' => sharedTerritoryFieldDefs(),
                'accountTerritoryProduct' => sharedProductFieldDefs()
            }
        };
        return JSON.serialize(layout);
    }

    private static String defaultHcoLayoutJson() {
        Map<String, Object> layout = new Map<String, Object>{
            'version' => 2,
            'accountVariant' => VARIANT_HCO,
            'sections' => new Map<String, Object>{
                'account' => new List<Object>(),
                'accountTerritory' => sharedTerritoryFieldDefs(),
                'accountTerritoryProduct' => sharedProductFieldDefs()
            }
        };
        return JSON.serialize(layout);
    }

    private static List<Object> sharedTerritoryFieldDefs() {
        return new List<Object>{
            fieldDefWithOptions(
                'Account_Territory_Fields__c',
                'HCP_Classification__c',
                'Classification',
                'picklist',
                10,
                false,
                hcpClassificationOptions()
            ),
            fieldDef('Account_Territory_Fields__c', 'Is_Speaker__c', 'Is Speaker', 'toggle', 20, false, null),
            fieldDef('Account_Territory_Fields__c', 'Is_KOL__c', 'Is KOL', 'toggle', 30, false, null),
            fieldDefWithOptions(
                'Account_Territory_Fields__c',
                'KOL_In_What__c',
                'KOL Type',
                'picklist',
                40,
                false,
                kolReasonOptions()
            )
        };
    }

    private static List<Object> sharedProductFieldDefs() {
        return new List<Object>{
            fieldDef('Account_Territory_Product_Fields__c', 'Potential__c', 'Potentiality', 'numberDonut', 10, false, null),
            fieldDef('Account_Territory_Product_Fields__c', 'Penetration__c', 'Penetration', 'numberDonut', 20, false, null)
        };
    }

    private static Map<String, Object> fieldDefWithOptions(
        String objectApiName,
        String fieldApiName,
        String label,
        String widget,
        Integer orderNum,
        Boolean readOnly,
        List<Object> options
    ) {
        Map<String, Object> field = fieldDef(objectApiName, fieldApiName, label, widget, orderNum, readOnly, null);
        field.put('options', options);
        return field;
    }

    private static List<Object> hcoKolProfileOptions() {
        List<Object> options = new List<Object>();
        for (String value : HCO_KOL_PROFILE_VALUES) {
            options.add(new Map<String, Object>{
                'label' => value,
                'value' => value
            });
        }
        return options;
    }

    private static List<Object> hcoFormularyOptions() {
        return new List<Object>{
            new Map<String, Object>{ 'label' => 'On Formulary', 'value' => 'H' },
            new Map<String, Object>{ 'label' => 'Restricted', 'value' => 'M' },
            new Map<String, Object>{ 'label' => 'Not Listed', 'value' => 'L' }
        };
    }

    private static List<Object> hcoContractTierOptions() {
        return new List<Object>{
            new Map<String, Object>{ 'label' => 'Preferred', 'value' => 'H' },
            new Map<String, Object>{ 'label' => 'Standard', 'value' => 'M' },
            new Map<String, Object>{ 'label' => 'None', 'value' => 'L' }
        };
    }

    public static String resolveAccountVariant(Id accountId) {
        if (accountId == null) {
            return VARIANT_HCP;
        }
        List<Account> accounts = [
            SELECT RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return VARIANT_HCP;
        }
        return HCO_RECORD_TYPES.contains(accounts[0].RecordType.DeveloperName)
            ? VARIANT_HCO
            : VARIANT_HCP;
    }

    private static CLM_Rating_Layout__c resolveDeployedLayout(String accountVariant) {
        String targetVariant = String.isBlank(accountVariant) ? VARIANT_HCP : accountVariant;
        CLM_Rating_Layout__c fallback = null;
        for (CLM_Rating_Layout__c layout : [
            SELECT Id, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Status__c = 'Deployed'
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
        ]) {
            String layoutVariant = resolveLayoutVariant(layout.Fields_JSON__c);
            if (layoutVariant == targetVariant) {
                return layout;
            }
            if (fallback == null && layoutVariant == VARIANT_HCP && targetVariant == VARIANT_HCP) {
                fallback = layout;
            }
        }
        return fallback;
    }

    public static String resolveLayoutVariant(String fieldsJson) {
        if (String.isBlank(fieldsJson)) {
            return VARIANT_HCP;
        }
        try {
            Map<String, Object> layout = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            Object variant = layout.get('accountVariant');
            if (variant != null && String.isNotBlank(String.valueOf(variant))) {
                return String.valueOf(variant);
            }
        } catch (Exception ex) {
            // Fall back to the HCP layout when JSON cannot be parsed.
        }
        return VARIANT_HCP;
    }

    private static Map<String, Object> fieldDef(
        String objectApiName,
        String fieldApiName,
        String label,
        String widget,
        Integer orderNum,
        Boolean readOnly,
        List<String> calculatedFrom
    ) {
        Map<String, Object> field = new Map<String, Object>{
            'objectApiName' => objectApiName,
            'fieldApiName' => fieldApiName,
            'label' => label,
            'widget' => widget,
            'order' => orderNum,
            'readOnly' => readOnly
        };
        if (calculatedFrom != null) {
            field.put('calculatedFrom', calculatedFrom);
        }
        return field;
    }

    private static void patchKnownFieldDefinitions(Map<String, Object> layout) {
        patchKnownFieldDefinitions(layout, VARIANT_HCP);
    }

    private static void patchKnownFieldDefinitions(Map<String, Object> layout, String accountVariant) {
        if (layout == null || !layout.containsKey('sections')) {
            return;
        }
        Map<String, Object> sections = (Map<String, Object>) layout.get('sections');
        patchKolFieldInSection((List<Object>) sections.get('accountTerritory'));
        patchClassificationFieldInSection((List<Object>) sections.get('accountTerritory'));
        if (VARIANT_HCO.equals(accountVariant)) {
            patchHcoFieldDefinitions((List<Object>) sections.get('accountTerritory'));
            patchHcoProductDefinitions((List<Object>) sections.get('accountTerritoryProduct'));
        }
        if (sectionSize(sections, 'accountTerritoryProduct') == 0) {
            Map<String, Object> defaultLayout = (Map<String, Object>) JSON.deserializeUntyped(
                VARIANT_HCO.equals(accountVariant) ? defaultHcoLayoutJson() : defaultLayoutJson()
            );
            Map<String, Object> defaultSections = (Map<String, Object>) defaultLayout.get('sections');
            sections.put('accountTerritoryProduct', defaultSections.get('accountTerritoryProduct'));
        }
    }

    private static void patchHcoFieldDefinitions(List<Object> sectionFields) {
        if (sectionFields == null) {
            return;
        }
        for (Object item : sectionFields) {
            Map<String, Object> field = (Map<String, Object>) item;
            String apiName = (String) field.get('fieldApiName');
            if (apiName == 'Has_KOLs__c') {
                field.put('label', 'Has KOLs');
                field.put('widget', 'toggle');
            } else if (apiName == 'KOL_Profile__c') {
                field.put('label', 'KOL Profile');
                field.put('widget', 'picklist');
                field.put('options', hcoKolProfileOptions());
            } else if (apiName == 'Potential__c') {
                field.put('label', 'Strategic Priority');
            } else if (apiName == 'Penetration__c') {
                field.put('label', 'Access Level');
            } else if (apiName == 'Matrix_Rating__c') {
                field.put('label', 'Priority Matrix');
            } else if (apiName == 'Classification__c') {
                field.put('label', 'Account Tier');
            }
        }
    }

    private static void patchHcoProductDefinitions(List<Object> sectionFields) {
        if (sectionFields == null) {
            return;
        }
        for (Object item : sectionFields) {
            Map<String, Object> field = (Map<String, Object>) item;
            String apiName = (String) field.get('fieldApiName');
            if (apiName == 'Rx_Per_Week__c') {
                field.put('label', 'Monthly Volume');
            } else if (apiName == 'Adoption__c') {
                field.put('label', 'Formulary Status');
                field.put('options', hcoFormularyOptions());
            } else if (apiName == 'Loyalty__c') {
                field.put('label', 'Contract Tier');
                field.put('options', hcoContractTierOptions());
            } else if (apiName == 'Product_Matrix_Rating__c') {
                field.put('label', 'Product Priority');
            }
        }
    }

    private static void patchKolFieldInSection(List<Object> sectionFields) {
        if (sectionFields == null) {
            return;
        }
        for (Object item : sectionFields) {
            Map<String, Object> field = (Map<String, Object>) item;
            if (field.get('fieldApiName') != 'KOL_In_What__c') {
                continue;
            }
            field.put('label', 'KOL Type');
            field.put('widget', 'picklist');
            field.put('options', kolReasonOptions());
        }
    }

    private static void patchClassificationFieldInSection(List<Object> sectionFields) {
        if (sectionFields == null) {
            return;
        }
        for (Object item : sectionFields) {
            Map<String, Object> field = (Map<String, Object>) item;
            if (field.get('fieldApiName') != 'HCP_Classification__c') {
                continue;
            }
            field.put('label', 'Classification');
            field.put('widget', 'picklist');
            field.put('options', hcpClassificationOptions());
        }
    }

    private static List<Object> hcpClassificationOptions() {
        List<Object> options = new List<Object>();
        for (String value : HCP_CLASSIFICATION_VALUES) {
            options.add(new Map<String, Object>{
                'label' => value,
                'value' => value
            });
        }
        return options;
    }

    private static List<Object> kolReasonOptions() {
        List<Object> options = new List<Object>();
        for (String value : KOL_REASON_VALUES) {
            options.add(new Map<String, Object>{
                'label' => value,
                'value' => value
            });
        }
        return options;
    }

    private static String migrateLegacyFields(List<Object> legacyFields) {
        List<Object> territoryFields = new List<Object>();
        Integer order = 10;
        for (Object item : legacyFields) {
            Map<String, Object> legacy = (Map<String, Object>) item;
            String key = (String) legacy.get('key');
            String label = (String) legacy.get('label');
            String type = (String) legacy.get('type');
            String widget = 'textValue';
            if (type == 'toggle') {
                widget = 'toggle';
            } else if (type == 'number') {
                widget = 'numberDonut';
            } else if (type == 'picklist') {
                widget = 'dotScale';
            }
            Map<String, Object> field = new Map<String, Object>{
                'objectApiName' => 'Account_Territory_Fields__c',
                'fieldApiName' => key,
                'label' => label,
                'widget' => widget,
                'order' => order,
                'readOnly' => false
            };
            if (legacy.containsKey('options')) {
                field.put('options', legacy.get('options'));
            }
            territoryFields.add(field);
            order += 10;
        }
        Map<String, Object> layout = new Map<String, Object>{
            'version' => 2,
            'sections' => new Map<String, Object>{
                'account' => new List<Object>(),
                'accountTerritory' => territoryFields,
                'accountTerritoryProduct' => new List<Object>()
            }
        };
        patchKnownFieldDefinitions(layout);
        return JSON.serialize(layout);
    }

    private static Integer sectionSize(Map<String, Object> sections, String key) {
        if (!sections.containsKey(key)) {
            return 0;
        }
        List<Object> rows = (List<Object>) sections.get(key);
        return rows != null ? rows.size() : 0;
    }

    private static List<CatalogField> describeSection(String sectionKey, String objectApiName, Set<String> allowedFields) {
        List<CatalogField> rows = new List<CatalogField>();
        Schema.SObjectType token = Schema.getGlobalDescribe().get(objectApiName);
        if (token == null) {
            return rows;
        }
        Map<String, Schema.SObjectField> fieldMap = token.getDescribe().fields.getMap();
        for (String fieldApiName : allowedFields) {
            if (!fieldMap.containsKey(fieldApiName)) {
                continue;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            CatalogField row = new CatalogField();
            row.sectionKey = sectionKey;
            row.objectApiName = objectApiName;
            row.fieldApiName = fieldApiName;
            row.label = fieldDescribe.getLabel();
            row.dataType = String.valueOf(fieldDescribe.getType());
            row.readOnly = !fieldDescribe.isUpdateable()
                || fieldApiName == 'Matrix_Rating__c'
                || fieldApiName == 'Classification__c'
                || fieldApiName == 'Product_Matrix_Rating__c';
            row.widget = suggestWidget(fieldDescribe, fieldApiName);
            row.options = buildOptions(fieldDescribe);
            rows.add(row);
        }
        return rows;
    }

    private static String suggestWidget(Schema.DescribeFieldResult fieldDescribe, String fieldApiName) {
        if (fieldApiName == 'Matrix_Rating__c' || fieldApiName == 'Classification__c' || fieldApiName == 'Product_Matrix_Rating__c') {
            return 'calculatedBadge';
        }
        if (fieldApiName == 'KOL_In_What__c' || fieldApiName == 'KOL_Profile__c') {
            return 'picklist';
        }
        Schema.DisplayType fieldType = fieldDescribe.getType();
        if (fieldType == Schema.DisplayType.BOOLEAN) {
            return 'toggle';
        }
        if (fieldType == Schema.DisplayType.DATE || fieldType == Schema.DisplayType.DATETIME) {
            return 'dateRelative';
        }
        if (fieldType == Schema.DisplayType.CURRENCY || fieldType == Schema.DisplayType.DOUBLE || fieldType == Schema.DisplayType.INTEGER) {
            return fieldApiName == 'Rx_Per_Week__c' ? 'numberDonut' : 'textValue';
        }
        if (fieldType == Schema.DisplayType.PICKLIST) {
            return 'dotScale';
        }
        return 'textValue';
    }

    private static List<Map<String, String>> buildOptions(Schema.DescribeFieldResult fieldDescribe) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        if (fieldDescribe.getName() == 'KOL_In_What__c') {
            for (String value : KOL_REASON_VALUES) {
                options.add(new Map<String, String>{
                    'label' => value,
                    'value' => value
                });
            }
            return options;
        }
        if (fieldDescribe.getName() == 'KOL_Profile__c') {
            for (String value : HCO_KOL_PROFILE_VALUES) {
                options.add(new Map<String, String>{
                    'label' => value,
                    'value' => value
                });
            }
            return options;
        }
        if (!fieldDescribe.getType().equals(Schema.DisplayType.PICKLIST)) {
            return options;
        }
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }
        return options;
    }

    private static Id getPrimaryTerritoryId() {
        return resolveTerritoryForAccount(null);
    }

    private static Id resolveTerritoryForAccount(Id accountId) {
        Set<Id> userTerritoryIds = getUserTerritoryIds();
        if (userTerritoryIds.isEmpty()) {
            return null;
        }

        Set<String> userTerritoryKeys = new Set<String>();
        for (Id territoryId : userTerritoryIds) {
            userTerritoryKeys.add(String.valueOf(territoryId));
        }

        if (accountId != null) {
            List<Account_Territory_Fields__c> existingAtf = [
                SELECT Territory2_Id__c
                FROM Account_Territory_Fields__c
                WHERE
                    Account__c = :accountId
                    AND Territory2_Id__c IN :userTerritoryKeys
                    AND Is_Active__c = TRUE
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!existingAtf.isEmpty()) {
                try {
                    return (Id) existingAtf[0].Territory2_Id__c;
                } catch (Exception ex) {
                    // Fall through to OT2A / default territory.
                }
            }

            for (ObjectTerritory2Association association : [
                SELECT Territory2Id
                FROM ObjectTerritory2Association
                WHERE ObjectId = :accountId AND Territory2Id IN :userTerritoryIds
                WITH USER_MODE
                ORDER BY Territory2Id ASC
            ]) {
                return association.Territory2Id;
            }
        }

        List<Id> sortedTerritoryIds = new List<Id>(userTerritoryIds);
        sortedTerritoryIds.sort();
        return sortedTerritoryIds[0];
    }

    private static Set<Id> getUserTerritoryIds() {
        Set<Id> territoryIds = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId()
            WITH USER_MODE
        ]) {
            territoryIds.add(assignment.Territory2Id);
        }
        return territoryIds;
    }

    private static String buildAtfUniqueKey(Id accountId, Id territory2Id) {
        return String.valueOf(accountId) + ':' + String.valueOf(territory2Id);
    }

    private static String buildAtpfUniqueKey(Id accountId, Id territory2Id, Id product2Id) {
        return String.valueOf(accountId) + ':' + String.valueOf(territory2Id) + ':' + String.valueOf(product2Id);
    }

    private static Map<String, Object> extractCalculatedAtfValues(Map<String, Object> values) {
        Map<String, Object> calculated = new Map<String, Object>();
        if (values.containsKey('Matrix_Rating__c')) {
            calculated.put('Matrix_Rating__c', values.remove('Matrix_Rating__c'));
        }
        if (values.containsKey('Classification__c')) {
            calculated.put('Classification__c', values.remove('Classification__c'));
        }
        return calculated;
    }

    private static Map<String, Object> extractCalculatedAtpfValues(Map<String, Object> values) {
        Map<String, Object> calculated = new Map<String, Object>();
        if (values.containsKey('Product_Matrix_Rating__c')) {
            calculated.put('Product_Matrix_Rating__c', values.remove('Product_Matrix_Rating__c'));
        }
        return calculated;
    }

    private static void applyCalculatedFieldUpdates(Id recordId, Map<String, Object> calculatedValues) {
        if (recordId == null || calculatedValues == null || calculatedValues.isEmpty()) {
            return;
        }
        SObject updateRow = recordId.getSobjectType().newSObject(recordId);
        populateSObject(updateRow, calculatedValues);
        Database.update(updateRow, AccessLevel.SYSTEM_MODE);
    }

    private static Id getSessionProductId(Id sessionId) {
        if (sessionId == null) {
            return null;
        }
        List<CLM_Presentation_Session__c> sessions = [
            SELECT CLM_Presentation__r.Product__c
            FROM CLM_Presentation_Session__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
        return sessions.isEmpty() ? null : sessions[0].CLM_Presentation__r?.Product__c;
    }

    private static Map<String, Object> loadExistingValues(Id accountId, Id territory2Id, Id product2Id) {
        Map<String, Object> values = loadTerritoryValues(accountId, territory2Id);
        if (accountId != null && territory2Id != null && product2Id != null) {
            List<Account_Territory_Product_Fields__c> atpfRows = [
                SELECT Rx_Per_Week__c, Adoption__c, Loyalty__c, Product_Matrix_Rating__c, Target_Visit_Frequency__c, Notes__c
                FROM Account_Territory_Product_Fields__c
                WHERE Account__c = :accountId
                    AND Territory2_Id__c = :String.valueOf(territory2Id)
                    AND Product2_Id__c = :String.valueOf(product2Id)
                WITH USER_MODE
                LIMIT 1
            ];
            if (!atpfRows.isEmpty()) {
                values.putAll(buildAtpfValuesMap(atpfRows[0]));
            }
        }
        return values;
    }

    private static Account_Territory_Fields__c findOrCreateAtf(Id accountId, Id territory2Id) {
        List<Account_Territory_Fields__c> rows = [
            SELECT Id
            FROM Account_Territory_Fields__c
            WHERE Account__c = :accountId AND Territory2_Id__c = :String.valueOf(territory2Id)
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            return rows[0];
        }
        return new Account_Territory_Fields__c(
            Account__c = accountId,
            Territory2_Id__c = String.valueOf(territory2Id),
            Is_Active__c = true
        );
    }

    private static Account_Territory_Product_Fields__c findOrCreateAtpf(Id accountId, Id territory2Id, Id product2Id) {
        List<Account_Territory_Product_Fields__c> rows = [
            SELECT Id
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :accountId
                AND Territory2_Id__c = :String.valueOf(territory2Id)
                AND Product2_Id__c = :String.valueOf(product2Id)
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            return rows[0];
        }
        return new Account_Territory_Product_Fields__c(
            Account__c = accountId,
            Territory2_Id__c = String.valueOf(territory2Id),
            Product2_Id__c = String.valueOf(product2Id),
            Is_Active__c = true
        );
    }

    private static Boolean isCalculatedAtfField(String fieldApiName) {
        return fieldApiName == 'Matrix_Rating__c' || fieldApiName == 'Classification__c';
    }

    private static Boolean isCalculatedAtpfField(String fieldApiName) {
        return fieldApiName == 'Product_Matrix_Rating__c';
    }

    private static void applyAtpfCalculations(Map<String, Object> atpfValues) {
        Object adoptionObj = atpfValues.get('Adoption__c');
        Object loyaltyObj = atpfValues.get('Loyalty__c');
        if (adoptionObj == null || loyaltyObj == null) {
            return;
        }
        String adoption = String.valueOf(adoptionObj);
        String loyalty = String.valueOf(loyaltyObj);
        if (String.isBlank(adoption) || String.isBlank(loyalty)) {
            return;
        }
        atpfValues.put('Product_Matrix_Rating__c', (adoption + loyalty).toLowerCase());
    }

    private static void applyAtfCalculations(Map<String, Object> atfValues, String accountVariant) {
        if (usesHcpKolFields(atfValues)) {
            applyHcpKolCalculations(atfValues);
        } else if (VARIANT_HCO.equals(accountVariant) || usesHcoKolFields(atfValues)) {
            applyHcoKolCalculations(atfValues);
        } else {
            applyHcpKolCalculations(atfValues);
        }

        Object potentialObj = atfValues.get('Potential__c');
        Object penetrationObj = atfValues.get('Penetration__c');
        if (potentialObj == null || penetrationObj == null) {
            return;
        }
        String potential = String.valueOf(potentialObj);
        String penetration = String.valueOf(penetrationObj);
        if (String.isBlank(potential) || String.isBlank(penetration)) {
            return;
        }

        String matrixKey = (potential + penetration).toUpperCase();
        atfValues.put('Matrix_Rating__c', matrixKey.toLowerCase());
        atfValues.put('Classification__c', classifyMatrix(matrixKey));
    }

    private static Boolean usesHcpKolFields(Map<String, Object> atfValues) {
        return atfValues.containsKey('Is_KOL__c') || atfValues.containsKey('KOL_In_What__c');
    }

    private static Boolean usesHcoKolFields(Map<String, Object> atfValues) {
        return atfValues.containsKey('Has_KOLs__c') || atfValues.containsKey('KOL_Profile__c');
    }

    private static void sanitizeAtfValuesForVariant(Map<String, Object> atfValues, String accountVariant) {
        if (VARIANT_HCO.equals(accountVariant)) {
            if (!atfValues.containsKey('Is_KOL__c')) {
                atfValues.put('Is_KOL__c', false);
            }
            if (!atfValues.containsKey('KOL_In_What__c')) {
                atfValues.put('KOL_In_What__c', null);
            }
        } else {
            if (!atfValues.containsKey('Has_KOLs__c')) {
                atfValues.put('Has_KOLs__c', false);
            }
            if (!atfValues.containsKey('KOL_Profile__c')) {
                atfValues.put('KOL_Profile__c', null);
            }
        }
    }

    private static void applyHcpKolCalculations(Map<String, Object> atfValues) {
        if (atfValues.containsKey('Is_KOL__c')) {
            Object isKolValue = atfValues.get('Is_KOL__c');
            Boolean isKol = isKolValue == true
                || (isKolValue != null && String.valueOf(isKolValue).equalsIgnoreCase('true'));
            if (!isKol) {
                atfValues.put('KOL_In_What__c', null);
            } else if (atfValues.containsKey('KOL_In_What__c')) {
                validateKolReason(atfValues);
            }
        } else if (atfValues.containsKey('KOL_In_What__c')) {
            validateKolReason(atfValues);
        }
    }

    private static void applyHcoKolCalculations(Map<String, Object> atfValues) {
        atfValues.put('Is_KOL__c', false);
        atfValues.put('KOL_In_What__c', null);
        if (atfValues.containsKey('Has_KOLs__c')) {
            Object hasKolsValue = atfValues.get('Has_KOLs__c');
            Boolean hasKols = hasKolsValue == true
                || (hasKolsValue != null && String.valueOf(hasKolsValue).equalsIgnoreCase('true'));
            if (!hasKols) {
                atfValues.put('KOL_Profile__c', null);
            } else if (atfValues.containsKey('KOL_Profile__c')) {
                validateHcoKolProfile(atfValues);
            }
        } else if (atfValues.containsKey('KOL_Profile__c')) {
            validateHcoKolProfile(atfValues);
            atfValues.put('Has_KOLs__c', true);
        }
    }

    private static void validateHcoKolProfile(Map<String, Object> atfValues) {
        Object profileValue = atfValues.get('KOL_Profile__c');
        if (profileValue != null && String.isNotBlank(String.valueOf(profileValue))) {
            String profile = String.valueOf(profileValue);
            if (!HCO_KOL_PROFILE_VALUES.contains(profile)) {
                throw new RatingSaveException(
                    'Select a valid KOL profile for this organization.'
                );
            }
            atfValues.put('KOL_Profile__c', profile);
        }
    }

    private static void validateKolReason(Map<String, Object> atfValues) {
        Object kolReasonValue = atfValues.get('KOL_In_What__c');
        if (kolReasonValue != null && String.isNotBlank(String.valueOf(kolReasonValue))) {
            String kolReason = String.valueOf(kolReasonValue);
            if (!KOL_REASON_VALUES.contains(kolReason)) {
                throw new RatingSaveException(
                    'Select a valid KOL reason: High Prescriber or Key Scientific Leader.'
                );
            }
            atfValues.put('KOL_In_What__c', kolReason);
        }
    }

    private static void mergeExistingAtfValues(
        Id accountId,
        Id territory2Id,
        Map<String, Object> atfValues
    ) {
        List<Account_Territory_Fields__c> rows = [
            SELECT
                Is_KOL__c,
                KOL_In_What__c,
                Has_KOLs__c,
                KOL_Profile__c,
                Is_Speaker__c,
                HCP_Classification__c,
                Potential__c,
                Penetration__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :accountId AND Territory2_Id__c = :String.valueOf(territory2Id)
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return;
        }
        Account_Territory_Fields__c existing = rows[0];
        mergeMissingValue(atfValues, 'Is_KOL__c', existing.Is_KOL__c);
        mergeMissingValue(atfValues, 'KOL_In_What__c', existing.KOL_In_What__c);
        mergeMissingValue(atfValues, 'Has_KOLs__c', existing.Has_KOLs__c);
        mergeMissingValue(atfValues, 'KOL_Profile__c', existing.KOL_Profile__c);
        mergeMissingValue(atfValues, 'Is_Speaker__c', existing.Is_Speaker__c);
        mergeMissingValue(atfValues, 'HCP_Classification__c', existing.HCP_Classification__c);
        mergeMissingValue(atfValues, 'Potential__c', existing.Potential__c);
        mergeMissingValue(atfValues, 'Penetration__c', existing.Penetration__c);
    }

    private static void mergeExistingAtpfValues(
        Id accountId,
        Id territory2Id,
        Id product2Id,
        Map<String, Object> atpfValues
    ) {
        List<Account_Territory_Product_Fields__c> rows = [
            SELECT Potential__c, Penetration__c, Rx_Per_Week__c, Adoption__c, Loyalty__c, Target_Visit_Frequency__c, Notes__c
            FROM Account_Territory_Product_Fields__c
            WHERE
                Account__c = :accountId
                AND Territory2_Id__c = :String.valueOf(territory2Id)
                AND Product2_Id__c = :String.valueOf(product2Id)
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return;
        }
        Account_Territory_Product_Fields__c existing = rows[0];
        mergeMissingValue(atpfValues, 'Potential__c', existing.Potential__c);
        mergeMissingValue(atpfValues, 'Penetration__c', existing.Penetration__c);
        mergeMissingValue(atpfValues, 'Rx_Per_Week__c', existing.Rx_Per_Week__c);
        mergeMissingValue(atpfValues, 'Adoption__c', existing.Adoption__c);
        mergeMissingValue(atpfValues, 'Loyalty__c', existing.Loyalty__c);
        mergeMissingValue(atpfValues, 'Target_Visit_Frequency__c', existing.Target_Visit_Frequency__c);
        mergeMissingValue(atpfValues, 'Notes__c', existing.Notes__c);
    }

    private static void mergeMissingValue(Map<String, Object> values, String fieldApiName, Object existingValue) {
        if (!values.containsKey(fieldApiName)) {
            values.put(fieldApiName, existingValue);
        }
    }

    private static String classifyMatrix(String matrixKey) {
        if (String.isBlank(matrixKey)) {
            return null;
        }
        if (new Set<String>{ 'A1', 'A2', 'B1' }.contains(matrixKey)) {
            return 'A';
        }
        if (new Set<String>{ 'A3', 'B2', 'C1' }.contains(matrixKey)) {
            return 'B';
        }
        if (new Set<String>{ 'B3', 'C2', 'C3' }.contains(matrixKey)) {
            return 'C';
        }
        return null;
    }

    private static Object parseValueJson(String valueJson) {
        if (String.isBlank(valueJson)) {
            return null;
        }
        try {
            return JSON.deserializeUntyped(valueJson);
        } catch (Exception ex) {
            return valueJson;
        }
    }

    private static void populateSObject(SObject record, Map<String, Object> values) {
        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType()
            .getDescribe()
            .fields.getMap();
        for (String fieldApiName : values.keySet()) {
            Object rawValue = values.get(fieldApiName);
            if (rawValue == null) {
                record.put(fieldApiName, null);
                continue;
            }
            if (!fieldMap.containsKey(fieldApiName)) {
                record.put(fieldApiName, rawValue);
                continue;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            record.put(fieldApiName, coerceFieldValue(fieldDescribe, rawValue));
        }
    }

    private static Object coerceFieldValue(Schema.DescribeFieldResult fieldDescribe, Object rawValue) {
        Schema.DisplayType fieldType = fieldDescribe.getType();
        if (fieldType == Schema.DisplayType.BOOLEAN) {
            if (rawValue instanceof Boolean) {
                return rawValue;
            }
            return String.valueOf(rawValue).equalsIgnoreCase('true');
        }
        if (
            fieldType == Schema.DisplayType.CURRENCY ||
            fieldType == Schema.DisplayType.DOUBLE ||
            fieldType == Schema.DisplayType.INTEGER ||
            fieldType == Schema.DisplayType.PERCENT
        ) {
            if (rawValue instanceof Decimal) {
                return rawValue;
            }
            if (rawValue instanceof Integer || rawValue instanceof Long) {
                return Decimal.valueOf(String.valueOf(rawValue));
            }
            if (rawValue instanceof Double) {
                return Decimal.valueOf((Double) rawValue);
            }
            String text = String.valueOf(rawValue).trim();
            if (String.isBlank(text)) {
                return null;
            }
            return Decimal.valueOf(text);
        }
        return rawValue;
    }
}