@IsTest private class S_VisitCallReportControllerTest {
  @IsTest static void smoke(){
    VisitCallReportController.getReportHtml(null);
    VisitCallReportController.getReportData(null);
  }
}