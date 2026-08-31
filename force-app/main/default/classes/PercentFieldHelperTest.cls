@IsTest
private class PercentFieldHelperTest {
  @IsTest
  static void toDisplayScale_handlesNullRatioAndLegacy() {
    System.assertEquals(null, PercentFieldHelper.toDisplayScale(null));
    System.assertEquals(45, PercentFieldHelper.toDisplayScale(0.45));
    System.assertEquals(45, PercentFieldHelper.toDisplayScale(45));
    System.assertEquals(45, PercentFieldHelper.toDisplayScale(4500));
    System.assertEquals(100, PercentFieldHelper.toDisplayScale(1));
  }
}