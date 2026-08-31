/**
 * Enriches Account.Maps_Phone_Number__c from Google Places (preferred) or OSM Overpass.
 */
public without sharing class AccountMapsPhoneBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
  public Integer foundCount = 0;
  public Integer notFoundCount = 0;
  public Integer errorCount = 0;

  public static Id run() {
    return AccountMapsPlacesService.runPhoneEnrichmentBatch();
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          BillingStreet,
          BillingCity,
          BillingCountry,
          BillingLatitude,
          BillingLongitude,
          Maps_Phone_Number__c,
          Maps_Place_Id__c
        FROM Account
        WHERE
          Maps_Phone_Number__c = NULL
          AND (
            BillingLatitude != NULL
            OR BillingStreet != NULL
            OR BillingCity != NULL
            OR Name != NULL
          )
        WITH SYSTEM_MODE
        ORDER BY BillingLatitude NULLS LAST
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    List<Account> updates = new List<Account>();
    for (Account acct : (List<Account>) scope) {
      AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccountRecord(
        acct
      );
      Account row = new Account(
        Id = acct.Id,
        Maps_Enrichment_Status__c = result.status,
        Maps_Last_Enriched__c = System.now()
      );
      if (String.isNotBlank(result.phone)) {
        row.Maps_Phone_Number__c = result.phone;
        foundCount++;
      } else if (result.status == 'Error' || result.status == 'Needs API Key') {
        errorCount++;
      } else {
        notFoundCount++;
      }
      if (String.isNotBlank(result.placeId)) {
        row.Maps_Place_Id__c = result.placeId;
      }
      updates.add(row);
    }
    if (!updates.isEmpty()) {
      Database.DmlOptions opts = new Database.DmlOptions();
      opts.duplicateRuleHeader.allowSave = true;
      opts.optAllOrNone = false;
      Database.update(updates, opts);
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(
      LoggingLevel.INFO,
      'AccountMapsPhoneBatch found=' +
        foundCount +
        ' notFound=' +
        notFoundCount +
        ' errors=' +
        errorCount
    );
  }
}