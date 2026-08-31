@IsTest
private class VisitContextInsightsControllerTest {
  @TestSetup
  static void setupData() {
    Account hco = new Account(
      Name = 'Test HCO',
      BillingCity = 'Cairo',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357
    );
    insert hco;

    List<RecordType> pharmacyTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
      LIMIT 1
    ];
    if (!pharmacyTypes.isEmpty()) {
      insert new Account(
        Name = 'Near Pharmacy',
        RecordTypeId = pharmacyTypes[0].Id,
        BillingCity = 'Cairo',
        BillingLatitude = 30.0450,
        BillingLongitude = 31.2360,
        Phone = '+201000000001'
      );
    }

    Visit__c priorTerritory = new Visit__c(
      Account__c = hco.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Start_Date__c = DateTime.now().addDays(-7),
      End_Date__c = DateTime.now().addDays(-7).addHours(1),
      Visit_Objective__c = 'Territory prior objective',
      Visit_Notes__c = 'Territory prior notes',
      Products_Discussed__c = 'Product A'
    );
    Visit__c priorZeta = new Visit__c(
      Account__c = hco.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Start_Date__c = DateTime.now().addDays(-14),
      End_Date__c = DateTime.now().addDays(-14).addHours(1),
      Visit_Objective__c = 'Zeta prior objective',
      Visit_Notes__c = 'Zeta prior notes',
      Products_Discussed__c = 'Product B'
    );
    insert new List<Visit__c>{ priorTerritory, priorZeta };

    insert new Visit__c(
      Account__c = hco.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Draft',
      Start_Date__c = DateTime.now().addDays(1),
      End_Date__c = DateTime.now().addDays(1).addHours(1),
      Visit_Objective__c = 'Current visit'
    );
  }

  @IsTest
  static void returnsPharmaciesAndPriorVisits() {
    Visit__c currentVisit = [
      SELECT Id
      FROM Visit__c
      WHERE Status__c = 'Draft'
      LIMIT 1
    ];

    Test.startTest();
    VisitContextInsightsController.VisitContextInsights insights = VisitContextInsightsController.getVisitContextInsights(
      currentVisit.Id
    );
    Test.stopTest();

    System.assertEquals(true, insights.hasGeo);
    System.assertEquals(5, insights.pharmacyPageSize);
    System.assertEquals(2, insights.zetaPriorVisits.size());
    System.assert(!insights.territoryPriorVisits.isEmpty());
    if (pharmacyTypesExist()) {
      System.assert(!insights.neighbouringPharmacies.isEmpty(), 'Expected nearby pharmacy');
      System.assertNotEquals(null, insights.centerLatitude);
      System.assertNotEquals(null, insights.neighbouringPharmacies[0].latitude);
      System.assertEquals(true, insights.neighbouringPharmacies[0].inAccountList);
      System.assertEquals(
        'Near Pharmacy',
        insights.neighbouringPharmacies[0].name
      );
    }
  }

  private static Boolean pharmacyTypesExist() {
    return ![
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
        LIMIT 1
      ]
      .isEmpty();
  }
}