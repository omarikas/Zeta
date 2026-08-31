/**
 * Batch upsert for Brick_Territory_Alignment__c rows from a JSON static resource chunk.
 * Uses String payloads so batch serialization cannot drop custom-type fields.
 */
public without sharing class ZetaOrganogramAlignmentBatch implements Database.Batchable<String>, Database.Stateful {
    private final String resourceName;
    @TestVisible private Integer successCount = 0;
    @TestVisible private Integer errorCount = 0;
    @TestVisible private static String testAlignmentsJson;

    public class AlignRow {
        public String externalId;
        public String brickExternalId;
        public String territoryExternalId;
        public Decimal share;
        public Boolean isActive;
    }

    private class AlignmentsPayload {
        public List<AlignRow> alignments;
    }

    public ZetaOrganogramAlignmentBatch(String resourceName) {
        this.resourceName = resourceName;
    }

    public Iterable<String> start(Database.BatchableContext context) {
        String body = testAlignmentsJson;
        if (String.isBlank(body)) {
            StaticResource resource = [
                SELECT Body
                FROM StaticResource
                WHERE Name = :resourceName
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            body = resource.Body.toString();
        }
        AlignmentsPayload payload = (AlignmentsPayload) JSON.deserialize(
            body,
            AlignmentsPayload.class
        );
        List<String> rows = new List<String>();
        if (payload.alignments != null) {
            for (AlignRow row : payload.alignments) {
                rows.add(JSON.serialize(row));
            }
        }
        return rows;
    }

    public void execute(Database.BatchableContext context, List<String> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<AlignRow> rows = new List<AlignRow>();
        for (String payload : scope) {
            rows.add((AlignRow) JSON.deserialize(payload, AlignRow.class));
        }

        Set<String> brickExtIds = new Set<String>();
        Set<String> terrExtIds = new Set<String>();
        for (AlignRow row : rows) {
            if (String.isNotBlank(row.brickExternalId)) {
                brickExtIds.add(row.brickExternalId);
            }
            if (String.isNotBlank(row.territoryExternalId)) {
                terrExtIds.add(row.territoryExternalId);
            }
        }

        Map<String, Id> brickIds = new Map<String, Id>();
        for (Brick__c brick : [
            SELECT Id, External_ID__c
            FROM Brick__c
            WHERE External_ID__c IN :brickExtIds
            WITH SYSTEM_MODE
        ]) {
            brickIds.put(brick.External_ID__c, brick.Id);
        }

        Map<String, Id> territoryIds = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :terrExtIds
            WITH SYSTEM_MODE
        ]) {
            territoryIds.put(territory.External_ID__c, territory.Id);
        }

        List<Brick_Territory_Alignment__c> records = new List<Brick_Territory_Alignment__c>();
        for (AlignRow row : rows) {
            Id brickId = brickIds.get(row.brickExternalId);
            Id territoryId = territoryIds.get(row.territoryExternalId);
            if (brickId == null || territoryId == null || String.isBlank(row.externalId)) {
                errorCount++;
                continue;
            }
            records.add(
                new Brick_Territory_Alignment__c(
                    Brick__c = brickId,
                    External_ID__c = row.externalId,
                    Territory_External_ID__c = row.territoryExternalId,
                    Territory2_Id__c = String.valueOf(territoryId),
                    Share__c = row.share,
                    Is_Active__c = row.isActive == null ? true : row.isActive
                )
            );
        }

        if (records.isEmpty()) {
            return;
        }

        Database.UpsertResult[] upserts = Database.upsert(
            records,
            Brick_Territory_Alignment__c.External_ID__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                successCount++;
            } else {
                errorCount++;
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(
            LoggingLevel.INFO,
            'ZetaOrganogramAlignmentBatch ' +
                resourceName +
                ' success=' +
                successCount +
                ' errors=' +
                errorCount
        );
    }
}