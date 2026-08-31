/**
 * Loads production organogram territories and brick masters from Static Resource
 * ZetaOrganogramTerritories, then queues alignment batches for Brick_Territory_Alignment__c.
 * Idempotent: upserts by External_ID__c. Does not create demo users or accounts.
 */
public without sharing class ZetaOrganogramTerritoryLoader {
    private static final String TERRITORIES_RESOURCE = 'ZetaOrganogramTerritories';
    private static final List<String> ALIGNMENT_RESOURCES = new List<String>{
        'ZetaOrganogramAlignments01',
        'ZetaOrganogramAlignments02',
        'ZetaOrganogramAlignments03',
        'ZetaOrganogramAlignments04',
        'ZetaOrganogramAlignments05',
        'ZetaOrganogramAlignments06'
    };

    @TestVisible private static String testTerritoriesJson;
    @TestVisible private static Boolean skipAlignmentQueue = false;

    public class LoadResult {
        @AuraEnabled public Id headOfficeId;
        @AuraEnabled public Integer businessUnitsUpserted;
        @AuraEnabled public Integer linesUpserted;
        @AuraEnabled public Integer districtsUpserted;
        @AuraEnabled public Integer positionsUpserted;
        @AuraEnabled public Integer bricksUpserted;
        @AuraEnabled public Integer alignmentBatchesQueued;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> errors;
    }

    private class TerritoryNode {
        public String externalId;
        public String name;
        public String developerName;
        public String parentExternalId;
        public String territoryType;
    }

    private class BrickNode {
        public String externalId;
        public String name;
        public String dataSource;
        public Boolean isActive;
    }

    private class TerritoriesPayload {
        public TerritoryNode headOffice;
        public List<TerritoryNode> businessUnits;
        public List<TerritoryNode> lines;
        public List<TerritoryNode> districts;
        public List<TerritoryNode> positions;
        public List<BrickNode> bricks;
    }

    @AuraEnabled
    public static LoadResult loadTerritoriesAndQueueAlignments() {
        LoadResult result = loadTerritoriesOnly();
        if (result.headOfficeId == null) {
            return result;
        }
        // Territory2 is a setup object; Brick__c DML must run in a separate transaction.
        if (!skipAlignmentQueue) {
            System.enqueueJob(new ZetaOrganogramBrickLoadQueueable());
            result.message = result.message + ' Brick/alignment load queued.';
        }
        return result;
    }

    @AuraEnabled
    public static LoadResult loadTerritoriesOnly() {
        LoadResult result = new LoadResult();
        result.errors = new List<String>();
        result.businessUnitsUpserted = 0;
        result.linesUpserted = 0;
        result.districtsUpserted = 0;
        result.positionsUpserted = 0;
        result.bricksUpserted = 0;
        result.alignmentBatchesQueued = 0;

        TerritoriesPayload payload = parseTerritoriesPayload();
        Territory2Model model = resolveModel();
        Territory2Type territoryType = resolveTerritoryType();

        Map<String, Id> idsByExt = new Map<String, Id>();
        result.headOfficeId = upsertTerritoryNode(
            payload.headOffice,
            null,
            model.Id,
            territoryType.Id,
            idsByExt,
            result.errors
        );
        if (result.headOfficeId == null) {
            result.message = 'Head Office upsert failed.';
            return result;
        }

        result.businessUnitsUpserted = upsertLevelBulk(
            payload.businessUnits,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.linesUpserted = upsertLevelBulk(
            payload.lines,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.districtsUpserted = upsertLevelBulk(
            payload.districts,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.positionsUpserted = upsertLevelBulk(
            payload.positions,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );

        result.message =
            'Upserted HO + ' +
            result.businessUnitsUpserted +
            ' BUs, ' +
            result.linesUpserted +
            ' lines, ' +
            result.districtsUpserted +
            ' districts, ' +
            result.positionsUpserted +
            ' positions.';
        return result;
    }

    @AuraEnabled
    public static LoadResult loadBricksAndQueueAlignments() {
        LoadResult result = new LoadResult();
        result.errors = new List<String>();
        result.bricksUpserted = 0;
        result.alignmentBatchesQueued = 0;

        TerritoriesPayload payload = parseTerritoriesPayload();
        result.bricksUpserted = upsertBricks(payload.bricks, result.errors);
        if (!skipAlignmentQueue) {
            result.alignmentBatchesQueued = queueAlignmentBatches(result.errors);
        }
        result.message =
            'Upserted ' +
            result.bricksUpserted +
            ' bricks. Queued ' +
            result.alignmentBatchesQueued +
            ' alignment batches.';
        return result;
    }

    public static Integer queueAlignmentBatches(List<String> errors) {
        Integer queued = 0;
        for (String resourceName : ALIGNMENT_RESOURCES) {
            try {
                Id jobId = Database.executeBatch(
                    new ZetaOrganogramAlignmentBatch(resourceName),
                    200
                );
                if (jobId != null) {
                    queued++;
                }
            } catch (Exception ex) {
                if (errors != null) {
                    errors.add(resourceName + ': ' + ex.getMessage());
                }
            }
        }
        return queued;
    }

    public static List<String> alignmentResourceNames() {
        return new List<String>(ALIGNMENT_RESOURCES);
    }

    private static TerritoriesPayload parseTerritoriesPayload() {
        String body = testTerritoriesJson;
        if (String.isBlank(body)) {
            StaticResource resource = [
                SELECT Body
                FROM StaticResource
                WHERE Name = :TERRITORIES_RESOURCE
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            body = resource.Body.toString();
        }
        return (TerritoriesPayload) JSON.deserialize(body, TerritoriesPayload.class);
    }

    private static Integer upsertLevelBulk(
        List<TerritoryNode> nodes,
        Map<String, Id> idsByExt,
        Id modelId,
        Id typeId,
        List<String> errors
    ) {
        if (nodes == null || nodes.isEmpty()) {
            return 0;
        }

        Set<String> externalIds = new Set<String>();
        Set<String> developerNames = new Set<String>();
        for (TerritoryNode node : nodes) {
            if (String.isBlank(node.externalId)) {
                continue;
            }
            externalIds.add(node.externalId);
            if (String.isNotBlank(node.developerName)) {
                developerNames.add(sanitizeDeveloperName(node.developerName, node.externalId));
            }
        }

        Map<String, Territory2> existingByExt = new Map<String, Territory2>();
        Map<String, Territory2> existingByDev = new Map<String, Territory2>();
        for (Territory2 territory : [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
            FROM Territory2
            WHERE External_ID__c IN :externalIds OR DeveloperName IN :developerNames
            WITH SYSTEM_MODE
        ]) {
            if (String.isNotBlank(territory.External_ID__c)) {
                existingByExt.put(territory.External_ID__c, territory);
            }
            if (String.isNotBlank(territory.DeveloperName) && !existingByDev.containsKey(territory.DeveloperName)) {
                existingByDev.put(territory.DeveloperName, territory);
            }
        }

        List<Territory2> toInsert = new List<Territory2>();
        List<Territory2> toUpdate = new List<Territory2>();
        List<TerritoryNode> insertNodes = new List<TerritoryNode>();

        for (TerritoryNode node : nodes) {
            if (String.isBlank(node.externalId)) {
                errors.add('Blank territory node.');
                continue;
            }
            Id parentId = null;
            if (String.isNotBlank(node.parentExternalId)) {
                parentId = idsByExt.get(node.parentExternalId);
                if (parentId == null) {
                    errors.add('Missing parent ' + node.parentExternalId + ' for ' + node.externalId);
                    continue;
                }
            }

            String developerName = sanitizeDeveloperName(node.developerName, node.externalId);
            Territory2 existing = existingByExt.get(node.externalId);
            if (existing == null) {
                existing = existingByDev.get(developerName);
            }

            if (existing != null) {
                existing.Name = node.name;
                existing.ParentTerritory2Id = parentId;
                existing.External_ID__c = node.externalId;
                applyTerritoryType(existing, node.territoryType);
                toUpdate.add(existing);
                idsByExt.put(node.externalId, existing.Id);
            } else {
                Territory2 territory = new Territory2(
                    Name = node.name,
                    DeveloperName = developerName,
                    Territory2ModelId = modelId,
                    Territory2TypeId = typeId,
                    ParentTerritory2Id = parentId,
                    External_ID__c = node.externalId
                );
                applyTerritoryType(territory, node.territoryType);
                toInsert.add(territory);
                insertNodes.add(node);
            }
        }

        Integer success = 0;
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updates = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < updates.size(); i++) {
                if (updates[i].isSuccess()) {
                    success++;
                    idsByExt.put(toUpdate[i].External_ID__c, toUpdate[i].Id);
                } else {
                    errors.add(toUpdate[i].External_ID__c + ': ' + updates[i].getErrors()[0].getMessage());
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] inserts = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < inserts.size(); i++) {
                if (inserts[i].isSuccess()) {
                    success++;
                    idsByExt.put(insertNodes[i].externalId, inserts[i].getId());
                } else {
                    errors.add(insertNodes[i].externalId + ': ' + inserts[i].getErrors()[0].getMessage());
                }
            }
        }
        return success;
    }

    private static Id upsertTerritoryNode(
        TerritoryNode node,
        Id parentId,
        Id modelId,
        Id typeId,
        Map<String, Id> idsByExt,
        List<String> errors
    ) {
        if (node == null || String.isBlank(node.externalId)) {
            errors.add('Blank territory node.');
            return null;
        }

        try {
            Territory2 existing = findExistingTerritory(node);
            if (existing != null) {
                existing.Name = node.name;
                existing.ParentTerritory2Id = parentId;
                existing.External_ID__c = node.externalId;
                applyTerritoryType(existing, node.territoryType);
                update as system existing;
                idsByExt.put(node.externalId, existing.Id);
                return existing.Id;
            }

            Territory2 territory = new Territory2(
                Name = node.name,
                DeveloperName = sanitizeDeveloperName(node.developerName, node.externalId),
                Territory2ModelId = modelId,
                Territory2TypeId = typeId,
                ParentTerritory2Id = parentId,
                External_ID__c = node.externalId
            );
            applyTerritoryType(territory, node.territoryType);
            insert as system territory;
            idsByExt.put(node.externalId, territory.Id);
            return territory.Id;
        } catch (Exception ex) {
            errors.add(node.externalId + ': ' + ex.getMessage());
            return null;
        }
    }

    private static Territory2 findExistingTerritory(TerritoryNode node) {
        List<Territory2> byExt = [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
            FROM Territory2
            WHERE External_ID__c = :node.externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!byExt.isEmpty()) {
            return byExt[0];
        }

        if (String.isNotBlank(node.developerName)) {
            List<Territory2> byDev = [
                SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
                FROM Territory2
                WHERE DeveloperName = :node.developerName
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!byDev.isEmpty()) {
                return byDev[0];
            }
        }

        if (node.externalId == 'TERR_HEAD_OFFICE') {
            List<Territory2> byName = [
                SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
                FROM Territory2
                WHERE Name = 'Head Office'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!byName.isEmpty()) {
                return byName[0];
            }
        }
        return null;
    }

    private static Integer upsertBricks(List<BrickNode> bricks, List<String> errors) {
        if (bricks == null || bricks.isEmpty()) {
            return 0;
        }
        List<Brick__c> records = new List<Brick__c>();
        for (BrickNode brick : bricks) {
            Brick__c row = new Brick__c(
                Name = brick.name,
                External_ID__c = brick.externalId,
                Is_Active__c = brick.isActive == null ? true : brick.isActive
            );
            if (Schema.SObjectType.Brick__c.fields.getMap().containsKey('Data_Source__c')) {
                row.put('Data_Source__c', String.isBlank(brick.dataSource) ? 'IQVIA IMS' : brick.dataSource);
            }
            records.add(row);
        }

        Integer success = 0;
        for (Integer start = 0; start < records.size(); start += 200) {
            Integer endIdx = Math.min(start + 200, records.size());
            List<Brick__c> batch = new List<Brick__c>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(records[i]);
            }
            Database.UpsertResult[] upserts = Database.upsert(
                batch,
                Brick__c.External_ID__c,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Integer i = 0; i < upserts.size(); i++) {
                if (upserts[i].isSuccess()) {
                    success++;
                } else {
                    errors.add(
                        batch[i].External_ID__c +
                            ': ' +
                            upserts[i].getErrors()[0].getMessage()
                    );
                }
            }
        }
        return success;
    }

    private static void applyTerritoryType(Territory2 territory, String territoryType) {
        if (!Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            return;
        }
        if (String.isBlank(territoryType)) {
            return;
        }
        territory.put('Territory_Type__c', territoryType);
    }

    private static String sanitizeDeveloperName(String developerName, String externalId) {
        String source = String.isNotBlank(developerName) ? developerName : externalId;
        String cleaned = source == null ? 'Territory' : source.replaceAll('[^A-Za-z0-9_]', '_');
        cleaned = cleaned.replaceAll('_+', '_');
        if (cleaned.length() == 0 || !cleaned.substring(0, 1).isAlpha()) {
            cleaned = 'T_' + cleaned;
        }
        return cleaned.left(80);
    }

    private static Territory2Type resolveTerritoryType() {
        List<Territory2Type> types = [
            SELECT Id, DeveloperName
            FROM Territory2Type
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (types.isEmpty()) {
            throw new AuraHandledException('No Territory2Type found. Enable Enterprise Territory Management first.');
        }
        return types[0];
    }

    private static Territory2Model resolveModel() {
        List<Territory2Model> existing = [
            SELECT Id, State, Name, DeveloperName
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Current_FY territory model not found.');
        }
        return existing[0];
    }
}