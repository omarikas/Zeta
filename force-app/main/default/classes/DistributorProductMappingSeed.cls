/**
 * Seeds Distributor_Product_Alias__c from DistributorProductMappingSeed static resource.
 * Optionally ensures Product2 records exist from ZetaProductListSeed.
 */
public with sharing class DistributorProductMappingSeed {
    public class SeedResult {
        @AuraEnabled public Integer productsUpserted;
        @AuraEnabled public Integer aliasesUpserted;
        @AuraEnabled public Integer aliasesSkipped;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static SeedResult seedFromStaticResources() {
        SeedResult result = new SeedResult();
        result.productsUpserted = ensureProductsFromSeed();
        Map<String, Id> productByZetaCode = loadProductsByExternalId();
        List<Distributor_Product_Alias__c> aliases = new List<Distributor_Product_Alias__c>();
        Integer skipped = 0;

        for (String line : readCsvLines('DistributorProductMappingSeed')) {
            List<String> cols = parseCsvLine(line);
            if (cols.size() < 4) {
                skipped++;
                continue;
            }
            String dist = DistributorMatchingUtil.normalizeDistributorCode(cols[0]);
            String itemCode = DistributorMatchingUtil.normalizeCode(cols[1]);
            if (String.isBlank(dist) || String.isBlank(itemCode)) {
                skipped++;
                continue;
            }
            String itemName = cols.size() > 2 ? cols[2] : null;
            String zetaCode = cols.size() > 3 ? cols[3].trim() : null;
            String zetaName = cols.size() > 4 ? cols[4] : null;

            Distributor_Product_Alias__c alias = new Distributor_Product_Alias__c(
                Distributor_Code__c = dist,
                Distributor_Item_Code__c = itemCode,
                Distributor_Item_Name__c = itemName,
                Zeta_Code__c = zetaCode,
                Match_Confidence__c = 100,
                Match_Method__c = 'Seeded',
                Status__c = 'Confirmed',
                Unique_Key__c = DistributorMatchingUtil.buildProductUniqueKey(dist, itemCode)
            );
            if (String.isNotBlank(zetaCode) && productByZetaCode.containsKey(zetaCode)) {
                alias.Product2_Id__c = productByZetaCode.get(zetaCode);
            } else if (String.isNotBlank(zetaName)) {
                // leave product null if not found; still seed alias for review
                alias.Status__c = 'Suggested';
                alias.Match_Confidence__c = 50;
            }
            aliases.add(alias);
        }

        if (!aliases.isEmpty()) {
            Database.UpsertResult[] urs = Database.upsert(aliases, Distributor_Product_Alias__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
            Integer ok = 0;
            for (Database.UpsertResult ur : urs) {
                if (ur.isSuccess()) {
                    ok++;
                } else {
                    skipped++;
                }
            }
            result.aliasesUpserted = ok;
        } else {
            result.aliasesUpserted = 0;
        }
        result.aliasesSkipped = skipped;
        result.message =
            'Products upserted: ' +
            result.productsUpserted +
            '; aliases upserted: ' +
            result.aliasesUpserted +
            '; skipped: ' +
            skipped;
        return result;
    }

    /**
     * Seed aliases from CSV text uploaded in the Admin UI (same columns as Product Mapping sheet).
     */
    @AuraEnabled
    public static SeedResult seedFromCsv(String csvContent) {
        if (String.isBlank(csvContent)) {
            throw new AuraHandledException('CSV content is required.');
        }
        // Temporarily write via parsing inline (reuse static resource parser pattern)
        List<String> lines = csvContent.split('\\r?\\n');
        Map<String, Id> productByZetaCode = loadProductsByExternalId();
        List<Distributor_Product_Alias__c> aliases = new List<Distributor_Product_Alias__c>();
        Integer skipped = 0;
        Boolean headerSkipped = false;
        for (String line : lines) {
            if (String.isBlank(line)) {
                continue;
            }
            List<String> cols = parseCsvLine(line);
            if (!headerSkipped) {
                headerSkipped = true;
                if (cols[0] != null && cols[0].toLowerCase().contains('dist')) {
                    continue;
                }
            }
            if (cols.size() < 4) {
                skipped++;
                continue;
            }
            String dist = DistributorMatchingUtil.normalizeDistributorCode(cols[0]);
            String itemCode = DistributorMatchingUtil.normalizeCode(cols[1]);
            if (String.isBlank(dist) || String.isBlank(itemCode) || itemCode.equalsIgnoreCase('Item Code')) {
                skipped++;
                continue;
            }
            String zetaCode = cols[3] != null ? cols[3].trim() : null;
            Distributor_Product_Alias__c alias = new Distributor_Product_Alias__c(
                Distributor_Code__c = dist,
                Distributor_Item_Code__c = itemCode,
                Distributor_Item_Name__c = cols.size() > 2 ? cols[2] : null,
                Zeta_Code__c = zetaCode,
                Match_Confidence__c = 100,
                Match_Method__c = 'Seeded',
                Status__c = 'Confirmed',
                Unique_Key__c = DistributorMatchingUtil.buildProductUniqueKey(dist, itemCode)
            );
            if (String.isNotBlank(zetaCode) && productByZetaCode.containsKey(zetaCode)) {
                alias.Product2_Id__c = productByZetaCode.get(zetaCode);
            }
            aliases.add(alias);
        }
        SeedResult result = new SeedResult();
        result.productsUpserted = 0;
        if (!aliases.isEmpty()) {
            Database.UpsertResult[] urs = Database.upsert(aliases, Distributor_Product_Alias__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
            Integer ok = 0;
            for (Database.UpsertResult ur : urs) {
                if (ur.isSuccess()) {
                    ok++;
                } else {
                    skipped++;
                }
            }
            result.aliasesUpserted = ok;
        } else {
            result.aliasesUpserted = 0;
        }
        result.aliasesSkipped = skipped;
        result.message = 'Aliases upserted: ' + result.aliasesUpserted;
        return result;
    }

    private static Integer ensureProductsFromSeed() {
        List<Product2> products = new List<Product2>();
        for (String line : readCsvLines('ZetaProductListSeed')) {
            List<String> cols = parseCsvLine(line);
            if (cols.size() < 6) {
                continue;
            }
            String zetaCode = cols[4] != null ? cols[4].trim() : null;
            String zetaName = cols[5] != null ? cols[5].trim() : null;
            if (String.isBlank(zetaCode) || zetaCode.equalsIgnoreCase('Zeta_Code') || zetaCode.equalsIgnoreCase('Zeta Code')) {
                continue;
            }
            Boolean isActive = cols.size() > 11 && cols[11] != null && cols[11].equalsIgnoreCase('Yes');
            Product2 p = new Product2(
                Name = String.isBlank(zetaName) ? zetaCode : zetaName,
                ProductCode = zetaCode,
                IsActive = isActive,
                External_ID__c = zetaCode
            );
            products.add(p);
        }
        if (products.isEmpty()) {
            return 0;
        }
        Database.UpsertResult[] urs = Database.upsert(products, Product2.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        Integer ok = 0;
        for (Database.UpsertResult ur : urs) {
            if (ur.isSuccess()) {
                ok++;
            }
        }
        return ok;
    }

    private static Map<String, Id> loadProductsByExternalId() {
        Map<String, Id> byCode = new Map<String, Id>();
        for (Product2 p : [
            SELECT Id, External_ID__c, ProductCode
            FROM Product2
            WHERE External_ID__c != NULL OR ProductCode != NULL
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            if (String.isNotBlank(p.External_ID__c)) {
                byCode.put(p.External_ID__c, p.Id);
            }
            if (String.isNotBlank(p.ProductCode) && !byCode.containsKey(p.ProductCode)) {
                byCode.put(p.ProductCode, p.Id);
            }
        }
        return byCode;
    }

    private static List<String> readCsvLines(String staticResourceName) {
        List<StaticResource> resources = [
            SELECT Id, Body
            FROM StaticResource
            WHERE Name = :staticResourceName
            LIMIT 1
        ];
        if (resources.isEmpty() || resources[0].Body == null) {
            return new List<String>();
        }
        String body = resources[0].Body.toString();
        List<String> lines = new List<String>();
        Boolean first = true;
        for (String line : body.split('\\r?\\n')) {
            if (first) {
                first = false;
                continue; // skip header
            }
            if (String.isNotBlank(line)) {
                lines.add(line);
            }
        }
        return lines;
    }

    @TestVisible
    private static List<String> parseCsvLine(String line) {
        List<String> result = new List<String>();
        if (line == null) {
            return result;
        }
        Boolean inQuotes = false;
        String current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);
        return result;
    }
}