public with sharing class AccountActivityInsightsTypes {
  public static final String SOURCE_AGENTFORCE = 'Agentforce';
  public static final String SOURCE_STRUCTURED = 'Structured';

  public class AccountVisitInsights {
    @AuraEnabled
    public String headline;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public List<String> productsDiscussed;
    @AuraEnabled
    public List<String> painPoints;
    @AuraEnabled
    public List<String> positiveSignals;
    @AuraEnabled
    public List<String> customerFeedback;
    @AuraEnabled
    public List<String> suggestedTalkingPoints;
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Integer visitCount;
    @AuraEnabled
    public Integer presentationCount;
  }

  public class EinsteinPayload {
    public String headline;
    public String summary;
    public List<String> productsDiscussed;
    public List<String> painPoints;
    public List<String> positiveSignals;
    public List<String> customerFeedback;
    public List<String> suggestedTalkingPoints;
  }
}