/**
 * Stamps Account Subtype = Doctor on loaded doctor accounts.
 */
public class DoctorSubtypeStampBatch implements Database.Batchable<SObject>, Database.Stateful {
  public Integer updatedCount = 0;

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id, Institution_Type__c
        FROM Account
        WHERE External_ID__c LIKE 'DOC-%'
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    for (Account account : scope) {
      account.Institution_Type__c = 'Doctor';
    }
    Database.DmlOptions opts = new Database.DmlOptions();
    opts.duplicateRuleHeader.allowSave = true;
    opts.optAllOrNone = false;
    for (Database.SaveResult result : Database.update(scope, opts)) {
      if (result.isSuccess()) {
        updatedCount++;
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(LoggingLevel.INFO, 'DoctorSubtypeStampBatch updated=' + updatedCount);
  }
}