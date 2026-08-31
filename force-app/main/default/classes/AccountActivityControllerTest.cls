@IsTest
private class AccountActivityControllerTest {

  @TestSetup
  static void setupData() {
    Account hcp = buildHcpAccount('Dr Timeline HCP');
    insert hcp;

    Product2 product = new Product2(
      Name = 'Timeline Product',
      IsActive = true,
      Product_Image_URL__c = 'https://example.com/timeline-product.png'
    );
    insert product;

    DateTime visitStart = DateTime.newInstance(Date.today().addDays(-3), Time.newInstance(10, 0, 0, 0));
    Visit__c visit = new Visit__c(
      Account__c = hcp.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = visitStart,
      End_Date__c = visitStart.addHours(1),
      Status__c = 'Completed',
      Visit_Type__c = 'Unplanned',
      Visit_Objective__c = 'Discuss treatment updates',
      Visit_Notes__c = 'Positive engagement on clinical data.',
      Products_Discussed__c = 'Timeline Product'
    );
    insert visit;

    Visit_Product_Detail__c productDetail = new Visit_Product_Detail__c(
      Visit__c = visit.Id,
      Product2__c = product.Id,
      Display_Order__c = 1,
      Detail_Type__c = 'Detail'
    );
    insert productDetail;

    CLM_Presentation__c presentation = new CLM_Presentation__c(
      Name = 'Timeline Deck',
      Status__c = 'Available',
      Format__c = 'PDF',
      Product__c = product.Id,
      Slide_Count__c = 10
    );
    insert presentation;

    CLM_Sequence__c sequence = new CLM_Sequence__c(
      CLM_Presentation__c = presentation.Id,
      Sequence_Order__c = 1,
      Sequence_Name__c = 'Opening Slide',
      Slide_Image_URL__c = 'https://example.com/slide-1.png'
    );
    insert sequence;

    CLM_Presentation_Session__c session = new CLM_Presentation_Session__c(
      Visit__c = visit.Id,
      CLM_Presentation__c = presentation.Id,
      Account__c = hcp.Id,
      User__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Started_At__c = visitStart.addMinutes(15),
      Ended_At__c = visitStart.addMinutes(45),
      Total_Duration_Seconds__c = 1800,
      Slides_Presented_Count__c = 8
    );
    insert session;

    insert new CLM_Message_Response__c(
      CLM_Presentation_Session__c = session.Id,
      Product_Name__c = 'Timeline Product',
      Message_Name__c = 'Efficacy data',
      Sentiment__c = 'Positive',
      Sort_Order__c = 1
    );

    insert new CLM_Slide_Metric__c(
      CLM_Presentation_Session__c = session.Id,
      CLM_Sequence__c = sequence.Id,
      Sequence_Order__c = 1,
      Sequence_Name__c = 'Opening Slide',
      Dwell_Time_Seconds__c = 45,
      Was_Presented__c = true
    );
  }

  @IsTest
  static void getHcpAccountOverview_returnsFourSpecialties() {
    Account hcp = getHcpAccount();

    Test.startTest();
    AccountActivityController.HcpAccountOverview overview =
      AccountActivityController.getHcpAccountOverview(hcp.Id);
    Test.stopTest();

    System.assertEquals('Dr Timeline HCP', overview.name);
    System.assertEquals(true, overview.isHcp);
    System.assertEquals(4, overview.specialties.size());
    System.assertEquals('Specialty 1', overview.specialties[0].label);
    System.assertEquals('Specialty 4', overview.specialties[3].label);
  }

  @IsTest
  static void getAccountActivityTimeline_returnsVisitWithNestedPresentations() {
    Account hcp = getHcpAccount();

    Test.startTest();
    List<AccountActivityController.TimelineItem> timeline =
      AccountActivityController.getAccountActivityTimeline(hcp.Id, 50);
    Test.stopTest();

    System.assert(timeline.size() >= 1, 'Expected at least one timeline entry.');

    AccountActivityController.TimelineItem visitItem;
    for (AccountActivityController.TimelineItem item : timeline) {
      if (item.type == 'visit') {
        visitItem = item;
        break;
      }
    }

    System.assertNotEquals(null, visitItem, 'Expected a visit timeline item.');
    System.assert(visitItem.title.contains('Dr Timeline HCP'), 'Visit title should include account name.');
    System.assertEquals('Unplanned', visitItem.channel);
    System.assert(visitItem.address.contains('1 Nile St'));
    System.assert(visitItem.address.contains('Cairo'));
    System.assertNotEquals(null, visitItem.dateGroupLabel);
    System.assertEquals(1, visitItem.presentations.size());
    System.assertEquals('Timeline Deck', visitItem.presentations[0].presentationName);
    System.assertEquals('8/10 slides presented', visitItem.presentations[0].slidesLabel);
    System.assertEquals(1, visitItem.presentations[0].slideThumbnails.size());
    System.assertEquals(
      'https://example.com/slide-1.png',
      visitItem.presentations[0].slideThumbnails[0].thumbnailUrl
    );

    Boolean foundVisitProductImage = false;
    for (AccountActivityController.ProductChip chip : visitItem.products) {
      if (chip.productName == 'Timeline Product') {
        System.assertEquals('https://example.com/timeline-product.png', chip.imageUrl);
        foundVisitProductImage = true;
      }
    }
    System.assertEquals(true, foundVisitProductImage, 'Expected visit product chip with image URL');
  }

  @IsTest
  static void getAccountActivityTimeline_standalonePresentationWhenNoVisit() {
    Account hcp = getHcpAccount();
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Timeline Product' LIMIT 1];
    CLM_Presentation__c presentation = new CLM_Presentation__c(
      Name = 'Standalone Deck',
      Status__c = 'Available',
      Format__c = 'PDF',
      Product__c = product.Id,
      Slide_Count__c = 4
    );
    insert presentation;

    insert new CLM_Presentation_Session__c(
      CLM_Presentation__c = presentation.Id,
      Account__c = hcp.Id,
      User__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Started_At__c = DateTime.now().addDays(-1),
      Total_Duration_Seconds__c = 120,
      Slides_Presented_Count__c = 2
    );

    Test.startTest();
    List<AccountActivityController.TimelineItem> timeline =
      AccountActivityController.getAccountActivityTimeline(hcp.Id, 50);
    Test.stopTest();

    Boolean foundStandalone = false;
    for (AccountActivityController.TimelineItem item : timeline) {
      if (item.type == 'presentation' && item.title == 'Standalone Deck') {
        foundStandalone = true;
        System.assertEquals(1, item.presentations.size());
        System.assertEquals('Standalone Deck', item.presentations[0].presentationName);
      }
    }
    System.assertEquals(true, foundStandalone, 'Expected standalone presentation item.');
  }

  @IsTest
  static void getAccountVisitInsights_returnsStructuredSummary() {
    Account hcp = getHcpAccount();

    Test.startTest();
    AccountActivityInsightsTypes.AccountVisitInsights insights =
      AccountActivityController.getAccountVisitInsights(hcp.Id);
    Test.stopTest();

    System.assertNotEquals(null, insights.headline);
    System.assertEquals(1, insights.visitCount);
    System.assertEquals(1, insights.presentationCount);
    System.assertEquals(
      AccountActivityInsightsTypes.SOURCE_STRUCTURED,
      insights.source
    );
    System.assert(insights.productsDiscussed.contains('Timeline Product'));
    System.assert(!insights.positiveSignals.isEmpty());
    System.assert(!insights.suggestedTalkingPoints.isEmpty());
  }

  @IsTest
  static void getAccountVisitInsights_agentforceWhenEinsteinSucceeds() {
    Account hcp = getHcpAccount();
    AccountActivityEinsteinClient.testForceFailure = false;
    AccountActivityEinsteinClient.testResponseJson =
      '{"headline":"AI headline","summary":"AI summary","productsDiscussed":["Timeline Product"],"painPoints":[],"positiveSignals":["Strong interest"],"customerFeedback":[],"suggestedTalkingPoints":["Ask about efficacy"]}';

    Test.startTest();
    AccountActivityInsightsTypes.AccountVisitInsights insights =
      AccountActivityController.getAccountVisitInsights(hcp.Id);
    Test.stopTest();

    System.assertEquals('AI headline', insights.headline);
    System.assertEquals(AccountActivityInsightsTypes.SOURCE_AGENTFORCE, insights.source);
    AccountActivityEinsteinClient.testResponseJson = null;

    AccountActivityEinsteinClient.testForceFailure = true;
    AccountActivityInsightsTypes.AccountVisitInsights failed =
      AccountActivityController.getAccountVisitInsights(hcp.Id);
    System.assertEquals(AccountActivityInsightsTypes.SOURCE_STRUCTURED, failed.source);
    AccountActivityEinsteinClient.testForceFailure = false;

    AccountActivityEinsteinClient.testResponseJson = 'not-json';
    AccountActivityInsightsTypes.AccountVisitInsights invalid =
      AccountActivityController.getAccountVisitInsights(hcp.Id);
    System.assertEquals(AccountActivityInsightsTypes.SOURCE_STRUCTURED, invalid.source);
    AccountActivityEinsteinClient.testResponseJson = null;
  }

  @IsTest
  static void getAccountActivityTimeline_emptyForNullAccount() {
    Test.startTest();
    List<AccountActivityController.TimelineItem> timeline =
      AccountActivityController.getAccountActivityTimeline(null, 10);
    Test.stopTest();

    System.assertEquals(0, timeline.size());
  }

  private static Account getHcpAccount() {
    return [SELECT Id FROM Account WHERE Name = 'Dr Timeline HCP' LIMIT 1];
  }

  private static Account buildHcpAccount(String label) {
    Account account = new Account(
      Name = label,
      BillingCity = 'Cairo',
      BillingStreet = '1 Nile St',
      Specialty_1__c = 'Cardiology',
      Tier__c = 'A',
      Professional_Designation__c = 'MD',
      Account_Status__c = 'Active'
    );
    Id hcpRecordTypeId = getHcpRecordTypeId();
    if (hcpRecordTypeId != null) {
      account.RecordTypeId = hcpRecordTypeId;
    }
    return account;
  }

  private static Id getHcpRecordTypeId() {
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName = 'Medical_Professional_HCP'
      LIMIT 1
    ];
    return hcpTypes.isEmpty() ? null : hcpTypes[0].Id;
  }
}