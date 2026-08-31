/**
 * Strips leading numeric ID prefixes from Account.Name (e.g. "1000000240_Pharmacy")
 * when the real name follows an underscore. Source IDs stay on External_ID__c.
 */
public class AccountNameCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  public Integer updatedCount = 0;
  public Integer scannedCount = 0;

  public Database.QueryLocator start(Database.BatchableContext bc) {
    // Prefixed Excel names start with digits; filter precisely in execute().
    return Database.getQueryLocator(
      [
        SELECT Id, Name, External_ID__c
        FROM Account
        WHERE
          Name LIKE '0%'
          OR Name LIKE '1%'
          OR Name LIKE '2%'
          OR Name LIKE '3%'
          OR Name LIKE '4%'
          OR Name LIKE '5%'
          OR Name LIKE '6%'
          OR Name LIKE '7%'
          OR Name LIKE '8%'
          OR Name LIKE '9%'
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    List<Account> toUpdate = new List<Account>();
    for (Account account : scope) {
      scannedCount++;
      String cleaned = cleanPrefixedName(account.Name);
      if (cleaned != null && cleaned != account.Name) {
        account.Name = cleaned;
        toUpdate.add(account);
      }
    }
    if (!toUpdate.isEmpty()) {
      Database.DmlOptions opts = new Database.DmlOptions();
      opts.duplicateRuleHeader.allowSave = true;
      opts.optAllOrNone = false;
      List<Database.SaveResult> results = Database.update(toUpdate, opts);
      for (Database.SaveResult result : results) {
        if (result.isSuccess()) {
          updatedCount++;
        }
      }
    }
  }

  /** Test helper: run cleanup on an explicit account list. */
  @TestVisible
  private static Integer cleanAccounts(List<Account> accounts) {
    AccountNameCleanupBatch batch = new AccountNameCleanupBatch();
    batch.execute(null, accounts);
    return batch.updatedCount;
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(
      LoggingLevel.INFO,
      'AccountNameCleanupBatch scanned=' + scannedCount + ' updated=' + updatedCount
    );
  }

  @TestVisible
  private static String cleanPrefixedName(String rawName) {
    if (String.isBlank(rawName) || !rawName.contains('_')) {
      return rawName;
    }
    Integer idx = rawName.indexOf('_');
    if (idx <= 0 || idx >= rawName.length() - 1) {
      return rawName;
    }
    String prefix = rawName.substring(0, idx);
    String rest = rawName.substring(idx + 1).trim();
    if (String.isBlank(rest) || !prefix.isNumeric()) {
      return rawName;
    }
    return rest.length() > 255 ? rest.substring(0, 255) : rest;
  }
}