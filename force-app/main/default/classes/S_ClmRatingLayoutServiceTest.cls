@IsTest private class S_ClmRatingLayoutServiceTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('ClmRatingLayoutService'));
    ClmRatingLayoutService.getLayout(null);
  }
}