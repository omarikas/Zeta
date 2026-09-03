@RestResource(urlMapping='/clm/v1/*')
global with sharing class ClmMobileRestService {

  global class ErrorResponse {
    public String message;
    public ErrorResponse(String message) {
      this.message = message;
    }
  }

  /**
   * Serializes a ClmMetricsController.SessionSummary into a plain map for the
   * mobile client. Includes the fields clmPlayer relies on.
   */
  private static Map<String, Object> sessionSummaryToMap(ClmMetricsController.SessionSummary s) {
    if (s == null) {
      return new Map<String, Object>();
    }
    List<Object> sequences = new List<Object>();
    if (s.sequences != null) {
      for (ClmMetricsController.SequenceDetail seq : s.sequences) {
        sequences.add(
          new Map<String, Object>{
            'id' => seq.id,
            'sequenceOrder' => seq.sequenceOrder,
            'sequenceName' => seq.sequenceName,
            'fileName' => seq.fileName,
            'productNames' => seq.productNames,
            'messageNames' => seq.messageNames,
            'isMandatory' => seq.isMandatory == true,
            'thumbnailUrl' => seq.thumbnailUrl,
            'slideImageUrl' => seq.slideImageUrl,
            'pageNumber' => seq.pageNumber,
            'htmlEntryPoint' => seq.htmlEntryPoint
          }
        );
      }
    }
    List<Object> metrics = new List<Object>();
    if (s.metrics != null) {
      for (ClmMetricsController.SlideMetricSummary m : s.metrics) {
        metrics.add(
          new Map<String, Object>{
            'sequenceId' => m.sequenceId,
            'sequenceOrder' => m.sequenceOrder,
            'sequenceName' => m.sequenceName,
            'dwellTimeSeconds' => m.dwellTimeSeconds,
            'wasPresented' => m.wasPresented == true,
            'thumbnailUrl' => m.thumbnailUrl
          }
        );
      }
    }
    return new Map<String, Object>{
      'id' => s.id,
      'visitId' => s.visitId,
      'name' => s.name,
      'presentationId' => s.presentationId,
      'presentationName' => s.presentationName,
      'formatType' => s.formatType,
      'contentDocumentId' => s.contentDocumentId,
      'contentVersionId' => s.contentVersionId,
      'publicContentUrl' => s.publicContentUrl,
      'contentSize' => s.contentSize,
      'status' => s.status,
      'startedAt' => s.startedAt,
      'endedAt' => s.endedAt,
      'totalDurationSeconds' => s.totalDurationSeconds,
      'slidesPresentedCount' => s.slidesPresentedCount,
      'slideCount' => s.slideCount,
      'trackingPaused' => s.trackingPaused == true,
      'productName' => s.productName,
      'productImageUrl' => s.productImageUrl,
      'sequences' => sequences,
      'metrics' => metrics
    };
  }

  @HttpGet
  global static void doGet() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = req.requestURI.substringAfter('/clm/v1');
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      Map<String, String> params = req.params;

      if (path == 'presentations') {
        List<Object> out = new List<Object>();
        for (ClmMetricsController.PresentationSummary p : ClmMetricsController.getRepPresentations()) {
          out.add(
            new Map<String, Object>{
              'id' => p.id,
              'name' => p.name,
              'status' => p.status,
              'formatType' => p.formatType,
              'productName' => p.productName,
              'imageUrl' => p.imageUrl,
              'slideCount' => p.slideCount,
              'tags' => p.tags
            }
          );
        }
        writeJson(res, 200, out);
        return;
      }

      if (path.startsWith('sessions/')) {
        Id sessionId = (Id) path.substringAfter('sessions/');
        writeJson(res, 200, sessionSummaryToMap(ClmMetricsController.getSessionDetail(sessionId)));
        return;
      }

      writeJson(res, 404, new ErrorResponse('Unknown GET path: ' + path));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  @HttpPost
  global static void doPost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = req.requestURI.substringAfter('/clm/v1');
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      String body = req.requestBody == null ? '{}' : req.requestBody.toString();
      Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);

      if (path == 'sessions/start') {
        Id visitId = blankToNullId((String) m.get('visitId'));
        Id presentationId = blankToNullId((String) m.get('presentationId'));
        ClmMetricsController.SessionSummary s = ClmMetricsController.startSession(visitId, presentationId);
        writeJson(res, 200, sessionSummaryToMap(s));
        return;
      }

      if (path == 'sessions/start-ad-hoc') {
        Id presentationId = blankToNullId((String) m.get('presentationId'));
        ClmMetricsController.SessionSummary s = ClmMetricsController.startAdHocPresentation(presentationId);
        writeJson(res, 200, sessionSummaryToMap(s));
        return;
      }

      if (path == 'sessions/slide-event') {
        ClmMetricsController.logSlideEvent(
          blankToNullId((String) m.get('sessionId')),
          blankToNullId((String) m.get('sequenceId')),
          toDecimal(m.get('dwellSeconds')),
          toBoolean(m.get('trackingPaused'))
        );
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }

      if (path == 'sessions/complete') {
        ClmMetricsController.SessionSummary s = ClmMetricsController.completeSession(
          blankToNullId((String) m.get('sessionId'))
        );
        writeJson(res, 200, sessionSummaryToMap(s));
        return;
      }

      if (path == 'sessions/cancel') {
        ClmMetricsController.cancelSession(blankToNullId((String) m.get('sessionId')));
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }

      if (path == 'sessions/message-responses') {
        ClmMetricsController.saveMessageResponses(
          blankToNullId((String) m.get('sessionId')),
          parseMessageResponses(m.get('responses'))
        );
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }

      if (path == 'sessions/message-responses/fetch') {
        writeJson(
          res,
          200,
          ClmMetricsController.getSessionMessageResponses(blankToNullId((String) m.get('sessionId')))
        );
        return;
      }

      if (path == 'pdf-base64') {
        String base64 = ClmPdfViewerController.getPdfBase64ForPlayer((String) m.get('contentDocumentId'));
        writeJson(res, 200, new Map<String, Object>{ 'base64' => base64 });
        return;
      }

      writeJson(res, 404, new ErrorResponse('Unknown POST path: ' + path));
    } catch (ClmPdfViewerController.ClmViewerException e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  private static List<ClmMetricsController.MessageResponseInput> parseMessageResponses(Object raw) {
    List<ClmMetricsController.MessageResponseInput> out = new List<ClmMetricsController.MessageResponseInput>();
    if (!(raw instanceof List<Object>)) {
      return out;
    }
    for (Object item : (List<Object>) raw) {
      if (!(item instanceof Map<String, Object>)) {
        continue;
      }
      Map<String, Object> row = (Map<String, Object>) item;
      ClmMetricsController.MessageResponseInput input = new ClmMetricsController.MessageResponseInput();
      input.productName = (String) row.get('productName');
      input.messageName = (String) row.get('messageName');
      input.sentiment = (String) row.get('sentiment');
      input.sortOrder = toInteger(row.get('sortOrder'));
      out.add(input);
    }
    return out;
  }

  private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
    res.statusCode = statusCode;
    res.responseBody = Blob.valueOf(JSON.serialize(payload));
  }

  private static Id blankToNullId(String value) {
    return String.isBlank(value) ? null : (Id) value;
  }

  private static String toStringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Decimal toDecimal(Object value) {
    if (value == null) {
      return null;
    }
    return Decimal.valueOf(String.valueOf(value));
  }

  private static Integer toInteger(Object value) {
    if (value == null) {
      return null;
    }
    return Integer.valueOf(String.valueOf(value));
  }

  private static Boolean toBoolean(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    return Boolean.valueOf(String.valueOf(value));
  }
}
