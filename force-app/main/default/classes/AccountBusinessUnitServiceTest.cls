@IsTest
private class AccountBusinessUnitServiceTest {
  @TestSetup
  static void setupPermissions() {
    assignPermissionSet('Account_Master_Load_Fields');
  }

  @IsTest
  static void upsertListDeactivateAndRejectNonBu() {
    Territory2 businessUnit = getOrCreateTypedTerritory(
      'TERR_BU_TEST_ABU',
      'Business_Unit',
      'Abu_Test_Business_Unit'
    );
    Territory2 position = getOrCreateTypedTerritory(
      'TERR_POS_TEST_ABU',
      'Position',
      'Abu_Test_Position'
    );
    System.assertNotEquals(null, businessUnit, 'Expected Business Unit Territory2.');
    System.assertNotEquals(null, position, 'Expected Position Territory2.');

    Id recordTypeId = resolveAccountRecordTypeId();
    Account account = new Account(
      Name = 'ABU Test Account',
      External_ID__c = 'ABU-TEST-001',
      RecordTypeId = recordTypeId,
      BillingCity = 'Cairo',
      Account_Status__c = 'Active'
    );
    insert account;

    AccountBusinessUnitService.UpsertRequest request = new AccountBusinessUnitService.UpsertRequest();
    request.accountId = account.Id;
    request.businessUnitTerritory2Id = String.valueOf(businessUnit.Id);
    request.potentiality = 'A';
    request.propensity = '2';
    request.isActive = true;

    Test.startTest();
    AccountBusinessUnitService.LinkDto saved = AccountBusinessUnitService.upsertLink(request);
    Test.stopTest();

    System.assertNotEquals(null, saved);
    System.assertEquals(true, saved.isActive);
    System.assertEquals('A', saved.potentiality);
    System.assertEquals('2', saved.propensity);
    System.assertEquals(businessUnit.Name, saved.businessUnitName);
    System.assert(String.isNotBlank(saved.uniqueKey));
    System.assert(String.isNotBlank(saved.chipLabel));

    List<AccountBusinessUnitService.LinkDto> activeOnly = AccountBusinessUnitService.listForAccount(
      account.Id,
      false
    );
    System.assertEquals(1, activeOnly.size());

    AccountBusinessUnitService.LinkDto deactivated = AccountBusinessUnitService.deactivateLink(
      saved.id
    );
    System.assertEquals(false, deactivated.isActive);
    System.assertEquals(Date.today(), deactivated.endDate);
    System.assertEquals(
      0,
      AccountBusinessUnitService.listForAccount(account.Id, false).size(),
      'Inactive links hidden from default list.'
    );
    System.assertEquals(
      1,
      AccountBusinessUnitService.listForAccount(account.Id, true).size(),
      'Admin includeInactive still returns row.'
    );

    AccountBusinessUnitService.UpsertRequest bad = new AccountBusinessUnitService.UpsertRequest();
    bad.accountExternalId = 'ABU-TEST-001';
    bad.businessUnitTerritory2Id = String.valueOf(position.Id);
    bad.potentiality = 'B';
    AccountBusinessUnitService.ChunkResult rejected = AccountBusinessUnitService.upsertLinks(
      new List<AccountBusinessUnitService.UpsertRequest>{ bad }
    );
    System.assertEquals(0, rejected.successCount);
    System.assertEquals(1, rejected.errorCount);
    System.assert(!rejected.errors.isEmpty(), 'Expected validation error for Position territory.');

    List<AccountBusinessUnitService.BuOption> options = AccountBusinessUnitService.listBusinessUnitOptions();
    Boolean foundBu = false;
    for (AccountBusinessUnitService.BuOption option : options) {
      if (option.territory2Id == businessUnit.Id) {
        foundBu = true;
        break;
      }
    }
    System.assertEquals(true, foundBu, 'BU options should include test Business Unit.');

    List<AccountBusinessUnitService.AccountSearchResult> searchHits =
      AccountBusinessUnitService.searchAccounts('ABU Test');
    System.assert(!searchHits.isEmpty());

    AccountBusinessUnitService.ExportPayload exportPayload = AccountBusinessUnitService.exportLinks(
      null,
      50
    );
    System.assertNotEquals(null, exportPayload.links);

    AccountBusinessUnitService.UpsertRequest reactivate = new AccountBusinessUnitService.UpsertRequest();
    reactivate.accountId = account.Id;
    reactivate.businessUnitTerritory2Id = String.valueOf(businessUnit.Id);
    reactivate.potentiality = 'B';
    reactivate.propensity = '1';
    reactivate.isActive = true;
    AccountBusinessUnitService.LinkDto reactivated = AccountBusinessUnitService.upsertLink(reactivate);
    System.assertEquals(true, reactivated.isActive);
  }

  private static Id resolveAccountRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN (
          'Medical_Professional_HCP',
          'SDO_PersonAccounts',
          'Institution_HCO'
        )
      LIMIT 1
    ];
    System.assert(!types.isEmpty(), 'Expected an Account record type.');
    return types[0].Id;
  }

  private static Territory2 getOrCreateTypedTerritory(
    String externalId,
    String territoryType,
    String developerName
  ) {
    List<Territory2> existing = [
      SELECT Id, Name, External_ID__c, Territory_Type__c
      FROM Territory2
      WHERE External_ID__c = :externalId
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      Territory2 territory = existing[0];
      if (
        Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c') &&
        territory.Territory_Type__c != territoryType
      ) {
        territory.Territory_Type__c = territoryType;
        update territory;
      }
      return territory;
    }

    List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
    if (types.isEmpty()) {
      return null;
    }
    List<Territory2Model> models = [
      SELECT Id
      FROM Territory2Model
      WHERE DeveloperName = 'Current_FY'
      LIMIT 1
    ];
    if (models.isEmpty()) {
      return null;
    }

    Territory2 territory = new Territory2(
      Name = developerName.replace('_', ' '),
      DeveloperName = developerName,
      Territory2ModelId = models[0].Id,
      Territory2TypeId = types[0].Id,
      External_ID__c = externalId
    );
    if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
      territory.put('Territory_Type__c', territoryType);
    }
    insert territory;
    return territory;
  }

  private static void assignPermissionSet(String developerName) {
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :developerName
      LIMIT 1
    ];
    if (sets.isEmpty()) {
      return;
    }
    List<PermissionSetAssignment> existing = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :sets[0].Id
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return;
    }
    insert new PermissionSetAssignment(
      AssigneeId = UserInfo.getUserId(),
      PermissionSetId = sets[0].Id
    );
  }
}