public with sharing class AccountAffiliationStrengthService {
  public static final String SOURCE_VISIT_ATTENDEE = 'Visit Attendee';
  public static final String SOURCE_PHARMACY_VISIT = 'Pharmacy Visit';

  private static final String TYPE_PRACTICE = 'Practice';
  private static final String STRENGTH_WEAK = 'Weak';
  private static final String STRENGTH_MEDIUM = 'Medium';
  private static final String STRENGTH_STRONG = 'Strong';

  /**
   * Creates or strengthens an active affiliation between two accounts.
   * Direction-agnostic lookup. Score += 1 each call; Strength derived from Score.
   * Initiation Source is set on create (and filled if blank on strengthen).
   */
  public static Account_Affiliation__c upsertAndStrengthen(
    Id accountAId,
    Id accountBId,
    String initiationSource
  ) {
    if (accountAId == null || accountBId == null || accountAId == accountBId) {
      return null;
    }
    if (String.isBlank(initiationSource)) {
      throw new AuraHandledException('Initiation source is required for visit affiliations.');
    }

    String externalId = buildPairExternalId(accountAId, accountBId);
    Account_Affiliation__c existing = findExisting(accountAId, accountBId, externalId);

    if (existing == null) {
      Account_Affiliation__c created = new Account_Affiliation__c(
        Primary_Account__c = accountAId,
        Related_Account__c = accountBId,
        Affiliation_Type__c = TYPE_PRACTICE,
        Is_Active__c = true,
        Score__c = 1,
        Strength__c = strengthForScore(1),
        Initiation_Source__c = initiationSource,
        External_ID__c = externalId
      );
      insert as system created;
      return created;
    }

    Decimal nextScore = (existing.Score__c == null ? 0 : existing.Score__c) + 1;
    existing.Score__c = nextScore;
    existing.Strength__c = strengthForScore(nextScore);
    existing.Is_Active__c = true;
    if (String.isBlank(existing.Initiation_Source__c)) {
      existing.Initiation_Source__c = initiationSource;
    }
    if (String.isBlank(existing.External_ID__c)) {
      existing.External_ID__c = externalId;
    }
    update as system existing;
    return existing;
  }

  public static void strengthenVisitAttendees(Id visitAccountId, Set<Id> attendeeAccountIds) {
    if (visitAccountId == null || attendeeAccountIds == null || attendeeAccountIds.isEmpty()) {
      return;
    }
    for (Id attendeeAccountId : attendeeAccountIds) {
      if (attendeeAccountId == null || attendeeAccountId == visitAccountId) {
        continue;
      }
      upsertAndStrengthen(visitAccountId, attendeeAccountId, SOURCE_VISIT_ATTENDEE);
    }
  }

  public static String strengthForScore(Decimal score) {
    if (score == null || score <= 2) {
      return STRENGTH_WEAK;
    }
    if (score <= 5) {
      return STRENGTH_MEDIUM;
    }
    return STRENGTH_STRONG;
  }

  @TestVisible
  private static String buildPairExternalId(Id accountAId, Id accountBId) {
    String a = String.valueOf(accountAId);
    String b = String.valueOf(accountBId);
    if (a.compareTo(b) <= 0) {
      return 'AFF-VISIT-' + a + '-' + b;
    }
    return 'AFF-VISIT-' + b + '-' + a;
  }

  private static Account_Affiliation__c findExisting(Id accountAId, Id accountBId, String externalId) {
    List<Account_Affiliation__c> byExternal = [
      SELECT
        Id,
        Primary_Account__c,
        Related_Account__c,
        Score__c,
        Strength__c,
        Initiation_Source__c,
        External_ID__c,
        Is_Active__c
      FROM Account_Affiliation__c
      WHERE External_ID__c = :externalId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!byExternal.isEmpty()) {
      return byExternal[0];
    }

    List<Account_Affiliation__c> byPair = [
      SELECT
        Id,
        Primary_Account__c,
        Related_Account__c,
        Score__c,
        Strength__c,
        Initiation_Source__c,
        External_ID__c,
        Is_Active__c
      FROM Account_Affiliation__c
      WHERE
        (
          (Primary_Account__c = :accountAId AND Related_Account__c = :accountBId)
          OR (Primary_Account__c = :accountBId AND Related_Account__c = :accountAId)
        )
      WITH SYSTEM_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    return byPair.isEmpty() ? null : byPair[0];
  }
}
