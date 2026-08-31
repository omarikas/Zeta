public with sharing class MedicalSpecialtyPicklist {
  private static Map<String, String> labelByApiValue;
  private static Map<String, String> apiValueByLabel;

  public static String getLabel(String apiValue) {
    if (String.isBlank(apiValue)) {
      return null;
    }
    ensureMaps();
    if (labelByApiValue.containsKey(apiValue)) {
      return labelByApiValue.get(apiValue);
    }
    return humanize(apiValue);
  }

  public static String resolveApiValue(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    ensureMaps();
    if (labelByApiValue.containsKey(value)) {
      return value;
    }
    if (apiValueByLabel.containsKey(value)) {
      return apiValueByLabel.get(value);
    }
    return value;
  }

  public static List<String> getSearchTokens(String apiValue) {
    if (String.isBlank(apiValue)) {
      return new List<String>();
    }
    String label = getLabel(apiValue);
    return new List<String>{
      apiValue.toLowerCase(),
      label != null ? label.toLowerCase() : null
    };
  }

  private static void ensureMaps() {
    if (labelByApiValue != null) {
      return;
    }
    labelByApiValue = new Map<String, String>();
    apiValueByLabel = new Map<String, String>();

    Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
    Schema.SObjectField specialtyField = accountFields.containsKey('Specialty_1__c')
      ? accountFields.get('Specialty_1__c')
      : accountFields.get('specialty_1__c');
    if (specialtyField == null) {
      return;
    }
    for (Schema.PicklistEntry entry : specialtyField.getDescribe().getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }
      String apiValue = entry.getValue();
      String label = entry.getLabel();
      labelByApiValue.put(apiValue, label);
      apiValueByLabel.put(label, apiValue);
    }
  }

  private static String humanize(String apiValue) {
    return apiValue.replace('_', ' ');
  }
}