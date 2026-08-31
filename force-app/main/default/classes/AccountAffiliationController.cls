public with sharing class AccountAffiliationController {
  public class PicklistOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;

    public PicklistOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  @AuraEnabled(cacheable=true)
  public static Object getAccountAffiliations(
    Id accountId,
    String filtersJson,
    Integer offset,
    Integer pageSize
  ) {
    Map<String, Object> empty = new Map<String, Object>();
    empty.put('nodes', new List<Object>());
    empty.put('edges', new List<Object>());
    empty.put('totalCount', 0);
    return empty;
  }

  @AuraEnabled(cacheable=true)
  public static Object getAccountDetails(Id accountId) {
    if (accountId == null) {
      return null;
    }
    List<Account> accounts = [
      SELECT Id, Name, RecordType.Name, RecordType.DeveloperName
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      return null;
    }
    Account account = accounts[0];
    Map<String, Object> details = new Map<String, Object>();
    details.put('id', account.Id);
    details.put('name', account.Name);
    details.put(
      'accountType',
      account.RecordType != null ? account.RecordType.Name : null
    );
    return details;
  }

  @AuraEnabled(cacheable=true)
  public static List<PicklistOption> getRelationTypePicklistValues() {
    return describePicklist(Account_Affiliation__c.Affiliation_Type__c);
  }

  @AuraEnabled(cacheable=true)
  public static List<PicklistOption> getRolePicklistValues() {
    return describePicklist(Account_Affiliation__c.Role__c);
  }

  @AuraEnabled(cacheable=true)
  public static List<PicklistOption> getStrengthPicklistValues() {
    return describePicklist(Account_Affiliation__c.Strength__c);
  }

  private static List<PicklistOption> describePicklist(Schema.SObjectField fieldToken) {
    List<PicklistOption> options = new List<PicklistOption>();
    if (fieldToken == null) {
      return options;
    }
    Schema.DescribeFieldResult describe = fieldToken.getDescribe();
    for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
      if (entry.isActive()) {
        options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
      }
    }
    return options;
  }
}
