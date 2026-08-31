@IsTest
private class ClmMetricsControllerOrgTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'CLM Ratings Wire Test');
    insert account;

    Product2 product = new Product2(Name = 'Wire Product', IsActive = true);
    insert product;

    insert new List<CLM_Presentation__c>{
      new CLM_Presentation__c(
        Name = 'Wire Deck',
        Status__c = 'Available',
        Format__c = 'PDF',
        Product__c = product.Id,
        Slide_Count__c = 1,
        Allow_Unaligned__c = true
      ),
      new CLM_Presentation__c(
        Name = 'Future Deck',
        Status__c = 'Available',
        Format__c = 'PDF',
        Product__c = product.Id,
        Slide_Count__c = 1,
        Allow_Unaligned__c = true,
        Start_Date__c = Date.today().addDays(10)
      ),
      new CLM_Presentation__c(
        Name = 'Territory Deck',
        Status__c = 'Available',
        Format__c = 'PDF',
        Product__c = product.Id,
        Slide_Count__c = 1,
        Allow_Unaligned__c = false,
        Territory_Ids__c = '0MIxxxxxxxxxxx'
      )
    };

    CLM_Presentation__c presentation = [
      SELECT Id
      FROM CLM_Presentation__c
      WHERE Name = 'Wire Deck'
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

  @IsTest
  static void sessionLifecycle_coversCorePaths() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    CLM_Presentation__c presentation = [
      SELECT Id
      FROM CLM_Presentation__c
      WHERE Name = 'Wire Deck'
      LIMIT 1
    ];
    CLM_Sequence__c sequence = [SELECT Id FROM CLM_Sequence__c LIMIT 1];

    Test.startTest();
    System.assertEquals(1, ClmMetricsController.getAvailablePresentations(visit.Id).size());
    System.assertEquals(1, ClmMetricsController.getRepPresentations().size());
    System.assertEquals(null, ClmMetricsController.getDeployedRatingLayoutJson());
    System.assertEquals(true, ClmMetricsController.getVisitSessions(null).isEmpty());
    System.assertEquals(true, ClmMetricsController.getSessionMessageResponses(null).isEmpty());

    ClmMetricsController.SessionSummary session =
      ClmMetricsController.startSession(visit.Id, presentation.Id);
    ClmMetricsController.logSlideEvent(session.id, sequence.Id, 8, false);
    ClmMetricsController.logSlideEvent(session.id, sequence.Id, 4, true);
    ClmMetricsController.logSlideEvent(session.id, null, 0, false);

    ClmMetricsController.MessageResponseInput response = new ClmMetricsController.MessageResponseInput();
    response.productName = 'Wire Product';
    response.messageName = 'Efficacy';
    response.sentiment = 'Positive';
    response.sortOrder = 1;
    ClmMetricsController.saveMessageResponses(
      session.id,
      new List<ClmMetricsController.MessageResponseInput>{ response, null }
    );
    System.assertEquals(1, ClmMetricsController.getSessionMessageResponses(session.id).size());
    ClmMetricsController.completeSession(session.id);

    ClmMetricsController.SessionSummary adHoc =
      ClmMetricsController.startAdHocPresentation(presentation.Id);
    ClmMetricsController.cancelSession(adHoc.id);
    System.assertNotEquals(null, ClmMetricsController.startAdHocSession(presentation.Id).visitId);

    Boolean startThrew = false;
    try {
      ClmMetricsController.startSession(null, null);
    } catch (AuraHandledException ex) {
      startThrew = true;
    }
    System.assertEquals(true, startThrew);
    Test.stopTest();
  }

  @IsTest
  static void ratingsWire_returnsDeployedLayout() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Product2 product = [SELECT Id FROM Product2 LIMIT 1];

    Test.startTest();
    ClmMetricsController.VisitRatingContext ctx =
      ClmMetricsController.loadAccountRatingContext(account.Id);
    System.assertEquals(account.Id, ctx.accountId);
    System.assertEquals(false, String.isBlank(ctx.layoutJson));
    System.assertNotEquals(null, ClmMetricsController.getRatingCaptureContext(visit.Id, null));

    Boolean emptySaveThrew = false;
    try {
      ClmMetricsController.saveAccountRatings(account.Id, ctx.layoutId, ctx.territory2Id, '[]', '{}');
    } catch (AuraHandledException ex) {
      emptySaveThrew = true;
    }
    System.assertEquals(true, emptySaveThrew);

    String fieldInputs = JSON.serialize(
      new List<Object>{
        new Map<String, Object>{
          'objectApiName' => 'Account',
          'fieldApiName' => 'Description',
          'valueJson' => 'Rated'
        },
        new Map<String, Object>{ 'objectApiName' => '', 'fieldApiName' => 'Skip' }
      }
    );
    String productRatings = JSON.serialize(
      new List<Object>{
        new Map<String, Object>{
          'product2Id' => product.Id,
          'values' => new List<Object>{
            new Map<String, Object>{
              'objectApiName' => 'Account',
              'fieldApiName' => 'Description',
              'valueJson' => 'Product Rated'
            }
          }
        },
        new Map<String, Object>{ 'product2Id' => null }
      }
    );
    try {
      ClmMetricsController.saveAccountRatings(
        account.Id,
        ctx.layoutId,
        ctx.territory2Id,
        fieldInputs,
        productRatings
      );
    } catch (Exception ignore) {
    }

    ClmMetricsController.saveVisitRatings(
      visit.Id,
      null,
      ctx.layoutId,
      new List<ClmMetricsController.VisitRatingFieldInput>()
    );
    System.assertEquals(
      true,
      ClmMetricsController.validateAccountRatings(account.Id, '{}').usedFallback
    );
    Test.stopTest();
  }
}