public with sharing class ClmOfflineSyncController {
  public class OfflineAction {
    @AuraEnabled public String actionType;
    @AuraEnabled public String clientActionKey;
    @AuraEnabled public String clientSessionKey;
    @AuraEnabled public String clientVisitKey;
    @AuraEnabled public String clientCoachingKey;
    @AuraEnabled public Id visitId;
    @AuraEnabled public Id presentationId;
    @AuraEnabled public Id sequenceId;
    @AuraEnabled public String startedAtIso;
    @AuraEnabled public String endedAtIso;
    @AuraEnabled public Decimal dwellSeconds;
    @AuraEnabled public Boolean trackingPaused;
    @AuraEnabled public String responsesJson;
    @AuraEnabled public String ratingsJson;
    @AuraEnabled public Id layoutId;
    @AuraEnabled public Integer slidesPresentedCount;
    @AuraEnabled public Decimal totalDurationSeconds;
    @AuraEnabled public String callReportJson;
    @AuraEnabled public String payloadJson;
  }

  public class SyncResult {
    @AuraEnabled public List<String> failedClientKeys = new List<String>();
    @AuraEnabled public List<String> errorMessages = new List<String>();
    @AuraEnabled public Map<String, Id> sessionIdByClientKey = new Map<String, Id>();
    @AuraEnabled public Map<String, Id> visitIdByClientKey = new Map<String, Id>();
    @AuraEnabled public Map<String, Id> coachingIdByClientKey = new Map<String, Id>();
  }

  @AuraEnabled
  public static SyncResult syncOfflineActions(List<OfflineAction> actions) {
    SyncResult result = new SyncResult();
    if (actions == null || actions.isEmpty()) {
      return result;
    }

    Map<String, Id> sessionMap = new Map<String, Id>();
    Map<String, Id> visitMap = new Map<String, Id>();

    for (OfflineAction action : actions) {
      if (action == null || String.isBlank(action.actionType)) {
        continue;
      }
      String failureKey = resolveFailureKey(action);
      try {
        processAction(action, sessionMap, visitMap);
        result.errorMessages.add(null);
      } catch (Exception ex) {
        result.failedClientKeys.add(failureKey);
        result.errorMessages.add(ex.getMessage());
      }
    }

    result.sessionIdByClientKey.putAll(sessionMap);
    result.visitIdByClientKey.putAll(visitMap);
    return result;
  }

  private static String resolveFailureKey(OfflineAction action) {
    if (String.isNotBlank(action.clientActionKey)) {
      return action.clientActionKey;
    }
    if (String.isNotBlank(action.clientSessionKey)) {
      return action.clientSessionKey;
    }
    if (String.isNotBlank(action.clientVisitKey)) {
      return action.clientVisitKey;
    }
    return action.actionType;
  }

  private static void processAction(
    OfflineAction action,
    Map<String, Id> sessionMap,
    Map<String, Id> visitMap
  ) {
    String type = action.actionType;
    if (type == 'SAVE_CALL_REPORT') {
      if (String.isBlank(action.callReportJson)) {
        throw new AuraHandledException('callReportJson is required.');
      }
      VisitCallReportController.saveCallReport(action.callReportJson);
      return;
    }
    if (type == 'START_SESSION') {
      Id visitId = resolveVisitId(action, visitMap);
      ClmMetricsController.SessionSummary session = ClmMetricsController.startSession(
        visitId,
        action.presentationId
      );
      if (String.isNotBlank(action.clientSessionKey) && session != null && session.id != null) {
        sessionMap.put(action.clientSessionKey, session.id);
      }
      return;
    }
    if (type == 'START_ADHOC_SESSION') {
      ClmMetricsController.SessionSummary session = ClmMetricsController.startAdHocPresentation(
        action.presentationId
      );
      if (session != null) {
        if (String.isNotBlank(action.clientSessionKey) && session.id != null) {
          sessionMap.put(action.clientSessionKey, session.id);
        }
        if (String.isNotBlank(action.clientVisitKey) && session.visitId != null) {
          visitMap.put(action.clientVisitKey, session.visitId);
        }
      }
      return;
    }
    if (type == 'LOG_SLIDE_EVENT') {
      Id sessionId = resolveSessionId(action, sessionMap);
      ClmMetricsController.logSlideEvent(
        sessionId,
        action.sequenceId,
        action.dwellSeconds,
        action.trackingPaused
      );
      return;
    }
    if (type == 'COMPLETE_SESSION') {
      Id sessionId = resolveSessionId(action, sessionMap);
      ClmMetricsController.completeSession(sessionId);
      return;
    }
    if (type == 'CANCEL_SESSION') {
      Id sessionId = resolveSessionId(action, sessionMap);
      ClmMetricsController.cancelSession(sessionId);
      return;
    }
    if (type == 'SAVE_MESSAGE_RESPONSES') {
      Id sessionId = resolveSessionId(action, sessionMap);
      List<ClmMetricsController.MessageResponseInput> responses =
        String.isBlank(action.responsesJson)
          ? new List<ClmMetricsController.MessageResponseInput>()
          : (List<ClmMetricsController.MessageResponseInput>) JSON.deserialize(
              action.responsesJson,
              List<ClmMetricsController.MessageResponseInput>.class
            );
      ClmMetricsController.saveMessageResponses(sessionId, responses);
      return;
    }
    if (type == 'UPSERT_VISIT') {
      Map<String, Object> payload = parsePayloadMap(action.payloadJson);
      FieldPlannerController.VisitSummary saved = FieldPlannerController.upsertVisit(
        parseId(payload.get('visitId')),
        parseId(payload.get('accountId')),
        parseIsoDateTime(payload.get('startDateTime')),
        parseIsoDateTime(payload.get('endDateTime')),
        toStringValue(payload.get('status')),
        toStringValue(payload.get('visitType')),
        toStringValue(payload.get('cancellationReason')),
        parseId(payload.get('zetaProjectId')),
        toStringValue(payload.get('visitObjective'))
      );
      if (String.isNotBlank(action.clientVisitKey) && saved != null && saved.id != null) {
        visitMap.put(action.clientVisitKey, saved.id);
      }
      return;
    }
    if (type == 'SUBMIT_VISIT') {
      Id visitId = resolveVisitId(action, visitMap);
      FieldPlannerController.submitVisit(visitId);
      return;
    }
    if (type == 'CREATE_TIME_OFF') {
      Map<String, Object> payload = parsePayloadMap(action.payloadJson);
      FieldPlannerController.createTimeOff(
        toStringValue(payload.get('typeValue')),
        toStringValue(payload.get('spanType')),
        toStringValue(payload.get('durationHours')),
        parseIsoDateTime(payload.get('startDateTime')),
        toStringValue(payload.get('comments')),
        toStringValue(payload.get('stage'))
      );
      return;
    }
    // Unknown action types are ignored so future queue items do not block drain.
  }

  private static Map<String, Object> parsePayloadMap(String payloadJson) {
    if (String.isBlank(payloadJson)) {
      return new Map<String, Object>();
    }
    Object parsed = JSON.deserializeUntyped(payloadJson);
    if (parsed instanceof Map<String, Object>) {
      return (Map<String, Object>) parsed;
    }
    throw new AuraHandledException('payloadJson must be an object.');
  }

  private static Id parseId(Object value) {
    if (value == null) {
      return null;
    }
    String raw = String.valueOf(value);
    if (String.isBlank(raw) || raw.startsWith('local_')) {
      return null;
    }
    try {
      return Id.valueOf(raw);
    } catch (Exception ex) {
      return null;
    }
  }

  private static DateTime parseIsoDateTime(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof DateTime) {
      return (DateTime) value;
    }
    String raw = String.valueOf(value);
    if (String.isBlank(raw)) {
      return null;
    }
    return (DateTime) JSON.deserialize('"' + raw + '"', DateTime.class);
  }

  private static String toStringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Id resolveVisitId(OfflineAction action, Map<String, Id> visitMap) {
    if (action.visitId != null) {
      return action.visitId;
    }
    if (String.isNotBlank(action.clientVisitKey) && visitMap.containsKey(action.clientVisitKey)) {
      return visitMap.get(action.clientVisitKey);
    }
    throw new AuraHandledException('Visit Id is required for ' + action.actionType);
  }

  private static Id resolveSessionId(OfflineAction action, Map<String, Id> sessionMap) {
    if (String.isNotBlank(action.clientSessionKey) && sessionMap.containsKey(action.clientSessionKey)) {
      return sessionMap.get(action.clientSessionKey);
    }
    if (String.isNotBlank(action.clientSessionKey)) {
      try {
        return Id.valueOf(action.clientSessionKey);
      } catch (Exception ex) {
        // Not a Salesforce Id — fall through.
      }
    }
    throw new AuraHandledException('Session Id is required for ' + action.actionType);
  }
}
