@IsTest private class S_VisitCallReportServiceTest {
  @IsTest static void smoke() {
    System.assertNotEquals(null, Type.forName('VisitCallReportService'));
    VisitCallReportService.buildReport(null);
  }
}