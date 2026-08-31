public with sharing class AccountActivityInsightsAggregator {
  private static final Integer MAX_VISITS = 100;
  private static final Integer MAX_LIST_ITEMS = 12;
  private static final Integer STALE_PRODUCT_DAYS = 90;

  private static final List<String> PAIN_KEYWORDS = new List<String>{
    'concern',
    'issue',
    'problem',
    'difficult',
    'challenge',
    'side effect',
    'cost',
    'price',
    'insurance',
    'adherence',
    'barrier',
    'objection',
    'hesitat',
    'reluctan',
    'negative',
    'unhappy',
    'dissatisf'
  };

  private static final List<String> POSITIVE_KEYWORDS = new List<String>{
    'positive',
    'interest',
    'enthusiastic',
    'pleased',
    'satisfied',
    'benefit',
    'efficacy',
    'improvement',
    'excited',
    'favorable',
    'happy',
    'success',
    'endorse',
    'strong data',
    'clinical data'
  };

  public static AccountActivityInsightsTypes.AccountVisitInsights build(Id accountId) {
    AccountActivityInsightsTypes.AccountVisitInsights insights = new AccountActivityInsightsTypes.AccountVisitInsights();
    insights.productsDiscussed = new List<String>();
    insights.painPoints = new List<String>();
    insights.positiveSignals = new List<String>();
    insights.customerFeedback = new List<String>();
    insights.suggestedTalkingPoints = new List<String>();
    insights.visitCount = 0;
    insights.presentationCount = 0;

    List<Account> accounts = [
      SELECT Name
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    String accountName = accounts.isEmpty() ? 'this account' : accounts[0].Name;

    List<Visit__c> visits = [
      SELECT
        Id,
        Name,
        Start_Date__c,
        Visit_Objective__c,
        Visit_Notes__c,
        Products_Discussed__c,
        Product_Details__c,
        Status__c
      FROM Visit__c
      WHERE Account__c = :accountId
      WITH USER_MODE
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 100
    ];
    insights.visitCount = visits.size();

    if (visits.isEmpty()) {
      insights.headline = 'No visit history yet';
      insights.summary =
        'No visits have been recorded for ' +
        accountName +
        '. Schedule a first call to begin building activity history.';
      insights.suggestedTalkingPoints.add('Introduce priority brands and confirm clinical interests.');
      return insights;
    }

    Set<Id> visitIds = new Set<Id>();
    for (Visit__c visit : visits) {
      visitIds.add(visit.Id);
    }

    Map<Id, List<String>> productNamesByVisit = getProductNamesFromTimeline(accountId);
    Map<Id, List<MessageSignal>> messageSignalsByVisit = getMessageSignalsByVisit(visitIds);
    Map<String, Date> lastProductDiscussedDate = new Map<String, Date>();
    Set<String> allProducts = new Set<String>();

    for (Visit__c visit : visits) {
      Date visitDay = visit.Start_Date__c != null ? visit.Start_Date__c.date() : null;
      List<String> visitProducts = new List<String>();
      visitProducts.addAll(productNamesByVisit.containsKey(visit.Id)
        ? productNamesByVisit.get(visit.Id)
        : splitProductNames(visit.Products_Discussed__c));
      for (String productName : visitProducts) {
        if (String.isBlank(productName)) {
          continue;
        }
        allProducts.add(productName);
        if (visitDay != null && !lastProductDiscussedDate.containsKey(productName)) {
          lastProductDiscussedDate.put(productName, visitDay);
        }
      }

      collectTextSignals(visit.Visit_Notes__c, visit.Start_Date__c, insights);
      collectTextSignals(visit.Product_Details__c, visit.Start_Date__c, insights);
      collectTextSignals(visit.Visit_Objective__c, visit.Start_Date__c, insights);

      if (String.isNotBlank(visit.Visit_Notes__c)) {
        addUnique(insights.customerFeedback, truncate(visit.Visit_Notes__c, 180));
      }

      List<MessageSignal> signals = messageSignalsByVisit.containsKey(visit.Id)
        ? messageSignalsByVisit.get(visit.Id)
        : new List<MessageSignal>();
      for (MessageSignal signal : signals) {
        String label = buildMessageLabel(signal);
        if (signal.isPositive) {
          addUnique(insights.positiveSignals, label);
        } else if (signal.isNegative) {
          addUnique(insights.painPoints, label);
        }
      }
    }

    insights.presentationCount = [
      SELECT COUNT()
      FROM CLM_Presentation_Session__c
      WHERE Account__c = :accountId AND Status__c = 'Completed'
      WITH USER_MODE
    ];

  insights.productsDiscussed = sortedList(allProducts);
    trimList(insights.productsDiscussed, MAX_LIST_ITEMS);
    trimList(insights.painPoints, MAX_LIST_ITEMS);
    trimList(insights.positiveSignals, MAX_LIST_ITEMS);
    trimList(insights.customerFeedback, MAX_LIST_ITEMS);

    buildTalkingPoints(insights, lastProductDiscussedDate, visits);

    insights.headline = buildHeadline(accountName, insights);
    insights.summary = buildSummary(accountName, insights, visits.size());
    trimList(insights.suggestedTalkingPoints, MAX_LIST_ITEMS);
    return insights;
  }

  private static void buildTalkingPoints(
    AccountActivityInsightsTypes.AccountVisitInsights insights,
    Map<String, Date> lastProductDiscussedDate,
    List<Visit__c> visits
  ) {
    if (!insights.painPoints.isEmpty()) {
      insights.suggestedTalkingPoints.add(
        'Address recent concerns: ' + joinTop(insights.painPoints, 2) + '.'
      );
    }
    if (!insights.positiveSignals.isEmpty()) {
      insights.suggestedTalkingPoints.add(
        'Leverage positive engagement on ' + joinTop(insights.positiveSignals, 2) + '.'
      );
    }

    Date staleCutoff = Date.today().addDays(-STALE_PRODUCT_DAYS);
    List<String> staleProducts = new List<String>();
    for (String productName : insights.productsDiscussed) {
      Date lastDiscussed = lastProductDiscussedDate.get(productName);
      if (lastDiscussed != null && lastDiscussed < staleCutoff) {
        staleProducts.add(productName);
      }
    }
    if (!staleProducts.isEmpty()) {
      insights.suggestedTalkingPoints.add(
        'Re-detail products not discussed recently: ' + joinTop(staleProducts, 3) + '.'
      );
    }

    Visit__c latestVisit = visits[0];
    if (String.isNotBlank(latestVisit.Visit_Objective__c)) {
      insights.suggestedTalkingPoints.add(
        'Follow up on the latest visit objective: ' + truncate(latestVisit.Visit_Objective__c, 120)
      );
    }

    if (insights.suggestedTalkingPoints.isEmpty()) {
      insights.suggestedTalkingPoints.add('Confirm therapeutic priorities and align next detail to recent CLM themes.');
    }
  }

  private static String buildHeadline(
    String accountName,
    AccountActivityInsightsTypes.AccountVisitInsights insights
  ) {
    Integer productCount = insights.productsDiscussed.size();
  String productPhrase = productCount == 0 ? 'no products detailed yet' : productCount + ' product(s) discussed';
    if (!insights.painPoints.isEmpty() && !insights.positiveSignals.isEmpty()) {
      return accountName + ': mixed signals across ' + productPhrase;
    }
    if (!insights.painPoints.isEmpty()) {
      return accountName + ': concerns surfaced in recent visits';
    }
    if (!insights.positiveSignals.isEmpty()) {
      return accountName + ': positive engagement on ' + productPhrase;
    }
    return accountName + ': ' + insights.visitCount + ' visit(s) on record';
  }

  private static String buildSummary(
    String accountName,
    AccountActivityInsightsTypes.AccountVisitInsights insights,
    Integer visitCount
  ) {
    List<String> parts = new List<String>();
    parts.add(
      'Across ' +
      visitCount +
      ' visit(s) and ' +
      insights.presentationCount +
      ' completed presentation(s), ' +
      accountName +
      ' shows ' +
      insights.productsDiscussed.size() +
      ' product(s) in the discussion history.'
    );
    if (!insights.painPoints.isEmpty()) {
      parts.add('Pain points include ' + joinTop(insights.painPoints, 2) + '.');
    }
    if (!insights.positiveSignals.isEmpty()) {
      parts.add('Positive signals include ' + joinTop(insights.positiveSignals, 2) + '.');
    }
    return String.join(parts, ' ');
  }

  private static Map<Id, List<String>> getProductNamesFromTimeline(Id accountId) {
    Map<Id, List<String>> productsByVisit = new Map<Id, List<String>>();
    List<AccountActivityController.TimelineItem> timeline =
      AccountActivityController.getAccountActivityTimeline(accountId, MAX_VISITS);
    for (AccountActivityController.TimelineItem item : timeline) {
      if (item.type != 'visit' || item.recordId == null) {
        continue;
      }
      List<String> names = item.productNames != null
        ? new List<String>(item.productNames)
        : new List<String>();
      if (names.isEmpty() && item.products != null) {
        for (AccountActivityController.ProductChip chip : item.products) {
          if (String.isNotBlank(chip.productName)) {
            names.add(chip.productName);
          }
        }
      }
      productsByVisit.put(item.recordId, names);
    }
    return productsByVisit;
  }

  private static Map<Id, List<MessageSignal>> getMessageSignalsByVisit(Set<Id> visitIds) {
    Map<Id, List<MessageSignal>> signalsByVisit = new Map<Id, List<MessageSignal>>();
    if (visitIds.isEmpty()) {
      return signalsByVisit;
    }

    Set<Id> sessionIds = new Set<Id>();
    for (CLM_Presentation_Session__c session : [
      SELECT Id, Visit__c
      FROM CLM_Presentation_Session__c
      WHERE Visit__c IN :visitIds AND Status__c = 'Completed'
      WITH USER_MODE
    ]) {
      sessionIds.add(session.Id);
      if (!signalsByVisit.containsKey(session.Visit__c)) {
        signalsByVisit.put(session.Visit__c, new List<MessageSignal>());
      }
    }

    if (sessionIds.isEmpty()) {
      return signalsByVisit;
    }

    for (CLM_Message_Response__c response : [
      SELECT
        CLM_Presentation_Session__c,
        CLM_Presentation_Session__r.Visit__c,
        Product_Name__c,
        Message_Name__c,
        Sentiment__c
      FROM CLM_Message_Response__c
      WHERE CLM_Presentation_Session__c IN :sessionIds
      WITH USER_MODE
      ORDER BY Sort_Order__c ASC NULLS LAST
    ]) {
      Id visitId = response.CLM_Presentation_Session__r?.Visit__c;
      if (visitId == null) {
        continue;
      }
      if (!signalsByVisit.containsKey(visitId)) {
        signalsByVisit.put(visitId, new List<MessageSignal>());
      }
      MessageSignal signal = new MessageSignal();
      signal.productName = response.Product_Name__c;
      signal.messageName = response.Message_Name__c;
      signal.sentiment = response.Sentiment__c;
      signal.isPositive = 'Positive'.equalsIgnoreCase(response.Sentiment__c);
      signal.isNegative = 'Negative'.equalsIgnoreCase(response.Sentiment__c);
      signalsByVisit.get(visitId).add(signal);
    }
    return signalsByVisit;
  }

  private static void collectTextSignals(
    String text,
    Datetime activityDate,
    AccountActivityInsightsTypes.AccountVisitInsights insights
  ) {
    if (String.isBlank(text)) {
      return;
    }
    String normalized = text.toLowerCase();
    String prefix = activityDate != null ? activityDate.format('MMM d') + ': ' : '';
    for (String keyword : PAIN_KEYWORDS) {
      if (normalized.contains(keyword)) {
        addUnique(insights.painPoints, prefix + truncate(text, 140));
        break;
      }
    }
    for (String keyword : POSITIVE_KEYWORDS) {
      if (normalized.contains(keyword)) {
        addUnique(insights.positiveSignals, prefix + truncate(text, 140));
        break;
      }
    }
  }

  private static String buildMessageLabel(MessageSignal signal) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(signal.productName)) {
      parts.add(signal.productName);
    }
    if (String.isNotBlank(signal.messageName)) {
      parts.add(signal.messageName);
    }
    String label = parts.isEmpty() ? 'CLM message' : String.join(parts, ' — ');
    if (String.isNotBlank(signal.sentiment)) {
      label += ' (' + signal.sentiment + ')';
    }
    return label;
  }

  private static List<String> splitProductNames(String productsDiscussed) {
    List<String> names = new List<String>();
    if (String.isBlank(productsDiscussed)) {
      return names;
    }
    for (String part : productsDiscussed.split('[;,]')) {
      String trimmed = part.trim();
      if (String.isNotBlank(trimmed)) {
        names.add(trimmed);
      }
    }
    return names;
  }

  private static List<String> sortedList(Set<String> values) {
    List<String> sorted = new List<String>(values);
    sorted.sort();
    return sorted;
  }

  private static void addUnique(List<String> target, String value) {
    if (String.isBlank(value) || target.contains(value)) {
      return;
    }
    target.add(value);
  }

  private static void trimList(List<String> target, Integer maxSize) {
    if (target == null || target.size() <= maxSize) {
      return;
    }
    List<String> trimmed = new List<String>();
    for (Integer i = 0; i < maxSize; i++) {
      trimmed.add(target[i]);
    }
    target.clear();
    target.addAll(trimmed);
  }

  private static String joinTop(List<String> values, Integer count) {
    List<String> slice = new List<String>();
    Integer itemCount = Math.min(count, values.size());
    for (Integer i = 0; i < itemCount; i++) {
      slice.add(values[i]);
    }
    return String.join(slice, '; ');
  }

  private static String truncate(String value, Integer maxLength) {
    if (String.isBlank(value)) {
      return value;
    }
    String normalized = value.replaceAll('\\s+', ' ').trim();
    if (normalized.length() <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength - 1) + '…';
  }

  private class MessageSignal {
    public String productName;
    public String messageName;
    public String sentiment;
    public Boolean isPositive = false;
    public Boolean isNegative = false;
  }
}