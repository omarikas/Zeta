/**
 * Account ↔ Business Unit (Territory2) many-to-many links.
 * Potentiality = A/B/C; Propensity = 1/2/3. Soft-deactivate via Is_Active__c.
 */
public with sharing class AccountBusinessUnitService {
  public static final String TERRITORY_TYPE_BUSINESS_UNIT = 'Business_Unit';

  @TestVisible
  private static Boolean isLinkSchemaReady() {
    if (!Schema.getGlobalDescribe().containsKey('Account_Business_Unit__c')) {
      return false;
    }
    Map<String, Schema.SObjectField> fields =
      Schema.SObjectType.Account_Business_Unit__c.fields.getMap();
    return fields.containsKey('Business_Unit_External_ID__c') &&
      fields.containsKey('Unique_Key__c') &&
      fields.containsKey('Is_Active__c');
  }

  public class BuOption {
    @AuraEnabled
    public Id territory2Id;
    @AuraEnabled
    public String externalId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
  }

  public class LinkDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String accountExternalId;
    @AuraEnabled
    public String businessUnitTerritory2Id;
    @AuraEnabled
    public String businessUnitExternalId;
    @AuraEnabled
    public String businessUnitName;
    @AuraEnabled
    public String potentiality;
    @AuraEnabled
    public String propensity;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String uniqueKey;
    @AuraEnabled
    public String chipLabel;
  }

  public class AccountSearchResult {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String externalId;
    @AuraEnabled
    public String city;
  }

  public class UpsertRequest {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountExternalId;
    @AuraEnabled
    public String businessUnitTerritory2Id;
    @AuraEnabled
    public String businessUnitExternalId;
    @AuraEnabled
    public String potentiality;
    @AuraEnabled
    public String propensity;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public Date startDate;
  }

  public class ChunkResult {
    @AuraEnabled
    public Integer successCount;
    @AuraEnabled
    public Integer errorCount;
    @AuraEnabled
    public List<String> errors;
  }

  public class ExportPayload {
    @AuraEnabled
    public List<LinkDto> links;
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public String nextId;
  }

  @AuraEnabled(cacheable=true)
  public static List<BuOption> listBusinessUnitOptions() {
    List<BuOption> options = new List<BuOption>();
    for (Territory2 territory : [
      SELECT Id, Name, External_ID__c, Territory_Type__c
      FROM Territory2
      WHERE Territory_Type__c = :TERRITORY_TYPE_BUSINESS_UNIT
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 500
    ]) {
      BuOption option = new BuOption();
      option.territory2Id = territory.Id;
      option.externalId = territory.External_ID__c;
      option.name = territory.Name;
      option.label = String.isBlank(territory.External_ID__c)
        ? territory.Name
        : territory.Name + ' (' + territory.External_ID__c + ')';
      options.add(option);
    }
    return options;
  }

  @AuraEnabled
  public static List<LinkDto> listForAccount(Id accountId, Boolean includeInactive) {
    if (accountId == null) {
      return new List<LinkDto>();
    }
    List<LinkDto> links = listForAccounts(new Set<Id>{ accountId }, includeInactive == true)
      .get(accountId);
    return links == null ? new List<LinkDto>() : links;
  }

  public static Map<Id, List<LinkDto>> listForAccounts(
    Set<Id> accountIds,
    Boolean includeInactive
  ) {
    Map<Id, List<LinkDto>> byAccount = new Map<Id, List<LinkDto>>();
    if (accountIds == null || accountIds.isEmpty() || !isLinkSchemaReady()) {
      return byAccount;
    }
    for (Id accountId : accountIds) {
      byAccount.put(accountId, new List<LinkDto>());
    }

    List<Account_Business_Unit__c> rows;
    if (includeInactive == true) {
      rows = [
        SELECT
          Id,
          Account__c,
          Account__r.Name,
          Account__r.External_ID__c,
          Business_Unit_Territory2_Id__c,
          Business_Unit_External_ID__c,
          Business_Unit_Name__c,
          Potentiality__c,
          Propensity__c,
          Is_Active__c,
          Start_Date__c,
          End_Date__c,
          Unique_Key__c
        FROM Account_Business_Unit__c
        WHERE Account__c IN :accountIds
        WITH SYSTEM_MODE
        ORDER BY Business_Unit_Name__c NULLS LAST, CreatedDate
      ];
    } else {
      rows = [
        SELECT
          Id,
          Account__c,
          Account__r.Name,
          Account__r.External_ID__c,
          Business_Unit_Territory2_Id__c,
          Business_Unit_External_ID__c,
          Business_Unit_Name__c,
          Potentiality__c,
          Propensity__c,
          Is_Active__c,
          Start_Date__c,
          End_Date__c,
          Unique_Key__c
        FROM Account_Business_Unit__c
        WHERE Account__c IN :accountIds AND Is_Active__c = TRUE
        WITH SYSTEM_MODE
        ORDER BY Business_Unit_Name__c NULLS LAST, CreatedDate
      ];
    }

    for (Account_Business_Unit__c row : rows) {
      byAccount.get(row.Account__c).add(toDto(row));
    }
    return byAccount;
  }

  @AuraEnabled
  public static List<AccountSearchResult> searchAccounts(String searchTerm) {
    List<AccountSearchResult> results = new List<AccountSearchResult>();
    String term = searchTerm == null ? '' : searchTerm.trim();
    if (term.length() < 2) {
      return results;
    }
    String likeTerm = '%' + String.escapeSingleQuotes(term) + '%';
    for (Account account : [
      SELECT Id, Name, External_ID__c, BillingCity
      FROM Account
      WHERE Name LIKE :likeTerm OR External_ID__c LIKE :likeTerm
      WITH USER_MODE
      ORDER BY Name
      LIMIT 25
    ]) {
      AccountSearchResult row = new AccountSearchResult();
      row.accountId = account.Id;
      row.name = account.Name;
      row.externalId = account.External_ID__c;
      row.city = account.BillingCity;
      results.add(row);
    }
    return results;
  }

  @AuraEnabled
  public static LinkDto upsertLink(UpsertRequest request) {
    if (request == null) {
      throw new AuraHandledException('Link request is required.');
    }
    ChunkResult chunk = upsertLinks(new List<UpsertRequest>{ request });
    if (chunk.errorCount > 0) {
      throw new AuraHandledException(
        chunk.errors.isEmpty() ? 'Unable to save Account Business Unit link.' : chunk.errors[0]
      );
    }
    Id accountId = resolveAccountId(request);
    String territoryId = resolveTerritoryId(request);
    List<LinkDto> links = listForAccount(accountId, true);
    for (LinkDto link : links) {
      if (link.businessUnitTerritory2Id == territoryId) {
        return link;
      }
    }
    return links.isEmpty() ? null : links[0];
  }

  @AuraEnabled
  public static ChunkResult upsertLinks(List<UpsertRequest> requests) {
    ChunkResult result = new ChunkResult();
    result.successCount = 0;
    result.errorCount = 0;
    result.errors = new List<String>();
    if (requests == null || requests.isEmpty()) {
      return result;
    }
    if (!isLinkSchemaReady()) {
      result.errorCount = requests.size();
      result.errors.add('Account Business Unit schema is not available.');
      return result;
    }

    Set<String> territoryIds = new Set<String>();
    Set<String> territoryExternalIds = new Set<String>();
    Set<Id> accountIds = new Set<Id>();
    Set<String> accountExternalIds = new Set<String>();
    for (UpsertRequest request : requests) {
      if (request == null) {
        continue;
      }
      if (request.accountId != null) {
        accountIds.add(request.accountId);
      }
      if (String.isNotBlank(request.accountExternalId)) {
        accountExternalIds.add(request.accountExternalId.trim());
      }
      if (String.isNotBlank(request.businessUnitTerritory2Id)) {
        territoryIds.add(request.businessUnitTerritory2Id.trim());
      }
      if (String.isNotBlank(request.businessUnitExternalId)) {
        territoryExternalIds.add(request.businessUnitExternalId.trim());
      }
    }

    Map<String, Account> accountsByExternalId = new Map<String, Account>();
    if (!accountExternalIds.isEmpty()) {
      for (Account account : [
        SELECT Id, External_ID__c, Name
        FROM Account
        WHERE External_ID__c IN :accountExternalIds
        WITH USER_MODE
      ]) {
        accountsByExternalId.put(account.External_ID__c, account);
        accountIds.add(account.Id);
      }
    }

    Map<Id, Territory2> territoriesById = loadBusinessUnitsById(territoryIds);
    Map<String, Territory2> territoriesByExternalId = loadBusinessUnitsByExternalId(
      territoryExternalIds
    );

    List<Account_Business_Unit__c> toUpsert = new List<Account_Business_Unit__c>();
    List<Integer> requestIndexes = new List<Integer>();
    for (Integer i = 0; i < requests.size(); i++) {
      UpsertRequest request = requests[i];
      try {
        Id accountId = request.accountId;
        if (accountId == null && String.isNotBlank(request.accountExternalId)) {
          Account matched = accountsByExternalId.get(request.accountExternalId.trim());
          if (matched == null) {
            throw new AuraHandledException(
              'Account not found for External ID ' + request.accountExternalId
            );
          }
          accountId = matched.Id;
        }
        if (accountId == null) {
          throw new AuraHandledException('Account Id or Account External ID is required.');
        }

        Territory2 territory = resolveTerritory(request, territoriesById, territoriesByExternalId);
        if (territory == null) {
          throw new AuraHandledException('Business Unit Territory2 was not found.');
        }
        if (!isBusinessUnit(territory)) {
          throw new AuraHandledException(
            'Territory must have Territory Type Business_Unit. Rejected: ' +
            (String.isBlank(territory.External_ID__c) ? String.valueOf(territory.Id) : territory.External_ID__c)
          );
        }

        Account_Business_Unit__c row = new Account_Business_Unit__c();
        row.Account__c = accountId;
        row.Business_Unit_Territory2_Id__c = String.valueOf(territory.Id);
        row.Business_Unit_External_ID__c = territory.External_ID__c;
        row.Business_Unit_Name__c = territory.Name;
        row.Unique_Key__c = buildUniqueKey(accountId, territory.Id);
        row.Potentiality__c = blankToNull(request.potentiality);
        row.Propensity__c = blankToNull(request.propensity);
        row.Is_Active__c = request.isActive == null ? true : request.isActive;
        row.Start_Date__c = request.startDate == null ? Date.today() : request.startDate;
        if (row.Is_Active__c == true) {
          row.End_Date__c = null;
        } else if (row.End_Date__c == null) {
          row.End_Date__c = Date.today();
        }
        toUpsert.add(row);
        requestIndexes.add(i);
      } catch (Exception ex) {
        result.errorCount++;
        result.errors.add('Row ' + (i + 1) + ': ' + ex.getMessage());
      }
    }

    if (toUpsert.isEmpty()) {
      return result;
    }

    Database.UpsertResult[] upsertResults = Database.upsert(
      toUpsert,
      Account_Business_Unit__c.Unique_Key__c,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < upsertResults.size(); i++) {
      Database.UpsertResult upsertResult = upsertResults[i];
      if (upsertResult.isSuccess()) {
        result.successCount++;
      } else {
        result.errorCount++;
        String message = 'Row ' + (requestIndexes[i] + 1) + ': ';
        for (Database.Error err : upsertResult.getErrors()) {
          message += err.getMessage() + ' ';
        }
        result.errors.add(message.trim());
      }
    }
    return result;
  }

  @AuraEnabled
  public static LinkDto deactivateLink(Id linkId) {
    if (linkId == null) {
      throw new AuraHandledException('Link Id is required.');
    }
    if (!isLinkSchemaReady()) {
      throw new AuraHandledException('Account Business Unit is not available.');
    }
    List<Account_Business_Unit__c> rows = [
      SELECT
        Id,
        Account__c,
        Account__r.Name,
        Account__r.External_ID__c,
        Business_Unit_Territory2_Id__c,
        Business_Unit_External_ID__c,
        Business_Unit_Name__c,
        Potentiality__c,
        Propensity__c,
        Is_Active__c,
        Start_Date__c,
        End_Date__c,
        Unique_Key__c
      FROM Account_Business_Unit__c
      WHERE Id = :linkId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Account Business Unit link was not found.');
    }
    Account_Business_Unit__c row = rows[0];
    row.Is_Active__c = false;
    if (row.End_Date__c == null) {
      row.End_Date__c = Date.today();
    }
    update as system row;
    return toDto(row);
  }

  @AuraEnabled
  public static ExportPayload exportLinks(String lastId, Integer pageSize) {
    ExportPayload payload = new ExportPayload();
    payload.links = new List<LinkDto>();
    if (!isLinkSchemaReady()) {
      payload.hasMore = false;
      return payload;
    }
    Integer size = pageSize == null || pageSize < 1 ? 200 : Math.min(pageSize, 500);
    Id cursor = String.isBlank(lastId) ? null : Id.valueOf(lastId);
    List<Account_Business_Unit__c> rows;
    if (cursor == null) {
      rows = [
        SELECT
          Id,
          Account__c,
          Account__r.Name,
          Account__r.External_ID__c,
          Business_Unit_Territory2_Id__c,
          Business_Unit_External_ID__c,
          Business_Unit_Name__c,
          Potentiality__c,
          Propensity__c,
          Is_Active__c,
          Start_Date__c,
          End_Date__c,
          Unique_Key__c
        FROM Account_Business_Unit__c
        WITH SYSTEM_MODE
        ORDER BY Id
        LIMIT :size
      ];
    } else {
      rows = [
        SELECT
          Id,
          Account__c,
          Account__r.Name,
          Account__r.External_ID__c,
          Business_Unit_Territory2_Id__c,
          Business_Unit_External_ID__c,
          Business_Unit_Name__c,
          Potentiality__c,
          Propensity__c,
          Is_Active__c,
          Start_Date__c,
          End_Date__c,
          Unique_Key__c
        FROM Account_Business_Unit__c
        WHERE Id > :cursor
        WITH SYSTEM_MODE
        ORDER BY Id
        LIMIT :size
      ];
    }
    for (Account_Business_Unit__c row : rows) {
      payload.links.add(toDto(row));
    }
    payload.hasMore = rows.size() == size;
    payload.nextId = rows.isEmpty() ? null : String.valueOf(rows[rows.size() - 1].Id);
    return payload;
  }

  /**
   * Before-insert/update stamp Unique_Key, BU name/external id, and End_Date on deactivate.
   * Rejects Territory2 Ids that are not Business_Unit.
   */
  public static void stampAndValidate(
    List<Account_Business_Unit__c> rows,
    Map<Id, Account_Business_Unit__c> oldMap
  ) {
    if (rows == null || rows.isEmpty()) {
      return;
    }

    Set<String> territoryIds = new Set<String>();
    for (Account_Business_Unit__c row : rows) {
      if (String.isNotBlank(row.Business_Unit_Territory2_Id__c)) {
        territoryIds.add(row.Business_Unit_Territory2_Id__c.trim());
      }
    }
    Map<Id, Territory2> territoriesById = loadTerritoriesById(territoryIds);

    for (Account_Business_Unit__c row : rows) {
      if (row.Account__c == null || String.isBlank(row.Business_Unit_Territory2_Id__c)) {
        row.addError('Account and Business Unit Territory Id are required.');
        continue;
      }

      String territoryKey = row.Business_Unit_Territory2_Id__c.trim();
      row.Business_Unit_Territory2_Id__c = territoryKey;
      Id territoryId;
      try {
        territoryId = Id.valueOf(territoryKey);
      } catch (Exception ex) {
        row.addError('Business Unit Territory Id must be a valid 18-character Id.');
        continue;
      }

      Territory2 territory = territoriesById.get(territoryId);
      if (territory == null) {
        row.addError('Business Unit Territory2 was not found.');
        continue;
      }
      if (!isBusinessUnit(territory)) {
        row.addError(
          'Territory must have Territory Type Business_Unit. Use a TERR_BU_* organogram Business Unit.'
        );
        continue;
      }

      row.Business_Unit_External_ID__c = territory.External_ID__c;
      row.Business_Unit_Name__c = territory.Name;
      row.Unique_Key__c = buildUniqueKey(row.Account__c, territory.Id);

      if (row.Start_Date__c == null) {
        row.Start_Date__c = Date.today();
      }

      Boolean wasActive = oldMap == null || oldMap.get(row.Id) == null
        ? true
        : oldMap.get(row.Id).Is_Active__c == true;
      Boolean isActive = row.Is_Active__c == true;
      if (!isActive && (wasActive || row.End_Date__c == null)) {
        row.End_Date__c = Date.today();
      }
      if (isActive) {
        row.End_Date__c = null;
      }
    }
  }

  private static LinkDto toDto(Account_Business_Unit__c row) {
    LinkDto dto = new LinkDto();
    dto.id = row.Id;
    dto.accountId = row.Account__c;
    dto.accountName = row.Account__r != null ? row.Account__r.Name : null;
    dto.accountExternalId = row.Account__r != null ? row.Account__r.External_ID__c : null;
    dto.businessUnitTerritory2Id = row.Business_Unit_Territory2_Id__c;
    dto.businessUnitExternalId = row.Business_Unit_External_ID__c;
    dto.businessUnitName = row.Business_Unit_Name__c;
    dto.potentiality = row.Potentiality__c;
    dto.propensity = row.Propensity__c;
    dto.isActive = row.Is_Active__c == true;
    dto.startDate = row.Start_Date__c;
    dto.endDate = row.End_Date__c;
    dto.uniqueKey = row.Unique_Key__c;
    String name = String.isBlank(row.Business_Unit_Name__c)
      ? row.Business_Unit_External_ID__c
      : row.Business_Unit_Name__c;
    List<String> parts = new List<String>();
    if (String.isNotBlank(name)) {
      parts.add(name);
    }
    if (String.isNotBlank(row.Potentiality__c)) {
      parts.add(row.Potentiality__c);
    }
    if (String.isNotBlank(row.Propensity__c)) {
      parts.add(row.Propensity__c);
    }
    dto.chipLabel = String.join(parts, ' · ');
    return dto;
  }

  private static String buildUniqueKey(Id accountId, Id territoryId) {
    return String.valueOf(accountId) + ':' + String.valueOf(territoryId);
  }

  private static Boolean isBusinessUnit(Territory2 territory) {
    if (territory == null) {
      return false;
    }
    if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
      return TERRITORY_TYPE_BUSINESS_UNIT.equals(territory.Territory_Type__c);
    }
    return territory.External_ID__c != null &&
      territory.External_ID__c.startsWith('TERR_BU_');
  }

  private static Map<Id, Territory2> loadBusinessUnitsById(Set<String> territoryIds) {
    Map<Id, Territory2> byId = new Map<Id, Territory2>();
    if (territoryIds == null || territoryIds.isEmpty()) {
      return byId;
    }
    Set<Id> ids = new Set<Id>();
    for (String value : territoryIds) {
      try {
        ids.add(Id.valueOf(value));
      } catch (Exception ignore) {
        // Invalid Id rejected later.
      }
    }
    if (ids.isEmpty()) {
      return byId;
    }
    for (Territory2 territory : [
      SELECT Id, Name, External_ID__c, Territory_Type__c
      FROM Territory2
      WHERE Id IN :ids
      WITH SYSTEM_MODE
    ]) {
      byId.put(territory.Id, territory);
    }
    return byId;
  }

  private static Map<String, Territory2> loadBusinessUnitsByExternalId(Set<String> externalIds) {
    Map<String, Territory2> byExternalId = new Map<String, Territory2>();
    if (externalIds == null || externalIds.isEmpty()) {
      return byExternalId;
    }
    for (Territory2 territory : [
      SELECT Id, Name, External_ID__c, Territory_Type__c
      FROM Territory2
      WHERE External_ID__c IN :externalIds
      WITH SYSTEM_MODE
    ]) {
      byExternalId.put(territory.External_ID__c, territory);
    }
    return byExternalId;
  }

  private static Map<Id, Territory2> loadTerritoriesById(Set<String> territoryIds) {
    return loadBusinessUnitsById(territoryIds);
  }

  private static Territory2 resolveTerritory(
    UpsertRequest request,
    Map<Id, Territory2> byId,
    Map<String, Territory2> byExternalId
  ) {
    if (String.isNotBlank(request.businessUnitTerritory2Id)) {
      try {
        Id territoryId = Id.valueOf(request.businessUnitTerritory2Id.trim());
        return byId.get(territoryId);
      } catch (Exception ex) {
        throw new AuraHandledException('Business Unit Territory Id is invalid.');
      }
    }
    if (String.isNotBlank(request.businessUnitExternalId)) {
      return byExternalId.get(request.businessUnitExternalId.trim());
    }
    throw new AuraHandledException(
      'Business Unit Territory Id or Business Unit External ID is required.'
    );
  }

  private static Id resolveAccountId(UpsertRequest request) {
    if (request.accountId != null) {
      return request.accountId;
    }
    if (String.isBlank(request.accountExternalId)) {
      return null;
    }
    List<Account> accounts = [
      SELECT Id
      FROM Account
      WHERE External_ID__c = :request.accountExternalId.trim()
      WITH USER_MODE
      LIMIT 1
    ];
    return accounts.isEmpty() ? null : accounts[0].Id;
  }

  private static String resolveTerritoryId(UpsertRequest request) {
    if (String.isNotBlank(request.businessUnitTerritory2Id)) {
      return request.businessUnitTerritory2Id.trim();
    }
    if (String.isBlank(request.businessUnitExternalId)) {
      return null;
    }
    List<Territory2> territories = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = :request.businessUnitExternalId.trim()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return territories.isEmpty() ? null : String.valueOf(territories[0].Id);
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }
}