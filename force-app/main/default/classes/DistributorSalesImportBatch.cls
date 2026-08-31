/**
 * Processes a Sales_Data_Import_Batch__c: geocode pending sellouts, map pharmacies by
 * name/geo, auto-create pharmacy accounts for remaining geocoded points, upsert withdrawals.
 */
public with sharing class DistributorSalesImportBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private Id batchId;
    private Integer insertedCount = 0;
    private Integer updatedCount = 0;
    private Integer failedCount = 0;
    private Integer pharmaciesCreated = 0;
    private List<String> errors = new List<String>();
    private String distributorCode;
    private Date reportMonth;
    private Boolean autoCreatePharmacies;

    public DistributorSalesImportBatch(Id batchId) {
        this(batchId, true);
    }

    public DistributorSalesImportBatch(Id batchId, Boolean autoCreatePharmacies) {
        this.batchId = batchId;
        this.autoCreatePharmacies = autoCreatePharmacies != false;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Sales_Data_Import_Batch__c batch = [
            SELECT Id, Distributor_Code__c, Report_Month__c, ContentVersion_Id__c, Status__c, File_Name__c
            FROM Sales_Data_Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        distributorCode = DistributorMatchingUtil.normalizeDistributorCode(batch.Distributor_Code__c);
        reportMonth = batch.Report_Month__c != null ? batch.Report_Month__c : Date.today().toStartOfMonth();
        batch.Status__c = 'Processing';
        Database.update(batch, AccessLevel.SYSTEM_MODE);

        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distributorCode);
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Unique_Key__c,
                    Distributor_Code__c,
                    Distributor_Client_Code__c,
                    Distributor_Client_Name__c,
                    Address__c,
                    Governorate__c,
                    Brick_Code__c,
                    Latitude__c,
                    Longitude__c,
                    Geocode_Status__c,
                    Geocode_Message__c,
                    Pharmacy_Account__c,
                    Status__c,
                    Match_Confidence__c,
                    Match_Method__c
                FROM Distributor_Sellout_Alias__c
                WHERE
                    Distributor_Code__c IN :distCodes
                    AND (
                        Geocode_Status__c = 'Pending'
                        OR Geocode_Status__c = NULL
                        OR (Geocode_Status__c = 'Failed' AND Latitude__c = NULL)
                    )
                WITH SYSTEM_MODE
                ORDER BY CreatedDate ASC
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Distributor_Sellout_Alias__c> aliases = (List<Distributor_Sellout_Alias__c>) scope;
        for (Distributor_Sellout_Alias__c alias : aliases) {
            if (alias.Latitude__c != null && alias.Longitude__c != null) {
                alias.Geocode_Status__c = 'Geocoded';
                alias.Geocode_Message__c = null;
                continue;
            }
            try {
                DistributorGeocodeService.GeoResult geo = DistributorGeocodeService.geocode(
                    alias.Distributor_Client_Name__c,
                    alias.Address__c,
                    alias.Governorate__c
                );
                alias.Geocode_Status__c = geo.status;
                if (geo.status == 'Geocoded') {
                    alias.Latitude__c = geo.latitude;
                    alias.Longitude__c = geo.longitude;
                    alias.Geocode_Message__c = null;
                } else {
                    List<String> notes = new List<String>();
                    if (String.isNotBlank(geo.message)) {
                        notes.add(geo.message);
                    }
                    if (String.isNotBlank(geo.recommendation)) {
                        notes.add('Recommendation: ' + geo.recommendation);
                    }
                    alias.Geocode_Message__c = notes.isEmpty() ? null : String.join(notes, '\n');
                }
            } catch (Exception e) {
                alias.Geocode_Status__c = 'Failed';
                alias.Geocode_Message__c =
                    'Geocode exception: ' +
                    e.getMessage() +
                    '\nRecommendation: ' +
                    DistributorGeocodeService.defaultFailureRecommendation(
                        DistributorGeocodeService.hasGoogleApiKey()
                    );
                if (errors.size() < 50) {
                    errors.add('Geocode ' + alias.Unique_Key__c + ': ' + e.getMessage());
                }
            }
        }
        rematch(aliases);
        Database.update(aliases, AccessLevel.SYSTEM_MODE);
    }

    public void finish(Database.BatchableContext bc) {
        // Final rematch + optional pharmacy auto-create for this distributor's geocoded points
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distributorCode);
        List<Distributor_Sellout_Alias__c> openAliases = [
            SELECT
                Id,
                Unique_Key__c,
                Distributor_Code__c,
                Distributor_Client_Code__c,
                Distributor_Client_Name__c,
                Address__c,
                Governorate__c,
                Brick_Code__c,
                Latitude__c,
                Longitude__c,
                Geocode_Status__c,
                Pharmacy_Account__c,
                Status__c,
                Match_Confidence__c,
                Match_Method__c
            FROM Distributor_Sellout_Alias__c
            WHERE
                Distributor_Code__c IN :distCodes
                AND Pharmacy_Account__c = NULL
                AND Geocode_Status__c = 'Geocoded'
                AND Latitude__c != NULL
                AND Longitude__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 2000
        ];
        if (!openAliases.isEmpty()) {
            rematch(openAliases);
            if (autoCreatePharmacies) {
                autoCreateFromGeocoded(openAliases);
            }
            Database.update(openAliases, AccessLevel.SYSTEM_MODE);
        }

        upsertWithdrawals();

        Sales_Data_Import_Batch__c batch = [
            SELECT Id, Rows_Inserted__c, Rows_Updated__c, Rows_Failed__c, Error_Log__c, Status__c, Needs_Review__c
            FROM Sales_Data_Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        batch.Rows_Inserted__c = (batch.Rows_Inserted__c == null ? 0 : batch.Rows_Inserted__c) + insertedCount;
        batch.Rows_Updated__c = (batch.Rows_Updated__c == null ? 0 : batch.Rows_Updated__c) + updatedCount;
        batch.Rows_Failed__c = (batch.Rows_Failed__c == null ? 0 : batch.Rows_Failed__c) + failedCount;
        batch.Status__c = 'Completed';
        List<String> notes = new List<String>();
        if (pharmaciesCreated > 0) {
            notes.add('Auto-created pharmacies: ' + pharmaciesCreated);
        }
        if (!errors.isEmpty()) {
            notes.addAll(errors);
        }
        if (!notes.isEmpty()) {
            String log = String.join(notes, '\n');
            batch.Error_Log__c = (batch.Error_Log__c == null ? '' : batch.Error_Log__c + '\n') + log.left(32000);
        }
        Database.update(batch, AccessLevel.SYSTEM_MODE);
    }

    private void rematch(List<Distributor_Sellout_Alias__c> aliases) {
        List<Distributor_Sellout_Alias__c> known = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Client_Name__c,
                Brick_Code__c,
                Latitude__c,
                Longitude__c,
                Pharmacy_Account__c
            FROM Distributor_Sellout_Alias__c
            WHERE Pharmacy_Account__c != NULL
            WITH SYSTEM_MODE
            LIMIT 5000
        ];

        Id pharmacyRtId = pharmacyRecordTypeId();
        List<Account> pharmacies = new List<Account>();
        if (pharmacyRtId != null) {
            pharmacies = [
                SELECT Id, Name, BillingLatitude, BillingLongitude, BillingStreet, BillingCity, BillingState
                FROM Account
                WHERE RecordTypeId = :pharmacyRtId
                WITH SYSTEM_MODE
                LIMIT 5000
            ];
        }

        Decimal prox = DistributorMatchingUtil.proximityMeters();
        Decimal threshold = DistributorMatchingUtil.autoConfirmThreshold();

        for (Distributor_Sellout_Alias__c cand : aliases) {
            if (cand.Pharmacy_Account__c != null && cand.Status__c == 'Confirmed') {
                continue;
            }
            Decimal bestScore = 0;
            Id bestPharmacy;
            String method;

            for (Distributor_Sellout_Alias__c k : known) {
                if (k.Id == cand.Id) {
                    continue;
                }
                Decimal score = DistributorMatchingUtil.nameSimilarity(
                    cand.Distributor_Client_Name__c,
                    k.Distributor_Client_Name__c
                );
                String m = 'FuzzyName';
                if (
                    String.isNotBlank(cand.Brick_Code__c) &&
                    cand.Brick_Code__c == k.Brick_Code__c &&
                    score < 75
                ) {
                    score = Math.max(score, 70);
                    m = 'BrickCode';
                }
                if (cand.Latitude__c != null && k.Latitude__c != null) {
                    Decimal meters = DistributorMatchingUtil.haversineMeters(
                        cand.Latitude__c,
                        cand.Longitude__c,
                        k.Latitude__c,
                        k.Longitude__c
                    );
                    if (meters != null && meters <= prox) {
                        Decimal geoScore = 60 + (score * 0.4);
                        if (geoScore > score) {
                            score = geoScore;
                            m = 'GeoProximity+Name';
                        }
                    }
                }
                if (score > bestScore && k.Pharmacy_Account__c != null) {
                    bestScore = score;
                    bestPharmacy = k.Pharmacy_Account__c;
                    method = m;
                }
            }

            for (Account ph : pharmacies) {
                Decimal score = DistributorMatchingUtil.nameSimilarity(cand.Distributor_Client_Name__c, ph.Name);
                String m = 'PharmacyName';
                if (cand.Latitude__c != null && ph.BillingLatitude != null) {
                    Decimal meters = DistributorMatchingUtil.haversineMeters(
                        cand.Latitude__c,
                        cand.Longitude__c,
                        ph.BillingLatitude,
                        ph.BillingLongitude
                    );
                    if (meters != null && meters <= prox) {
                        Decimal geoScore = 65 + (score * 0.35);
                        if (geoScore > score) {
                            score = geoScore;
                            m = 'GeoProximity+Pharmacy';
                        }
                    }
                }
                if (score > bestScore) {
                    bestScore = score;
                    bestPharmacy = ph.Id;
                    method = m;
                }
            }

            if (bestPharmacy != null && bestScore >= 50) {
                cand.Pharmacy_Account__c = bestPharmacy;
                cand.Match_Confidence__c = bestScore.setScale(2);
                cand.Match_Method__c = method;
                cand.Status__c = bestScore >= threshold ? 'Confirmed' : 'Suggested';
                stampPharmacyGeo(bestPharmacy, cand);
            }
        }
    }

    private void autoCreateFromGeocoded(List<Distributor_Sellout_Alias__c> aliases) {
        Decimal prox = DistributorMatchingUtil.proximityMeters();
        List<Distributor_Sellout_Alias__c> remaining = new List<Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c a : aliases) {
            if (a.Pharmacy_Account__c == null && a.Latitude__c != null) {
                remaining.add(a);
            }
        }
        // Cluster by proximity, create one pharmacy per cluster
        List<List<Distributor_Sellout_Alias__c>> clusters = new List<List<Distributor_Sellout_Alias__c>>();
        for (Distributor_Sellout_Alias__c a : remaining) {
            Boolean placed = false;
            for (List<Distributor_Sellout_Alias__c> cluster : clusters) {
                Distributor_Sellout_Alias__c seed = cluster[0];
                Decimal meters = DistributorMatchingUtil.haversineMeters(
                    a.Latitude__c,
                    a.Longitude__c,
                    seed.Latitude__c,
                    seed.Longitude__c
                );
                if (meters != null && meters <= prox) {
                    cluster.add(a);
                    placed = true;
                    break;
                }
            }
            if (!placed) {
                clusters.add(new List<Distributor_Sellout_Alias__c>{ a });
            }
        }

        List<Account> toInsert = new List<Account>();
        List<List<Distributor_Sellout_Alias__c>> clusterByInsert = new List<List<Distributor_Sellout_Alias__c>>();
        Id rtId = pharmacyRecordTypeId();
        for (List<Distributor_Sellout_Alias__c> cluster : clusters) {
            Distributor_Sellout_Alias__c seed = cluster[0];
            Account ph = new Account();
            ph.Name = String.isNotBlank(seed.Distributor_Client_Name__c)
                ? seed.Distributor_Client_Name__c.left(255)
                : seed.Distributor_Client_Code__c;
            if (rtId != null) {
                ph.RecordTypeId = rtId;
            }
            if (String.isNotBlank(seed.Address__c)) {
                ph.BillingStreet = seed.Address__c.left(255);
            }
            if (String.isNotBlank(seed.Governorate__c) && seed.Governorate__c != '0') {
                ph.BillingState = seed.Governorate__c.left(80);
            }
            ph.BillingCountry = 'Egypt';
            ph.BillingLatitude = seed.Latitude__c;
            ph.BillingLongitude = seed.Longitude__c;
            toInsert.add(ph);
            clusterByInsert.add(cluster);
        }
        if (toInsert.isEmpty()) {
            return;
        }
        Database.SaveResult[] srs = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < srs.size(); i++) {
            if (!srs[i].isSuccess()) {
                if (errors.size() < 50) {
                    errors.add('Pharmacy create: ' + srs[i].getErrors()[0].getMessage());
                }
                continue;
            }
            Id pharmacyId = srs[i].getId();
            pharmaciesCreated++;
            for (Distributor_Sellout_Alias__c a : clusterByInsert[i]) {
                a.Pharmacy_Account__c = pharmacyId;
                a.Match_Confidence__c = 100;
                a.Match_Method__c = 'GeoCluster+AutoCreate';
                a.Status__c = 'Suggested';
            }
        }
    }

    private void stampPharmacyGeo(Id pharmacyId, Distributor_Sellout_Alias__c alias) {
        if (pharmacyId == null || alias.Latitude__c == null) {
            return;
        }
        try {
            Account ph = [
                SELECT Id, BillingLatitude, BillingLongitude
                FROM Account
                WHERE Id = :pharmacyId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (ph.BillingLatitude == null || ph.BillingLongitude == null) {
                ph.BillingLatitude = alias.Latitude__c;
                ph.BillingLongitude = alias.Longitude__c;
                Database.update(ph, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            // best effort
        }
    }

    private static Id pharmacyRecordTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && info.getDeveloperName() == 'Pharmacy') {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    private void upsertWithdrawals() {
        List<Map<String, Object>> stagingRows = loadStaging();
        if (stagingRows.isEmpty()) {
            return;
        }
        String distCode = DistributorMatchingUtil.normalizeDistributorCode(distributorCode);
        String dataSource = DistributorMatchingUtil.toDataSource(distCode);

        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distCode);
        Map<String, Distributor_Product_Alias__c> productAliases = new Map<String, Distributor_Product_Alias__c>();
        for (Distributor_Product_Alias__c a : [
            SELECT Id, Unique_Key__c, Product2_Id__c, Status__c, Distributor_Item_Code__c, Match_Confidence__c
            FROM Distributor_Product_Alias__c
            WHERE Distributor_Code__c IN :distCodes AND Product2_Id__c != NULL
            WITH SYSTEM_MODE
        ]) {
            productAliases.put(a.Unique_Key__c, a);
            productAliases.put(
                DistributorMatchingUtil.buildProductUniqueKey(distCode, a.Distributor_Item_Code__c),
                a
            );
        }
        Map<String, Distributor_Sellout_Alias__c> selloutAliases = new Map<String, Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c a : [
            SELECT Id, Unique_Key__c, Pharmacy_Account__c, Status__c, Distributor_Client_Code__c
            FROM Distributor_Sellout_Alias__c
            WHERE Distributor_Code__c IN :distCodes AND Pharmacy_Account__c != NULL
            WITH SYSTEM_MODE
        ]) {
            selloutAliases.put(a.Unique_Key__c, a);
            selloutAliases.put(
                DistributorMatchingUtil.buildSelloutUniqueKey(distCode, a.Distributor_Client_Code__c),
                a
            );
        }

        Map<Id, Id> brickByPharmacy = new Map<Id, Id>();
        Set<Id> pharmacyIds = new Set<Id>();
        for (Distributor_Sellout_Alias__c a : selloutAliases.values()) {
            pharmacyIds.add(a.Pharmacy_Account__c);
        }
        try {
            for (SObject bp : Database.query(
                'SELECT Brick__c, Pharmacy_Account__c FROM Brick_Pharmacy__c WHERE Pharmacy_Account__c IN :pharmacyIds AND Is_Active__c = true',
                AccessLevel.SYSTEM_MODE
            )) {
                brickByPharmacy.put((Id) bp.get('Pharmacy_Account__c'), (Id) bp.get('Brick__c'));
            }
        } catch (Exception e) {
            // optional
        }

        Map<String, Pharmacy_Sales_Withdrawal__c> withdrawals = new Map<String, Pharmacy_Sales_Withdrawal__c>();
        for (Map<String, Object> row : stagingRows) {
            String itemCode = normalize(row.get('itemCode'));
            String clientCode = normalize(row.get('clientCode'));
            String pKey = DistributorMatchingUtil.buildProductUniqueKey(distCode, itemCode);
            String sKey = DistributorMatchingUtil.buildSelloutUniqueKey(distCode, clientCode);
            Distributor_Product_Alias__c pa = productAliases.get(pKey);
            Distributor_Sellout_Alias__c sa = selloutAliases.get(sKey);
            if (pa == null || sa == null || pa.Status__c == 'Rejected' || sa.Status__c == 'Rejected') {
                failedCount++;
                continue;
            }
            if (pa.Status__c != 'Confirmed' && (pa.Match_Confidence__c == null || pa.Match_Confidence__c < 85)) {
                failedCount++;
                continue;
            }
            if (sa.Pharmacy_Account__c == null) {
                failedCount++;
                continue;
            }
            Id productId = pa.Product2_Id__c;
            Id pharmacyId = sa.Pharmacy_Account__c;
            String uk =
                dataSource +
                '_' +
                String.valueOf(reportMonth.year()) +
                '-' +
                (reportMonth.month() < 10 ? '0' : '') +
                String.valueOf(reportMonth.month()) +
                '_' +
                pharmacyId +
                '_' +
                productId;

            Decimal qty = toDecimal(row.get('quantity'));
            if (qty == null) {
                qty = 0;
            }
            Decimal unitPrice = toDecimal(row.get('unitPrice'));

            if (withdrawals.containsKey(uk)) {
                Pharmacy_Sales_Withdrawal__c existing = withdrawals.get(uk);
                existing.Quantity_Withdrawn__c =
                    (existing.Quantity_Withdrawn__c == null ? 0 : existing.Quantity_Withdrawn__c) + qty;
            } else {
                Pharmacy_Sales_Withdrawal__c w = new Pharmacy_Sales_Withdrawal__c(
                    Data_Source__c = dataSource,
                    Report_Month__c = reportMonth,
                    Pharmacy_Account__c = pharmacyId,
                    Product2_Id__c = String.valueOf(productId),
                    Quantity_Withdrawn__c = qty,
                    Unique_Key__c = uk,
                    Import_Batch__c = batchId
                );
                if (unitPrice != null) {
                    w.Unit_Price__c = unitPrice;
                }
                if (brickByPharmacy.containsKey(pharmacyId)) {
                    w.Brick__c = brickByPharmacy.get(pharmacyId);
                }
                withdrawals.put(uk, w);
            }
        }

        if (withdrawals.isEmpty()) {
            return;
        }
        List<Pharmacy_Sales_Withdrawal__c> toSave = withdrawals.values();
        Database.UpsertResult[] results = Database.upsert(
            toSave,
            Pharmacy_Sales_Withdrawal__c.Unique_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : results) {
            if (ur.isSuccess()) {
                if (ur.isCreated()) {
                    insertedCount++;
                } else {
                    updatedCount++;
                }
            } else {
                failedCount++;
                if (errors.size() < 50) {
                    errors.add(ur.getErrors()[0].getMessage());
                }
            }
        }
    }

    private List<Map<String, Object>> loadStaging() {
        List<Map<String, Object>> stagingRows = new List<Map<String, Object>>();
        String title = 'DistributorImport_' + batchId;
        List<ContentVersion> cvs = [
            SELECT Id, VersionData
            FROM ContentVersion
            WHERE Title = :title AND IsLatest = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (cvs.isEmpty()) {
            Sales_Data_Import_Batch__c batch = [
                SELECT ContentVersion_Id__c
                FROM Sales_Data_Import_Batch__c
                WHERE Id = :batchId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (String.isNotBlank(batch.ContentVersion_Id__c)) {
                cvs = [
                    SELECT Id, VersionData
                    FROM ContentVersion
                    WHERE Id = :batch.ContentVersion_Id__c
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
            }
        }
        if (cvs.isEmpty() || cvs[0].VersionData == null) {
            return stagingRows;
        }
        Object parsed = JSON.deserializeUntyped(cvs[0].VersionData.toString());
        if (parsed instanceof List<Object>) {
            for (Object o : (List<Object>) parsed) {
                stagingRows.add((Map<String, Object>) o);
            }
        }
        return stagingRows;
    }

    private static String normalize(Object o) {
        return o == null ? '' : String.valueOf(o).trim().replaceAll('\\s+', '');
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        if (o instanceof Integer) {
            return Decimal.valueOf((Integer) o);
        }
        if (o instanceof Long) {
            return Decimal.valueOf((Long) o);
        }
        if (o instanceof Double) {
            return Decimal.valueOf((Double) o);
        }
        try {
            return Decimal.valueOf(String.valueOf(o).trim());
        } catch (Exception e) {
            return null;
        }
    }
}