public with sharing class VisitCallReportController {
  @AuraEnabled(cacheable=true)
  public static VisitCallReportService.CallReportPayload getCallReportPayload(Id visitId) {
    return VisitCallReportService.getCallReportPayload(visitId);
  }

  @AuraEnabled(cacheable=true)
  public static List<VisitCallReportService.TerritoryProductOption> getTerritoryProducts(Id visitId) {
    return VisitCallReportService.getTerritoryProducts(visitId);
  }

  @AuraEnabled(cacheable=true)
  public static List<VisitCallReportService.AttendeeCandidate> searchAttendeeCandidates(
    Id visitId,
    String searchTerm,
    Integer offset
  ) {
    return VisitCallReportService.searchAttendeeCandidates(visitId, searchTerm, offset);
  }

  @AuraEnabled(cacheable=true)
  public static List<VisitCallReportService.SampleInventoryOption> getSampleInventoryForUser() {
    return VisitCallReportService.getSampleInventoryForUser();
  }

  @AuraEnabled(cacheable=true)
  public static List<CLM_Presentation__c> getActiveClmPresentations() {
    return [
      SELECT Id, Name, Product__c, Status__c, Slide_Count__c
      FROM CLM_Presentation__c
      WHERE Status__c = 'Available'
      WITH USER_MODE
      ORDER BY Name ASC
      LIMIT 100
    ];
  }

  @AuraEnabled
  public static VisitCallReportService.CallReportPayload saveCallReport(String requestJson) {
    if (String.isBlank(requestJson)) {
      throw new AuraHandledException('Visit Id is required.');
    }
    VisitCallReportService.SaveRequest request = (VisitCallReportService.SaveRequest) JSON.deserialize(
      requestJson,
      VisitCallReportService.SaveRequest.class
    );
    return VisitCallReportService.saveCallReport(request);
  }
}