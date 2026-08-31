@IsTest
private class MedicalSpecialtyPicklistTest {
  @IsTest
  static void getLabel_humanizesUnknownValues() {
    Test.startTest();
    String label = MedicalSpecialtyPicklist.getLabel('Unknown_Specialty_Value');
    Test.stopTest();
    System.assertEquals('Unknown Specialty Value', label);
  }

  @IsTest
  static void resolveApiValue_preservesUnknownValues() {
    Test.startTest();
    String apiValue = MedicalSpecialtyPicklist.resolveApiValue('Cardiology');
    Test.stopTest();
    System.assertEquals('Cardiology', apiValue);
  }

  @IsTest
  static void getSearchTokens_includesLabelAndApiValue() {
    Test.startTest();
    List<String> tokens = MedicalSpecialtyPicklist.getSearchTokens('Pain_Management');
    Test.stopTest();
    System.assertEquals(2, tokens.size());
    System.assertEquals('pain_management', tokens[0]);
    System.assertEquals('pain management', tokens[1]);
  }

  @IsTest
  static void getLabel_returnsNullForBlank() {
    System.assertEquals(null, MedicalSpecialtyPicklist.getLabel(null));
    System.assertEquals(null, MedicalSpecialtyPicklist.getLabel(''));
  }
}