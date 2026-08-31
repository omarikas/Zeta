/**
 * Aligns all Accounts to a target Territory2 via ObjectTerritory2Association
 * and Account_Territory_Fields__c (planner / accounts-tab visibility).
 */
public without sharing class AccountTerritoryAlignBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Id territory2Id;
    private Integer ot2aCreated = 0;
    private Integer atfCreated = 0;
    private Integer errors = 0;

    public AccountTerritoryAlignBatch(Id territory2Id) {
        this.territory2Id = territory2Id;
    }

    public static Id alignCurrentUserTerritory() {
        List<UserTerritory2Association> utas = [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId()
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (utas.isEmpty()) {
            throw new AuraHandledException('No territory assignment found for the current user.');
        }
        return Database.executeBatch(new AccountTerritoryAlignBatch(utas[0].Territory2Id), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Account');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> accountIds = new Map<Id, SObject>(scope).keySet();
        String territoryKey = String.valueOf(territory2Id);

        Set<Id> alreadyOt2a = new Set<Id>();
        for (ObjectTerritory2Association existing : [
            SELECT ObjectId
            FROM ObjectTerritory2Association
            WHERE ObjectId IN :accountIds AND Territory2Id = :territory2Id
            WITH SYSTEM_MODE
        ]) {
            alreadyOt2a.add(existing.ObjectId);
        }

        Set<Id> alreadyAtf = new Set<Id>();
        for (Account_Territory_Fields__c existing : [
            SELECT Account__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :accountIds AND Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
        ]) {
            alreadyAtf.add(existing.Account__c);
        }

        List<ObjectTerritory2Association> ot2aRows = new List<ObjectTerritory2Association>();
        List<Account_Territory_Fields__c> atfRows = new List<Account_Territory_Fields__c>();
        for (Id accountId : accountIds) {
            if (!alreadyOt2a.contains(accountId)) {
                ot2aRows.add(
                    new ObjectTerritory2Association(
                        ObjectId = accountId,
                        Territory2Id = territory2Id,
                        AssociationCause = 'Territory2Manual'
                    )
                );
            }
            if (!alreadyAtf.contains(accountId)) {
                atfRows.add(
                    new Account_Territory_Fields__c(
                        Account__c = accountId,
                        Territory2_Id__c = territoryKey,
                        Is_Active__c = true
                    )
                );
            }
        }

        if (!ot2aRows.isEmpty()) {
            Database.SaveResult[] otResults = Database.insert(ot2aRows, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : otResults) {
                if (sr.isSuccess()) {
                    ot2aCreated++;
                } else {
                    errors++;
                }
            }
        }

        if (!atfRows.isEmpty()) {
            Database.SaveResult[] atfResults = Database.insert(atfRows, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : atfResults) {
                if (sr.isSuccess()) {
                    atfCreated++;
                } else {
                    errors++;
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'AccountTerritoryAlignBatch done territory=' +
                territory2Id +
                ' ot2a=' +
                ot2aCreated +
                ' atf=' +
                atfCreated +
                ' errors=' +
                errors
        );
    }
}