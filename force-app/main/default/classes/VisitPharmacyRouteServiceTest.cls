@IsTest
private class VisitPharmacyRouteServiceTest {
  @TestSetup
  static void setupData() {
    Id pharmacyRtId;
    List<RecordType> pharmacyTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy' AND IsActive = TRUE
      LIMIT 1
    ];
    if (!pharmacyTypes.isEmpty()) {
      pharmacyRtId = pharmacyTypes[0].Id;
    }

    Account hcp = new Account(Name = 'Route HCP');
    Account pharmacy = new Account(
      Name = 'Route Pharmacy In List',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357
    );
    if (pharmacyRtId != null) {
      pharmacy.RecordTypeId = pharmacyRtId;
    }
    insert new List<Account>{ hcp, pharmacy };

    insert new Visit__c(
      Account__c = hcp.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)'
    );
  }

  @IsTest
  static void scheduleAccountPharmacyOnRoute_createsVisitAndAffiliation() {
    Visit__c current = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Account pharmacy = [SELECT Id FROM Account WHERE Name = 'Route Pharmacy In List' LIMIT 1];

    Test.startTest();
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult result = VisitNeighbouringPharmacyRouteService.scheduleAccountPharmacyOnRoute(
      current.Id,
      pharmacy.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, result.visitId);
    System.assertEquals(pharmacy.Id, result.accountId);
    System.assertEquals(false, result.createdAccount);

    List<Account_Affiliation__c> affs = [
      SELECT Score__c, Initiation_Source__c, Strength__c
      FROM Account_Affiliation__c
      WHERE
        (Primary_Account__c = :current.Account__c AND Related_Account__c = :pharmacy.Id)
        OR (Primary_Account__c = :pharmacy.Id AND Related_Account__c = :current.Account__c)
    ];
    System.assertEquals(1, affs.size());
    System.assertEquals(1, affs[0].Score__c);
    System.assertEquals('Pharmacy Visit', affs[0].Initiation_Source__c);
  }

  @IsTest
  static void addExternalPharmacyToRoute_createsAccountVisitAndAffiliation() {
    Visit__c current = [SELECT Id, Account__c FROM Visit__c LIMIT 1];

    Test.startTest();
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult result = VisitNeighbouringPharmacyRouteService.addExternalPharmacyToRoute(
      current.Id,
      'node/999001',
      'OSM Pharmacy Test',
      '1 Nile St',
      'Cairo',
      null,
      '11511',
      'Egypt',
      null,
      30.05,
      31.24
    );
    Test.stopTest();

    System.assertEquals(true, result.createdAccount);
    System.assertNotEquals(null, result.visitId);
    System.assertNotEquals(null, result.accountId);

    Account created = [
      SELECT Name, Maps_Place_Id__c
      FROM Account
      WHERE Id = :result.accountId
    ];
    System.assertEquals('OSM Pharmacy Test', created.Name);
    System.assertEquals('OSM-node/999001', created.Maps_Place_Id__c);

    List<Account_Affiliation__c> affs = [
      SELECT Initiation_Source__c, Score__c
      FROM Account_Affiliation__c
      WHERE
        (Primary_Account__c = :current.Account__c AND Related_Account__c = :result.accountId)
        OR (Primary_Account__c = :result.accountId AND Related_Account__c = :current.Account__c)
    ];
    System.assertEquals(1, affs.size());
    System.assertEquals('Pharmacy Visit', affs[0].Initiation_Source__c);
  }

  @IsTest
  static void controllerWrappers_delegateToRouteService() {
    Visit__c current = [SELECT Id FROM Visit__c LIMIT 1];
    Account pharmacy = [SELECT Id FROM Account WHERE Name = 'Route Pharmacy In List' LIMIT 1];

    Test.startTest();
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult scheduled = VisitNeighbouringPharmacyRouteService.scheduleAccountPharmacyOnRoute(
      current.Id,
      pharmacy.Id
    );
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult external = VisitContextInsightsController.addExternalPharmacyToRoute(
      current.Id,
      'node/999002',
      'OSM Via Controller',
      '2 Nile St',
      'Cairo',
      null,
      '11511',
      'Egypt',
      null,
      30.06,
      31.25
    );
    Test.stopTest();

    System.assertEquals(pharmacy.Id, scheduled.accountId);
    System.assertEquals(true, external.createdAccount);
  }
}
