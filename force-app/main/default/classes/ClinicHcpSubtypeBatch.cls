/**
 * Ensures CLINIC-* practice sites use Institution_HCO + Subtype Clinic.
 */
public class ClinicHcpSubtypeBatch implements Database.Batchable<SObject>, Database.Stateful {
  public Integer updatedCount = 0;

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id, RecordTypeId, Institution_Type__c
        FROM Account
        WHERE External_ID__c LIKE 'CLINIC-%' AND IsPersonAccount = FALSE
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    Id clinicRt = AccountMasterImportUtil.clinicHcpRecordTypeId();
    for (Account account : scope) {
      account.RecordTypeId = clinicRt;
      if (String.isBlank(account.Institution_Type__c)) {
        account.Institution_Type__c = 'Clinic';
      }
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
    System.debug(LoggingLevel.INFO, 'ClinicHcpSubtypeBatch updated=' + updatedCount);
  }
}