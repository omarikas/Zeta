/**
 * Deletes Account affiliations, common Account children, then Accounts.
 * Chained phases via finish().
 */
public without sharing class AccountWipeBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String PHASE_AFFILIATIONS = 'AFFILIATIONS';
    public static final String PHASE_ATF = 'ATF';
    public static final String PHASE_ATP = 'ATP';
    public static final String PHASE_VISIT_FEEDBACK = 'VISIT_FEEDBACK';
    public static final String PHASE_VISIT_ATTENDEES = 'VISIT_ATTENDEES';
    public static final String PHASE_VISITS = 'VISITS';
    public static final String PHASE_BRICK_PHARMACY = 'BRICK_PHARMACY';
    public static final String PHASE_WITHDRAWALS = 'WITHDRAWALS';
    public static final String PHASE_ACCOUNT_GOALS = 'ACCOUNT_GOALS';
    public static final String PHASE_TIME_CARD_TARGETS = 'TIME_CARD_TARGETS';
    public static final String PHASE_MEETING_LOCATIONS = 'MEETING_LOCATIONS';
    public static final String PHASE_SPEAKERS = 'SPEAKERS';
    public static final String PHASE_CLM_SESSIONS = 'CLM_SESSIONS';
    public static final String PHASE_LOCATIONS = 'LOCATIONS';
    public static final String PHASE_CASES = 'CASES';
    public static final String PHASE_OPPORTUNITIES = 'OPPORTUNITIES';
    public static final String PHASE_ACCOUNTS = 'ACCOUNTS';

    private String currentPhase;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private List<String> errorSamples = new List<String>();

    public AccountWipeBatch() {
        this(PHASE_AFFILIATIONS);
    }

    public AccountWipeBatch(String phase) {
        this.currentPhase = phase;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (currentPhase == PHASE_AFFILIATIONS) {
            return Database.getQueryLocator('SELECT Id FROM Account_Affiliation__c');
        }
        if (currentPhase == PHASE_ATF) {
            return Database.getQueryLocator('SELECT Id FROM Account_Territory_Fields__c');
        }
        if (currentPhase == PHASE_ATP) {
            return Database.getQueryLocator('SELECT Id FROM Account_Territory_Product_Fields__c');
        }
        if (currentPhase == PHASE_VISIT_FEEDBACK) {
            return Database.getQueryLocator('SELECT Id FROM Visit_Product_Survey_Feedback__c');
        }
        if (currentPhase == PHASE_VISIT_ATTENDEES) {
            return Database.getQueryLocator('SELECT Id FROM Visit_Attendee__c');
        }
        if (currentPhase == PHASE_VISITS) {
            return Database.getQueryLocator('SELECT Id FROM Visit__c');
        }
        if (currentPhase == PHASE_BRICK_PHARMACY) {
            return Database.getQueryLocator('SELECT Id FROM Brick_Pharmacy__c');
        }
        if (currentPhase == PHASE_WITHDRAWALS) {
            return Database.getQueryLocator('SELECT Id FROM Pharmacy_Sales_Withdrawal__c');
        }
        if (currentPhase == PHASE_ACCOUNT_GOALS) {
            return Database.getQueryLocator('SELECT Id FROM Pharma_Project_Account_Goal__c');
        }
        if (currentPhase == PHASE_TIME_CARD_TARGETS) {
            return Database.getQueryLocator('SELECT Id FROM Employee_Time_Card_Account_Target__c');
        }
        if (currentPhase == PHASE_MEETING_LOCATIONS) {
            return Database.getQueryLocator('SELECT Id FROM Meeting_Location__c');
        }
        if (currentPhase == PHASE_SPEAKERS) {
            return Database.getQueryLocator('SELECT Id FROM Speaker__c');
        }
        if (currentPhase == PHASE_CLM_SESSIONS) {
            return Database.getQueryLocator('SELECT Id FROM CLM_Presentation_Session__c');
        }
        if (currentPhase == PHASE_LOCATIONS) {
            return Database.getQueryLocator('SELECT Id FROM Location__c WHERE Account__c != null');
        }
        if (currentPhase == PHASE_CASES) {
            return Database.getQueryLocator('SELECT Id FROM Case WHERE AccountId != null');
        }
        if (currentPhase == PHASE_OPPORTUNITIES) {
            return Database.getQueryLocator('SELECT Id, StageName, IsWon FROM Opportunity WHERE AccountId != null');
        }
        return Database.getQueryLocator('SELECT Id FROM Account');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (currentPhase == PHASE_LOCATIONS) {
            for (SObject row : scope) {
                row.put('Account__c', null);
            }
            Database.SaveResult[] urs = Database.update(scope, false, AccessLevel.SYSTEM_MODE);
            tallySave(urs);
            return;
        }
        if (currentPhase == PHASE_OPPORTUNITIES) {
            for (SObject row : scope) {
                Opportunity o = (Opportunity) row;
                if (o.IsWon) {
                    o.StageName = 'Prospecting';
                }
            }
            Database.update(scope, false, AccessLevel.SYSTEM_MODE);
        }

        Database.DeleteResult[] results = Database.delete(scope, false, AccessLevel.SYSTEM_MODE);
        tallyDelete(results);
        List<Id> deletedIds = new List<Id>();
        for (Database.DeleteResult dr : results) {
            if (dr.isSuccess()) {
                deletedIds.add(dr.getId());
            }
        }
        if (!deletedIds.isEmpty()) {
            try {
                Database.emptyRecycleBin(deletedIds);
            } catch (Exception e) {
                // best-effort
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        String next = nextPhase(currentPhase);
        if (next != null) {
            Database.executeBatch(new AccountWipeBatch(next), 200);
        }
    }

    private static String nextPhase(String phase) {
        if (phase == PHASE_AFFILIATIONS) return PHASE_ATF;
        if (phase == PHASE_ATF) return PHASE_ATP;
        if (phase == PHASE_ATP) return PHASE_VISIT_FEEDBACK;
        if (phase == PHASE_VISIT_FEEDBACK) return PHASE_VISIT_ATTENDEES;
        if (phase == PHASE_VISIT_ATTENDEES) return PHASE_VISITS;
        if (phase == PHASE_VISITS) return PHASE_BRICK_PHARMACY;
        if (phase == PHASE_BRICK_PHARMACY) return PHASE_WITHDRAWALS;
        if (phase == PHASE_WITHDRAWALS) return PHASE_ACCOUNT_GOALS;
        if (phase == PHASE_ACCOUNT_GOALS) return PHASE_TIME_CARD_TARGETS;
        if (phase == PHASE_TIME_CARD_TARGETS) return PHASE_MEETING_LOCATIONS;
        if (phase == PHASE_MEETING_LOCATIONS) return PHASE_SPEAKERS;
        if (phase == PHASE_SPEAKERS) return PHASE_CLM_SESSIONS;
        if (phase == PHASE_CLM_SESSIONS) return PHASE_LOCATIONS;
        if (phase == PHASE_LOCATIONS) return PHASE_CASES;
        if (phase == PHASE_CASES) return PHASE_OPPORTUNITIES;
        if (phase == PHASE_OPPORTUNITIES) return PHASE_ACCOUNTS;
        return null;
    }

    private void tallySave(Database.SaveResult[] results) {
        if (results == null) {
            return;
        }
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                successCount++;
            } else {
                errorCount++;
                if (errorSamples.size() < 25) {
                    errorSamples.add(String.valueOf(sr.getErrors()));
                }
            }
        }
    }

    private void tallyDelete(Database.DeleteResult[] results) {
        if (results == null) {
            return;
        }
        for (Database.DeleteResult dr : results) {
            if (dr.isSuccess()) {
                successCount++;
            } else {
                errorCount++;
                if (errorSamples.size() < 25) {
                    String msg = dr.getErrors().isEmpty() ? 'delete failed' : dr.getErrors()[0].getMessage();
                    errorSamples.add(msg);
                }
            }
        }
    }
}