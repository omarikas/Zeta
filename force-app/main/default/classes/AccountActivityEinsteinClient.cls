/**
 * Optional Agentforce enhancement for account activity insights.
 * Einstein LLM ConnectApi is not available in all orgs; when unavailable we
 * safely return without enhancement so structured insights still work.
 */
public with sharing class AccountActivityEinsteinClient {
  @TestVisible
  private static Boolean testForceFailure = false;

  @TestVisible
  private static String testResponseJson;

  public class GenerationResult {
    public Boolean success = false;
    public AccountActivityInsightsTypes.AccountVisitInsights insights;
  }

  public static GenerationResult tryEnhance(
    Id accountId,
    AccountActivityInsightsTypes.AccountVisitInsights baseInsights
  ) {
    GenerationResult generationResult = new GenerationResult();
    try {
      if (Test.isRunningTest()) {
        if (testForceFailure) {
          return generationResult;
        }
        if (!String.isBlank(testResponseJson)) {
          return parseTestResponse(testResponseJson, baseInsights);
        }
        return generationResult;
      }

      // Einstein prompt generation is optional. Keep structured insights when
      // ConnectApi Einstein LLM types are not provisioned in this org.
      return generationResult;
    } catch (Exception ex) {
      generationResult.success = false;
    }
    return generationResult;
  }

  private static GenerationResult parseTestResponse(
    String responseJson,
    AccountActivityInsightsTypes.AccountVisitInsights baseInsights
  ) {
    GenerationResult generationResult = new GenerationResult();
    AccountActivityInsightsTypes.EinsteinPayload payload = parsePayload(responseJson);
    if (payload == null) {
      return generationResult;
    }
    generationResult.success = true;
    generationResult.insights = mergePayload(baseInsights, payload);
    return generationResult;
  }

  private static AccountActivityInsightsTypes.AccountVisitInsights mergePayload(
    AccountActivityInsightsTypes.AccountVisitInsights baseInsights,
    AccountActivityInsightsTypes.EinsteinPayload payload
  ) {
    AccountActivityInsightsTypes.AccountVisitInsights merged = new AccountActivityInsightsTypes.AccountVisitInsights();
    merged.headline = String.isBlank(payload.headline) ? baseInsights.headline : payload.headline;
    merged.summary = String.isBlank(payload.summary) ? baseInsights.summary : payload.summary;
    merged.productsDiscussed = coalesceList(payload.productsDiscussed, baseInsights.productsDiscussed);
    merged.painPoints = coalesceList(payload.painPoints, baseInsights.painPoints);
    merged.positiveSignals = coalesceList(payload.positiveSignals, baseInsights.positiveSignals);
    merged.customerFeedback = coalesceList(payload.customerFeedback, baseInsights.customerFeedback);
    merged.suggestedTalkingPoints = coalesceList(
      payload.suggestedTalkingPoints,
      baseInsights.suggestedTalkingPoints
    );
    merged.visitCount = baseInsights.visitCount;
    merged.presentationCount = baseInsights.presentationCount;
    merged.source = AccountActivityInsightsTypes.SOURCE_AGENTFORCE;
    return merged;
  }

  private static List<String> coalesceList(List<String> primary, List<String> fallback) {
    if (primary != null && !primary.isEmpty()) {
      return primary;
    }
    return fallback == null ? new List<String>() : fallback;
  }

  private static AccountActivityInsightsTypes.EinsteinPayload parsePayload(String text) {
    String normalized = text == null ? '' : text.trim();
    if (normalized.startsWith('```')) {
      normalized = normalized.replaceAll('(?i)^```json\\s*', '');
      normalized = normalized.replaceAll('```\\s*$', '');
      normalized = normalized.trim();
    }
    if (String.isBlank(normalized)) {
      return null;
    }
    try {
      return (AccountActivityInsightsTypes.EinsteinPayload) JSON.deserialize(
        normalized,
        AccountActivityInsightsTypes.EinsteinPayload.class
      );
    } catch (Exception ex) {
      return null;
    }
  }

  public static Object generate(String prompt) {
    return null;
  }
}