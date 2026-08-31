/**
 * Aligns accounts to Position territories based on Brick_Territory_Alignment__c.
 * Uses ObjectTerritory2Association so ETM sharing and targeting can resolve brick geography.
 */
public without sharing class BrickTerritoryAlignmentService {
    public class AlignResult {
        @AuraEnabled public Integer accountsProcessed;
        @AuraEnabled public Integer associationsCreated;
        @AuraEnabled public Integer associationsSkipped;
        @AuraEnabled public String message;
    }

    public static AlignResult alignAccountsForBrick(Set<Id> brickIds) {
        AlignResult result = new AlignResult();
        result.accountsProcessed = 0;
        result.associationsCreated = 0;
        result.associationsSkipped = 0;
        if (brickIds == null || brickIds.isEmpty()) {
            result.message = 'No bricks provided.';
            return result;
        }

        Map<Id, Set<Id>> territoryIdsByBrick = loadTerritoryIdsByBrick(brickIds);
        if (territoryIdsByBrick.isEmpty()) {
            result.message = 'No active brick-territory alignments found.';
            return result;
        }

        Map<Id, Set<Id>> brickIdsByAccount = loadBrickIdsByAccount(brickIds);
        if (brickIdsByAccount.isEmpty()) {
            result.message = 'No accounts linked to the provided bricks.';
            return result;
        }

        Set<Id> accountIds = brickIdsByAccount.keySet();
        Set<Id> allTerritoryIds = new Set<Id>();
        for (Set<Id> territoryIds : territoryIdsByBrick.values()) {
            allTerritoryIds.addAll(territoryIds);
        }

        Set<String> existingKeys = new Set<String>();
        for (ObjectTerritory2Association existing : [
            SELECT ObjectId, Territory2Id
            FROM ObjectTerritory2Association
            WHERE ObjectId IN :accountIds AND Territory2Id IN :allTerritoryIds
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(String.valueOf(existing.ObjectId) + ':' + String.valueOf(existing.Territory2Id));
        }

        List<ObjectTerritory2Association> toInsert = new List<ObjectTerritory2Association>();
        for (Id accountId : brickIdsByAccount.keySet()) {
            result.accountsProcessed++;
            for (Id brickId : brickIdsByAccount.get(accountId)) {
                Set<Id> territoryIds = territoryIdsByBrick.get(brickId);
                if (territoryIds == null) {
                    continue;
                }
                for (Id territoryId : territoryIds) {
                    String key = String.valueOf(accountId) + ':' + String.valueOf(territoryId);
                    if (existingKeys.contains(key)) {
                        result.associationsSkipped++;
                        continue;
                    }
                    existingKeys.add(key);
                    toInsert.add(
                        new ObjectTerritory2Association(
                            ObjectId = accountId,
                            Territory2Id = territoryId,
                            AssociationCause = 'Territory2Manual'
                        )
                    );
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] saves = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saves) {
                if (sr.isSuccess()) {
                    result.associationsCreated++;
                } else {
                    result.associationsSkipped++;
                }
            }
        }

        result.message =
            'Processed ' +
            result.accountsProcessed +
            ' accounts; created ' +
            result.associationsCreated +
            ' associations.';
        return result;
    }

    public static void alignAccountsForBrickIds(List<Id> brickIds) {
        if (brickIds == null || brickIds.isEmpty()) {
            return;
        }
        alignAccountsForBrick(new Set<Id>(brickIds));
    }

    private static Map<Id, Set<Id>> loadTerritoryIdsByBrick(Set<Id> brickIds) {
        Map<Id, Set<Id>> territoryIdsByBrick = new Map<Id, Set<Id>>();
        for (Brick_Territory_Alignment__c alignment : [
            SELECT Brick__c, Territory2_Id__c
            FROM Brick_Territory_Alignment__c
            WHERE Brick__c IN :brickIds AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            if (String.isBlank(alignment.Territory2_Id__c)) {
                continue;
            }
            Id territoryId;
            try {
                territoryId = (Id) alignment.Territory2_Id__c;
            } catch (Exception ex) {
                continue;
            }
            if (!territoryIdsByBrick.containsKey(alignment.Brick__c)) {
                territoryIdsByBrick.put(alignment.Brick__c, new Set<Id>());
            }
            territoryIdsByBrick.get(alignment.Brick__c).add(territoryId);
        }
        return territoryIdsByBrick;
    }

    private static Map<Id, Set<Id>> loadBrickIdsByAccount(Set<Id> brickIds) {
        Map<Id, Set<Id>> brickIdsByAccount = new Map<Id, Set<Id>>();

        if (Schema.SObjectType.Account.fields.getMap().containsKey('Brick__c')) {
            String soql = 'SELECT Id, Brick__c FROM Account WHERE Brick__c IN :brickIds WITH SYSTEM_MODE';
            for (Account accountRow : Database.query(soql)) {
                Id brickId = (Id) accountRow.get('Brick__c');
                if (brickId == null) {
                    continue;
                }
                if (!brickIdsByAccount.containsKey(accountRow.Id)) {
                    brickIdsByAccount.put(accountRow.Id, new Set<Id>());
                }
                brickIdsByAccount.get(accountRow.Id).add(brickId);
            }
        }

        for (Brick_Pharmacy__c membership : [
            SELECT Pharmacy_Account__c, Brick__c
            FROM Brick_Pharmacy__c
            WHERE Brick__c IN :brickIds AND Is_Active__c = TRUE AND Pharmacy_Account__c != NULL
            WITH SYSTEM_MODE
        ]) {
            if (!brickIdsByAccount.containsKey(membership.Pharmacy_Account__c)) {
                brickIdsByAccount.put(membership.Pharmacy_Account__c, new Set<Id>());
            }
            brickIdsByAccount.get(membership.Pharmacy_Account__c).add(membership.Brick__c);
        }

        return brickIdsByAccount;
    }
}