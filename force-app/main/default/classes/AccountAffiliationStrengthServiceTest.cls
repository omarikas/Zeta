@IsTest
private class AccountAffiliationStrengthServiceTest {
  @TestSetup
  static void setupData() {
    insert new List<Account>{
      new Account(Name = 'HCP Aff Test'),
      new Account(Name = 'Attendee Aff Test'),
      new Account(Name = 'Pharmacy Aff Test')
    };
  }

  @IsTest
  static void upsertAndStrengthen_createsThenStrengthens() {
    Account hcp = [SELECT Id FROM Account WHERE Name = 'HCP Aff Test' LIMIT 1];
    Account attendee = [SELECT Id FROM Account WHERE Name = 'Attendee Aff Test' LIMIT 1];

    Test.startTest();
    Account_Affiliation__c first = AccountAffiliationStrengthService.upsertAndStrengthen(
      hcp.Id,
      attendee.Id,
      AccountAffiliationStrengthService.SOURCE_VISIT_ATTENDEE
    );
    Account_Affiliation__c second = AccountAffiliationStrengthService.upsertAndStrengthen(
      attendee.Id,
      hcp.Id,
      AccountAffiliationStrengthService.SOURCE_VISIT_ATTENDEE
    );
    Test.stopTest();

    System.assertEquals(1, first.Score__c);
    System.assertEquals('Weak', first.Strength__c);
    System.assertEquals('Visit Attendee', first.Initiation_Source__c);
    System.assertEquals(2, second.Score__c);
    System.assertEquals('Weak', second.Strength__c);
    System.assertEquals(first.Id, second.Id);
  }

  @IsTest
  static void strengthForScore_thresholds() {
    System.assertEquals('Weak', AccountAffiliationStrengthService.strengthForScore(1));
    System.assertEquals('Weak', AccountAffiliationStrengthService.strengthForScore(2));
    System.assertEquals('Medium', AccountAffiliationStrengthService.strengthForScore(3));
    System.assertEquals('Medium', AccountAffiliationStrengthService.strengthForScore(5));
    System.assertEquals('Strong', AccountAffiliationStrengthService.strengthForScore(6));
  }

  @IsTest
  static void pharmacyVisit_setsInitiationSource() {
    Account hcp = [SELECT Id FROM Account WHERE Name = 'HCP Aff Test' LIMIT 1];
    Account pharmacy = [SELECT Id FROM Account WHERE Name = 'Pharmacy Aff Test' LIMIT 1];

    Test.startTest();
    Account_Affiliation__c row = AccountAffiliationStrengthService.upsertAndStrengthen(
      hcp.Id,
      pharmacy.Id,
      AccountAffiliationStrengthService.SOURCE_PHARMACY_VISIT
    );
    Test.stopTest();

    System.assertEquals('Pharmacy Visit', row.Initiation_Source__c);
    System.assertEquals(1, row.Score__c);
  }
}
