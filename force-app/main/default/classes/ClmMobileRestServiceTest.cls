@IsTest
private class ClmMobileRestServiceTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'CLM Mobile Rest Account');
    insert account;

    Product2 product = new Product2(Name = 'Mobile Product', IsActive = true);
    insert product;

    insert new List<CLM_Presentation__c>{
      new CLM_Presentation__c(
        Name = 'Mobile Deck',
        Status__c = 'Available',
        Format__c = 'PDF',
        Product__c = product.Id,
        Slide_Count__c = 1,
        Allow_Unaligned__c = true
      ),
      new CLM_Presentation__c(
        Name = 'Mobile Future Deck',
        Status__c = 'Available',
        Format__c = 'PDF',
        Product__c = product.Id,
        Slide_Count__c = 1,
        Allow_Unaligned__c = true,
        Start_Date__c = Date.today().addDays(10)
      )
    };

    CLM_Presentation__c presentation = [
      SELECT Id
      FROM CLM_Presentation__c
      WHERE Name = 'Mobile Deck'
      LIMIT 1
    ];
    insert new CLM_Sequence__c(
      CLM_Presentation__c = presentation.Id,
      Sequence_Order__c = 1,
      Sequence_Name__c = 'Intro',
      Name = 'Intro'
    );

    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft'
    );
  }

  private static RestResponse invokeGet(String path) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/clm/v1/' + path;
    req.httpMethod = 'GET';
    RestContext.request = req;
    RestContext.response = res;
    ClmMobileRestService.doGet();
    return res;
  }

  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/clm/v1/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    ClmMobileRestService.doPost();
    return res;
  }

  @IsTest
  static void getPresentations_returnsOnlyAvailableInWindow() {
    Test.startTest();
    RestResponse res = invokeGet('presentations');
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    List<Object> rows = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
    System.assertEquals(1, rows.size(), 'Only the in-window unaligned available deck should surface.');
    Map<String, Object> row = (Map<String, Object>) rows[0];
    System.assertEquals('Mobile Deck', row.get('name'));
    System.assertEquals('PDF', row.get('formatType'));
    System.assertEquals(1, row.get('slideCount'));
    System.assertNotEquals(null, row.get('id'));
  }

  @IsTest
  static void getPresentations_emptyWhenNoAvailable() {
    // Closes the date window so the only available deck is filtered out.
    List<CLM_Presentation__c> all = [SELECT Id, Status__c, End_Date__c FROM CLM_Presentation__c];
    for (CLM_Presentation__c p : all) {
      p.Status__c = 'Draft';
    }
    update all;

    Test.startTest();
    RestResponse res = invokeGet('presentations');
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    List<Object> rows = (List<Object>) JSON.deserializeUntyped(res.responseBody.toString());
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void getUnknownPath_returns404() {
    Test.startTest();
    RestResponse res = invokeGet('not-a-real-path');
    Test.stopTest();
    System.assertEquals(404, res.statusCode);
  }

  @IsTest
  static void postStartAndComplete_roundTrip() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    CLM_Presentation__c presentation = [
      SELECT Id
      FROM CLM_Presentation__c
      WHERE Name = 'Mobile Deck'
      LIMIT 1
    ];

    Test.startTest();
    RestResponse startRes = invokePost(
      'sessions/start',
      JSON.serialize(
        new Map<String, Object>{
          'visitId' => visit.Id,
          'presentationId' => presentation.Id
        }
      )
    );
    System.assertEquals(200, startRes.statusCode);
    Map<String, Object> session = (Map<String, Object>) JSON.deserializeUntyped(
      startRes.responseBody.toString()
    );
    System.assertEquals('Mobile Deck', session.get('presentationName'));
    System.assertEquals('Active', session.get('status'));
    System.assertNotEquals(null, session.get('id'));

    String sessionId = String.valueOf(session.get('id'));

    RestResponse slideRes = invokePost(
      'sessions/slide-event',
      JSON.serialize(
        new Map<String, Object>{
          'sessionId' => sessionId,
          'sequenceId' => null,
          'dwellSeconds' => 5,
          'trackingPaused' => false
        }
      )
    );
    System.assertEquals(200, slideRes.statusCode);

    RestResponse fetchRes = invokePost(
      'sessions/message-responses/fetch',
      JSON.serialize(new Map<String, Object>{ 'sessionId' => sessionId })
    );
    System.assertEquals(200, fetchRes.statusCode);
    List<Object> fetched = (List<Object>) JSON.deserializeUntyped(fetchRes.responseBody.toString());
    System.assertEquals(0, fetched.size());

    RestResponse saveRes = invokePost(
      'sessions/message-responses',
      JSON.serialize(
        new Map<String, Object>{
          'sessionId' => sessionId,
          'responses' => new List<Object>{
            new Map<String, Object>{
              'productName' => 'Mobile Product',
              'messageName' => 'Efficacy',
              'sentiment' => 'Positive',
              'sortOrder' => 1
            }
          }
        }
      )
    );
    System.assertEquals(200, saveRes.statusCode);

    RestResponse completeRes = invokePost(
      'sessions/complete',
      JSON.serialize(new Map<String, Object>{ 'sessionId' => sessionId })
    );
    System.assertEquals(200, completeRes.statusCode);
    Map<String, Object> completed = (Map<String, Object>) JSON.deserializeUntyped(
      completeRes.responseBody.toString()
    );
    System.assertEquals('Completed', completed.get('status'));

    RestResponse detailRes = invokeGet('sessions/' + sessionId);
    System.assertEquals(200, detailRes.statusCode);
    Map<String, Object> detail = (Map<String, Object>) JSON.deserializeUntyped(
      detailRes.responseBody.toString()
    );
    System.assertEquals('Completed', detail.get('status'));
    Test.stopTest();
  }

  @IsTest
  static void postAdHocCancelAndSlideEvent_ok() {
    CLM_Presentation__c presentation = [
      SELECT Id
      FROM CLM_Presentation__c
      WHERE Name = 'Mobile Deck'
      LIMIT 1
    ];

    Test.startTest();
    RestResponse adHocRes = invokePost(
      'sessions/start-ad-hoc',
      JSON.serialize(new Map<String, Object>{ 'presentationId' => presentation.Id })
    );
    System.assertEquals(200, adHocRes.statusCode);
    Map<String, Object> adHoc = (Map<String, Object>) JSON.deserializeUntyped(
      adHocRes.responseBody.toString()
    );
    System.assertEquals('Active', adHoc.get('status'));
    System.assertNotEquals(null, adHoc.get('visitId'));
    String sessionId = String.valueOf(adHoc.get('id'));

    RestResponse slideRes = invokePost(
      'sessions/slide-event',
      JSON.serialize(
        new Map<String, Object>{
          'sessionId' => sessionId,
          'sequenceId' => null,
          'dwellSeconds' => 3,
          'trackingPaused' => false
        }
      )
    );
    System.assertEquals(200, slideRes.statusCode);

    RestResponse cancelRes = invokePost(
      'sessions/cancel',
      JSON.serialize(new Map<String, Object>{ 'sessionId' => sessionId })
    );
    System.assertEquals(200, cancelRes.statusCode);
    Test.stopTest();
  }

  @IsTest
  static void postStart_missingIds_returns400() {
    Test.startTest();
    RestResponse res = invokePost('sessions/start', '{}');
    Test.stopTest();
    System.assertEquals(400, res.statusCode);
  }

  @IsTest
  static void postUnknownPath_returns404() {
    Test.startTest();
    RestResponse res = invokePost('not-a-real-path', '{}');
    Test.stopTest();
    System.assertEquals(404, res.statusCode);
  }

  @IsTest
  static void postPdfBase64_handlesMissingDocument() {
    Test.startTest();
    RestResponse res = invokePost(
      'pdf-base64',
      JSON.serialize(new Map<String, Object>{ 'contentDocumentId' => '0xx000000000000AAA' })
    );
    Test.stopTest();
    // Blank/fake document id yields a ClmViewerException -> 400, not a crash.
    System.assertEquals(400, res.statusCode);
  }
}
