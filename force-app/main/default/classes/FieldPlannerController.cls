public with sharing class FieldPlannerController {

  public class AccountSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String specialtyApiValue;
    @AuraEnabled
    public String classification;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String recordTypeName;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public String brickName;
    @AuraEnabled
    public String frequencyStatus;
    @AuraEnabled
    public Decimal actualVisits;
    @AuraEnabled
    public Decimal targetVisits;
    @AuraEnabled
    public Integer plannedVisits;
    @AuraEnabled
    public String paceStatus;
    @AuraEnabled
    public String paceStatusLabel;
  }

  public class FilterOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public FilterOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class PlannerFilterOptions {
    @AuraEnabled
    public List<FilterOption> specialtyOptions;
    @AuraEnabled
    public List<FilterOption> classificationOptions;
    @AuraEnabled
    public List<FilterOption> brickOptions;
  }

  public class AccountVisitTarget {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Decimal targetVisitFrequency;
    @AuraEnabled
    public Decimal actualVisits;
    @AuraEnabled
    public Decimal visitGap;
    @AuraEnabled
    public String frequencyStatus;
    @AuraEnabled
    public String potentiality;
  }

  public class PlannerViewerOption {
    @AuraEnabled
    public Id territoryId;
    @AuraEnabled
    public String territoryName;
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String userName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String parentTerritoryName;
  }

  public class PlannerViewerContext {
    @AuraEnabled
    public String viewerMode;
    @AuraEnabled
    public Boolean canSwitchView;
    @AuraEnabled
    public Id topTerritoryId;
    @AuraEnabled
    public String topTerritoryName;
    @AuraEnabled
    public Id defaultUserId;
    @AuraEnabled
    public List<PlannerViewerOption> options;
  }

  public class VisitSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String visitType;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public Decimal accountLatitude;
    @AuraEnabled
    public Decimal accountLongitude;
    @AuraEnabled
    public String accountSpecialty;
    @AuraEnabled
    public String accountRecordTypeName;
    @AuraEnabled
    public String accountRecordTypeDeveloperName;
    @AuraEnabled
    public String cancellationReason;
    @AuraEnabled
    public Id zetaProjectId;
    @AuraEnabled
    public String zetaProjectName;
    @AuraEnabled
    public String visitObjective;
  }

  public class VisitDetail {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String visitType;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public String durationLabel;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String accountRecordTypeName;
    @AuraEnabled
    public String accountRecordTypeDeveloperName;
    @AuraEnabled
    public String accountSpecialty;
    @AuraEnabled
    public String accountCity;
    @AuraEnabled
    public String accountStreet;
    @AuraEnabled
    public String assignedToName;
    @AuraEnabled
    public String visitObjective;
    @AuraEnabled
    public String visitNotes;
    @AuraEnabled
    public String productsDiscussed;
    @AuraEnabled
    public String productDetails;
    @AuraEnabled
    public String clmPresentation;
    @AuraEnabled
    public Date nextVisitDate;
    @AuraEnabled
    public String cancellationReason;
    @AuraEnabled
    public String planRejectionReason;
    @AuraEnabled
    public Boolean isLocked;
  }

  public class TotSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String typeLabel;
    @AuraEnabled
    public String typeValue;
    @AuraEnabled
    public String spanType;
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public Boolean isFullDay;
    @AuraEnabled
    public String comments;
  }

  public class MeetingSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public Id pharmaProjectId;
    @AuraEnabled
    public String pharmaProjectName;
  }

  public class PlannerPayload {
    @AuraEnabled
    public List<VisitSummary> visits;
    @AuraEnabled
    public List<TotSummary> timeOffBlocks;
    @AuraEnabled
    public List<MeetingSummary> meetings;
  }

  public class WeekSubmitResult {
    @AuraEnabled
    public Integer submittedCount;
    @AuraEnabled
    public Integer failedCount;
    @AuraEnabled
    public List<VisitSummary> visits;
    @AuraEnabled
    public List<String> errors;
  }

  public class AccountPageResult {
    @AuraEnabled
    public List<AccountSummary> accounts;
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public Integer totalCount;
  }

  public class RecordTypeOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public RecordTypeOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class ProductOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public ProductOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class ProjectOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public ProjectOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class VisitInput {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public String visitType;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String cancellationReason;
    @AuraEnabled
    public Id zetaProjectId;
    @AuraEnabled
    public String visitObjective;
  }

  public class TotInput {
    @AuraEnabled
    public String typeValue;
    @AuraEnabled
    public String spanType;
    @AuraEnabled
    public String durationHours;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public String comments;
    @AuraEnabled
    public String stage;
  }

  private static final Integer DEFAULT_ACCOUNT_PAGE_SIZE = 25;
  private static final Integer MAX_ACCOUNT_PAGE_SIZE = 50;
  private static final String RECORD_TYPE_ALL = 'All';
  private static final String FILTER_ALL = 'All';
  private static final Set<String> PLANNER_ACCOUNT_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Institution_HCO',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact',
    'Pharmacy'
  };
  private static final String HEAD_OFFICE_EXTERNAL_ID = 'TERR_HEAD_OFFICE';
  private static final Decimal PACE_ON_TRACK_THRESHOLD = 90;
  private static final Decimal PACE_CRITICAL_THRESHOLD = 50;
  private static final Set<String> PLANNED_VISIT_STATUSES = new Set<String>{
    VisitStatusHelper.STATUS_DRAFT,
    VisitStatusHelper.STATUS_SUBMITTED,
    VisitStatusHelper.STATUS_SCHEDULED,
    'Rescheduled'
  };

  private static Boolean plannerHasObject(String objectApiName) {
    return String.isNotBlank(objectApiName) &&
      Schema.getGlobalDescribe().containsKey(objectApiName.toLowerCase());
  }

  private static Boolean plannerHasField(Schema.SObjectType sobjectType, String fieldApiName) {
    if (sobjectType == null || String.isBlank(fieldApiName)) {
      return false;
    }
    Schema.SObjectField fieldToken = sobjectType.getDescribe().fields.getMap()
      .get(fieldApiName.toLowerCase());
    return fieldToken != null && fieldToken.getDescribe().isAccessible();
  }

  private static Boolean plannerHasVisitZetaProjectField() {
    return plannerHasField(Visit__c.SObjectType, 'Pharma_Project__c');
  }

  private static Visit__c queryPlannerVisitById(Id visitId) {
    Id userId = UserInfo.getUserId();
    List<Visit__c> visits = queryPlannerVisitsById(new Set<Id>{ visitId }, userId);
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    return visits[0];
  }

  private static List<Visit__c> queryPlannerVisitsById(Set<Id> visitIds, Id assignedToUserId) {
    if (visitIds == null || visitIds.isEmpty()) {
      return new List<Visit__c>();
    }
    if (plannerHasVisitZetaProjectField()) {
      if (assignedToUserId != null) {
        return [
          SELECT
            Id,
            Name,
            Status__c,
            Visit_Type__c,
            Start_Date__c,
            End_Date__c,
            Cancellation_Reason__c,
            Account__c,
            Account__r.Name,
            Account__r.BillingLatitude,
            Account__r.BillingLongitude,
            Account__r.Specialty_1__c,
            Account__r.RecordType.Name,
            Account__r.RecordType.DeveloperName,
            Visit_Objective__c,
            Pharma_Project__c,
            Pharma_Project__r.Name
          FROM Visit__c
          WHERE Id IN :visitIds AND Assigned_To__c = :assignedToUserId
          WITH SYSTEM_MODE
          ORDER BY Start_Date__c ASC
        ];
      }
      return [
        SELECT
          Id,
          Name,
          Status__c,
          Visit_Type__c,
          Start_Date__c,
          End_Date__c,
          Cancellation_Reason__c,
          Account__c,
          Account__r.Name,
          Account__r.BillingLatitude,
          Account__r.BillingLongitude,
          Account__r.Specialty_1__c,
          Account__r.RecordType.Name,
          Account__r.RecordType.DeveloperName,
          Visit_Objective__c,
          Pharma_Project__c,
          Pharma_Project__r.Name
        FROM Visit__c
        WHERE Id IN :visitIds
        WITH SYSTEM_MODE
        ORDER BY Start_Date__c ASC
      ];
    }
    if (assignedToUserId != null) {
      return [
        SELECT
          Id,
          Name,
          Status__c,
          Visit_Type__c,
          Start_Date__c,
          End_Date__c,
          Cancellation_Reason__c,
          Account__c,
          Account__r.Name,
          Account__r.BillingLatitude,
          Account__r.BillingLongitude,
          Account__r.Specialty_1__c,
          Account__r.RecordType.Name,
          Account__r.RecordType.DeveloperName,
          Visit_Objective__c
        FROM Visit__c
        WHERE Id IN :visitIds AND Assigned_To__c = :assignedToUserId
        WITH SYSTEM_MODE
        ORDER BY Start_Date__c ASC
      ];
    }
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Visit_Type__c,
        Start_Date__c,
        End_Date__c,
        Cancellation_Reason__c,
        Account__c,
        Account__r.Name,
        Account__r.BillingLatitude,
        Account__r.BillingLongitude,
        Account__r.Specialty_1__c,
        Account__r.RecordType.Name,
        Account__r.RecordType.DeveloperName,
        Visit_Objective__c
      FROM Visit__c
      WHERE Id IN :visitIds
      WITH SYSTEM_MODE
      ORDER BY Start_Date__c ASC
    ];
  }

  @AuraEnabled(cacheable=true)
  public static PlannerPayload getPlannerData(Date weekStart, Date weekEnd, Id contextUserId) {
    return buildPlannerPayload(weekStart, weekEnd, contextUserId);
  }

  @AuraEnabled
  public static PlannerPayload fetchPlannerData(Date weekStart, Date weekEnd, Id contextUserId) {
    return buildPlannerPayload(weekStart, weekEnd, contextUserId);
  }

  private static PlannerPayload buildPlannerPayload(Date weekStart, Date weekEnd, Id contextUserId) {
    if (weekStart == null || weekEnd == null) {
      throw new AuraHandledException('Week start and end dates are required.');
    }

    Id resolvedUserId = resolveContextUserId(contextUserId);
    DateTime rangeStart = DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

    PlannerPayload payload = new PlannerPayload();
    payload.visits = queryVisits(rangeStart, rangeEnd, resolvedUserId);
    try {
      payload.timeOffBlocks = queryTimeOff(rangeStart, rangeEnd, resolvedUserId);
    } catch (Exception timeOffError) {
      payload.timeOffBlocks = new List<TotSummary>();
    }
    // Meetings are optional for planner week load — never block visits/TOT if
    // Meeting__c FLS/object access is missing during the visits→meetings migration.
    try {
      payload.meetings = queryMeetings(rangeStart, rangeEnd, resolvedUserId);
    } catch (Exception meetingError) {
      payload.meetings = new List<MeetingSummary>();
    }
    return payload;
  }

  @AuraEnabled(cacheable=true)
  public static List<RecordTypeOption> getPlannerAccountRecordTypes() {
    List<RecordTypeOption> options = new List<RecordTypeOption>();
    options.add(new RecordTypeOption('All Record Types', RECORD_TYPE_ALL));
    for (RecordType recordType : [
      SELECT Name, DeveloperName
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
      WITH USER_MODE
      ORDER BY Name ASC
    ]) {
      options.add(new RecordTypeOption(recordType.Name, recordType.DeveloperName));
    }
    return options;
  }

  @AuraEnabled(cacheable=true)
  public static List<ProductOption> getPlannerProducts(Id contextUserId) {
    List<ProductOption> options = new List<ProductOption>();
    Set<Id> productIds = new Set<Id>();
    Id resolvedUserId = resolveContextUserId(contextUserId);
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIdsForUser(resolvedUserId));
    Set<String> territoryIdStrings = toTerritoryIdStrings(territoryIds);
    if (!territoryIdStrings.isEmpty()) {
      for (Product_Territory_Alignment__c alignment : [
        SELECT Product2_Id__c
        FROM Product_Territory_Alignment__c
        WHERE Territory2_Id__c IN :territoryIdStrings AND Product2_Id__c != NULL
        WITH USER_MODE
      ]) {
        try {
          productIds.add((Id) alignment.Product2_Id__c);
        } catch (Exception ex) {
          // Skip invalid product id values on alignment rows.
        }
      }
    }

    List<Product2> products;
    if (productIds.isEmpty()) {
      products = [
        SELECT Id, Name
        FROM Product2
        WHERE IsActive = TRUE
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT 50
      ];
    } else {
      products = [
        SELECT Id, Name
        FROM Product2
        WHERE Id IN :productIds AND IsActive = TRUE
        WITH USER_MODE
        ORDER BY Name ASC
      ];
    }

    for (Product2 product : products) {
      options.add(new ProductOption(product.Name, product.Name));
    }
    return options;
  }

  @AuraEnabled(cacheable=true)
  public static AccountPageResult searchAccountsPage(
    String searchTerm,
    String recordTypeDeveloperName,
    String specialty,
    String classification,
    Id brickId,
    Integer offset,
    Integer pageSize,
    Id contextUserId
  ) {
    return queryAccountsPage(
      searchTerm,
      recordTypeDeveloperName,
      specialty,
      classification,
      brickId,
      offset,
      pageSize,
      contextUserId
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<AccountSummary> getMapAccounts(Id contextUserId) {
    return queryMapAccounts(contextUserId);
  }

  @AuraEnabled(cacheable=true)
  public static PlannerFilterOptions getPlannerAccountFilterOptions(Id contextUserId) {
    Id resolvedUserId = resolveContextUserId(contextUserId);
    PlannerFilterOptions result = new PlannerFilterOptions();
    result.specialtyOptions = new List<FilterOption>{
      new FilterOption('All Specialties', FILTER_ALL)
    };
    result.classificationOptions = new List<FilterOption>{
      new FilterOption('All Classifications', FILTER_ALL)
    };
    result.brickOptions = new List<FilterOption>{
      new FilterOption('All Bricks', FILTER_ALL)
    };

    Set<Id> accountIds = resolveScopedAccountIds(resolvedUserId);
    if (accountIds != null && accountIds.isEmpty()) {
      return result;
    }

    Set<String> specialties = new Set<String>();
    if (accountIds == null) {
      for (AggregateResult agg : [
        SELECT Specialty_1__c specialty
        FROM Account
        WHERE
          RecordType.DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
          AND Specialty_1__c != NULL
        WITH USER_MODE
        GROUP BY Specialty_1__c
        ORDER BY Specialty_1__c ASC
      ]) {
        specialties.add((String) agg.get('specialty'));
      }
    } else {
      for (AggregateResult agg : [
        SELECT Specialty_1__c specialty
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
          AND Specialty_1__c != NULL
        WITH USER_MODE
        GROUP BY Specialty_1__c
        ORDER BY Specialty_1__c ASC
      ]) {
        specialties.add((String) agg.get('specialty'));
      }
    }
    for (String spec : specialties) {
      result.specialtyOptions.add(
        new FilterOption(MedicalSpecialtyPicklist.getLabel(spec), spec)
      );
    }

    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIdsForUser(resolvedUserId));
    Set<String> territoryIdStrings = toTerritoryIdStrings(territoryIds);
    if (!territoryIdStrings.isEmpty()) {
      Set<String> classifications = new Set<String>();
      if (accountIds == null) {
        for (AggregateResult agg : [
          SELECT Classification__c classVal
          FROM Account_Territory_Fields__c
          WHERE
            Territory2_Id__c IN :territoryIdStrings
            AND Is_Active__c = TRUE
            AND Classification__c != NULL
          WITH SYSTEM_MODE
          GROUP BY Classification__c
          ORDER BY Classification__c ASC
        ]) {
          classifications.add((String) agg.get('classVal'));
        }
        for (AggregateResult agg : [
          SELECT HCP_Classification__c classVal
          FROM Account_Territory_Fields__c
          WHERE
            Territory2_Id__c IN :territoryIdStrings
            AND Is_Active__c = TRUE
            AND Classification__c = NULL
            AND HCP_Classification__c != NULL
          WITH SYSTEM_MODE
          GROUP BY HCP_Classification__c
          ORDER BY HCP_Classification__c ASC
        ]) {
          classifications.add((String) agg.get('classVal'));
        }
      } else {
        for (AggregateResult agg : [
          SELECT Classification__c classVal
          FROM Account_Territory_Fields__c
          WHERE
            Territory2_Id__c IN :territoryIdStrings
            AND Is_Active__c = TRUE
            AND Classification__c != NULL
            AND Account__c IN :accountIds
          WITH SYSTEM_MODE
          GROUP BY Classification__c
          ORDER BY Classification__c ASC
        ]) {
          classifications.add((String) agg.get('classVal'));
        }
        for (AggregateResult agg : [
          SELECT HCP_Classification__c classVal
          FROM Account_Territory_Fields__c
          WHERE
            Territory2_Id__c IN :territoryIdStrings
            AND Is_Active__c = TRUE
            AND Classification__c = NULL
            AND HCP_Classification__c != NULL
            AND Account__c IN :accountIds
          WITH SYSTEM_MODE
          GROUP BY HCP_Classification__c
          ORDER BY HCP_Classification__c ASC
        ]) {
          classifications.add((String) agg.get('classVal'));
        }
      }
      for (String classVal : classifications) {
        result.classificationOptions.add(new FilterOption(classVal, classVal));
      }
    }

    Set<Id> brickIds = new Set<Id>();
    if (accountIds == null) {
      for (AggregateResult agg : [
        SELECT Brick__c brickId
        FROM Account
        WHERE
          RecordType.DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
          AND Brick__c != NULL
        WITH USER_MODE
        GROUP BY Brick__c
        ORDER BY Brick__c ASC
      ]) {
        brickIds.add((Id) agg.get('brickId'));
      }
    } else if (!accountIds.isEmpty()) {
      for (AggregateResult agg : [
        SELECT Brick__c brickId
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
          AND Brick__c != NULL
        WITH USER_MODE
        GROUP BY Brick__c
        ORDER BY Brick__c ASC
      ]) {
        brickIds.add((Id) agg.get('brickId'));
      }
    }
    if (!brickIds.isEmpty()) {
      for (Brick__c brick : [
        SELECT Id, Name
        FROM Brick__c
        WHERE Id IN :brickIds
        WITH USER_MODE
        ORDER BY Name ASC
      ]) {
        result.brickOptions.add(new FilterOption(brick.Name, brick.Id));
      }
    }
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<ProjectOption> getPromotionalProjects(Id contextUserId) {
    List<ProjectOption> options = new List<ProjectOption>();
    if (!plannerHasObject('Pharma_Project__c')) {
      return options;
    }

    try {
      Id resolvedUserId = resolveContextUserId(contextUserId);
      Set<Id> memberProjectIds = new Set<Id>();
      if (
        plannerHasObject('Pharma_Project_Member__c') &&
        plannerHasField(Pharma_Project_Member__c.SObjectType, 'User__c') &&
        plannerHasField(Pharma_Project_Member__c.SObjectType, 'Pharma_Project__c')
      ) {
        for (Pharma_Project_Member__c member : [
          SELECT Pharma_Project__c
          FROM Pharma_Project_Member__c
          WHERE User__c = :resolvedUserId AND Pharma_Project__c != NULL
          WITH USER_MODE
        ]) {
          memberProjectIds.add(member.Pharma_Project__c);
        }
      }

      String promoCampaignType = 'Promotional Events';
      List<Pharma_Project__c> projects;
      if (!memberProjectIds.isEmpty()) {
        projects = [
          SELECT Id, Name
          FROM Pharma_Project__c
          WHERE
            Campaign_Type__c = :promoCampaignType
            AND Status__c IN ('Planning', 'In Progress')
            AND (Id IN :memberProjectIds OR Project_Lead__c = :resolvedUserId)
          WITH USER_MODE
          ORDER BY Name ASC
          LIMIT 50
        ];
      } else {
        projects = [
          SELECT Id, Name
          FROM Pharma_Project__c
          WHERE
            Campaign_Type__c = :promoCampaignType
            AND Status__c IN ('Planning', 'In Progress')
            AND Project_Lead__c = :resolvedUserId
          WITH USER_MODE
          ORDER BY Name ASC
          LIMIT 50
        ];
      }
      for (Pharma_Project__c project : projects) {
        options.add(new ProjectOption(project.Name, project.Id));
      }
    } catch (Exception projectError) {
      // Org schema variance (member/project fields) should not break planner.
      return new List<ProjectOption>();
    }
    return options;
  }

  @AuraEnabled(cacheable=true)
  public static List<AccountVisitTarget> getAccountVisitTargets(Id contextUserId) {
    Id resolvedUserId = resolveContextUserId(contextUserId);
    List<AccountVisitTarget> results = new List<AccountVisitTarget>();
    Date monthStart = Date.today().toStartOfMonth();

    List<Employee_Time_Card__c> cards = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE
        Employee__c = :resolvedUserId
        AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    if (cards.isEmpty()) {
      return results;
    }

    for (Employee_Time_Card_Account_Target__c target : [
      SELECT
        Account__c,
        Account__r.Name,
        Account__r.BillingLatitude,
        Account__r.BillingLongitude,
        Target_Visit_Frequency__c,
        Actual_Visits__c,
        Frequency_Status__c,
        Potentiality__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE
        Employee_Time_Card__c = :cards[0].Id
        AND Frequency_Status__c = 'LCF'
        AND Account__r.BillingLatitude != NULL
        AND Account__r.BillingLongitude != NULL
      WITH USER_MODE
      ORDER BY Potentiality__c ASC
      LIMIT 200
    ]) {
      AccountVisitTarget row = new AccountVisitTarget();
      row.accountId = target.Account__c;
      row.accountName = target.Account__r.Name;
      row.latitude = target.Account__r.BillingLatitude;
      row.longitude = target.Account__r.BillingLongitude;
      row.targetVisitFrequency = target.Target_Visit_Frequency__c;
      row.actualVisits = target.Actual_Visits__c;
      row.visitGap = target.Target_Visit_Frequency__c - target.Actual_Visits__c;
      row.frequencyStatus = target.Frequency_Status__c;
      row.potentiality = target.Potentiality__c;
      results.add(row);
    }
    return results;
  }

  @AuraEnabled(cacheable=true)
  public static PlannerViewerContext getPlannerViewerContext() {
    PlannerViewerContext ctx = new PlannerViewerContext();
    ctx.defaultUserId = UserInfo.getUserId();
    ctx.viewerMode = 'self';
    ctx.canSwitchView = false;
    ctx.options = new List<PlannerViewerOption>();

    Id headOfficeId = getHeadOfficeTerritoryId();
    if (headOfficeId != null) {
      List<Territory2> headOffice = [
        SELECT Id, Name
        FROM Territory2
        WHERE Id = :headOfficeId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!headOffice.isEmpty()) {
        ctx.topTerritoryId = headOffice[0].Id;
        ctx.topTerritoryName = headOffice[0].Name;
      }
    }

    if (hasFullPlannerAccountAccess()) {
      ctx.viewerMode = 'admin';
      ctx.canSwitchView = true;
      ctx.options = buildViewerOptionsForTerritories(
        headOfficeId != null
          ? expandTerritoryHierarchy(new Set<Id>{ headOfficeId })
          : new Set<Id>()
      );
    }
    return ctx;
  }

  public static Id resolveViewerContextUserId(Id requestedUserId) {
    return resolveContextUserId(requestedUserId);
  }

  @AuraEnabled
  public static VisitSummary upsertVisit(
    Id visitId,
    Id accountId,
    DateTime startDateTime,
    DateTime endDateTime,
    String status,
    String visitType,
    String cancellationReason,
    Id zetaProjectId,
    String visitObjective
  ) {
    assertCanMutatePlanner();
    VisitInput input = new VisitInput();
    input.id = visitId;
    input.accountId = accountId;
    input.startDateTime = startDateTime;
    input.endDateTime = endDateTime;
    input.status = status;
    input.visitType = visitType;
    input.cancellationReason = cancellationReason;
    input.zetaProjectId = zetaProjectId;
    input.visitObjective = visitObjective;
    return upsertVisitInternal(input);
  }

  @AuraEnabled
  public static List<VisitSummary> rescheduleVisits(
    List<Id> visitIds,
    List<DateTime> startDateTimes,
    List<DateTime> endDateTimes
  ) {
    assertCanMutatePlanner();
    if (visitIds == null || startDateTimes == null || endDateTimes == null) {
      throw new AuraHandledException('Visit schedule details are required.');
    }
    if (
      visitIds.isEmpty() ||
      visitIds.size() != startDateTimes.size() ||
      visitIds.size() != endDateTimes.size()
    ) {
      throw new AuraHandledException('Visit schedule lists must match in length.');
    }

    Map<Id, Visit__c> visitsById = new Map<Id, Visit__c>(
      [
        SELECT Id, Status__c, Visit_Type__c, Account__c, Assigned_To__c, Start_Date__c, End_Date__c
        FROM Visit__c
        WHERE Id IN :visitIds AND Assigned_To__c = :UserInfo.getUserId()
        WITH USER_MODE
      ]
    );

    if (visitsById.size() != visitIds.size()) {
      throw new AuraHandledException('One or more visits could not be rescheduled.');
    }

    List<Visit__c> updates = new List<Visit__c>();
    for (Integer i = 0; i < visitIds.size(); i++) {
      Visit__c visit = visitsById.get(visitIds[i]);
      if (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') {
        throw new AuraHandledException('Completed or cancelled visits cannot be rescheduled.');
      }
      if (VisitStatusHelper.isPendingApproval(visit.Status__c)) {
        throw new AuraHandledException('Visits pending approval cannot be rescheduled.');
      }
      DateTime startDt = startDateTimes[i];
      DateTime endDt = endDateTimes[i];
      if (startDt == null || endDt == null || endDt <= startDt) {
        throw new AuraHandledException('Each visit needs a valid start and end time.');
      }
      VisitConflictService.assertNoConflicts(
        visit.Assigned_To__c,
        startDt,
        endDt,
        visit.Id
      );
      Boolean replan =
        VisitStatusHelper.isPlannedVisitType(visit.Visit_Type__c) &&
        visit.Status__c == VisitStatusHelper.STATUS_SCHEDULED &&
        (visit.Start_Date__c != startDt || visit.End_Date__c != endDt);
      if (replan) {
        visit.Status__c = VisitStatusHelper.STATUS_SUBMITTED;
        visit.Submitted_At__c = System.now();
      }
      visit.Start_Date__c = startDt;
      visit.End_Date__c = endDt;
      visit.Visit_Date__c = startDt;
      updates.add(visit);
    }

    update as user updates;

    for (Visit__c visit : updates) {
      if (visit.Status__c == VisitStatusHelper.STATUS_SUBMITTED) {
        try {
          submitForApprovalInternal(visit.Id);
        } catch (Exception ex) {
          throw new AuraHandledException(
            'Visit was replanned but could not be submitted for approval: ' + ex.getMessage()
          );
        }
      }
    }

    List<VisitSummary> results = new List<VisitSummary>();
    for (Visit__c visit : queryPlannerVisitsById(new Set<Id>(visitIds), null)) {
      results.add(mapVisit(visit));
    }
    return results;
  }

  private static void submitForApprovalInternal(Id visitId) {
    Approval.ProcessSubmitRequest approvalRequest = new Approval.ProcessSubmitRequest();
    approvalRequest.setComments('Visit plan submitted.');
    approvalRequest.setObjectId(visitId);
    Approval.process(approvalRequest);
  }

  @AuraEnabled
  public static VisitSummary submitVisit(Id visitId) {
    assertCanMutatePlanner();
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    Visit__c visit = [
      SELECT
        Id,
        Status__c,
        Visit_Type__c,
        Assigned_To__c,
        Start_Date__c,
        End_Date__c
      FROM Visit__c
      WHERE Id = :visitId AND Assigned_To__c = :UserInfo.getUserId()
      WITH USER_MODE
      LIMIT 1
    ];
    if (!VisitStatusHelper.isPlannedVisitType(visit.Visit_Type__c)) {
      throw new AuraHandledException('Only planned visits can be submitted for approval.');
    }
    VisitStatusHelper.assertTransitionAllowed(
      visit.Status__c,
      VisitStatusHelper.STATUS_SUBMITTED,
      visit.Visit_Type__c,
      false
    );
    VisitConflictService.assertNoConflicts(
      visit.Assigned_To__c,
      visit.Start_Date__c,
      visit.End_Date__c,
      visit.Id
    );
    visit.Status__c = VisitStatusHelper.STATUS_SUBMITTED;
    visit.Submitted_At__c = System.now();
    update as user visit;

    try {
      submitForApprovalInternal(visit.Id);
    } catch (Exception ex) {
      visit.Status__c = VisitStatusHelper.STATUS_DRAFT;
      visit.Submitted_At__c = null;
      update as user visit;
      throw new AuraHandledException('Unable to submit visit for approval: ' + ex.getMessage());
    }

    return mapVisit(queryPlannerVisitById(visit.Id));
  }

  @AuraEnabled
  public static WeekSubmitResult submitWeekPlans(Date weekStart, Date weekEnd) {
    assertCanMutatePlanner();
    if (weekStart == null || weekEnd == null) {
      throw new AuraHandledException('Week start and end dates are required.');
    }

    DateTime rangeStart = DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
    Id userId = UserInfo.getUserId();
    List<Visit__c> drafts = [
      SELECT Id
      FROM Visit__c
      WHERE
        Assigned_To__c = :userId
        AND Status__c = :VisitStatusHelper.STATUS_DRAFT
        AND Visit_Type__c IN (
          :VisitStatusHelper.TYPE_PLANNED_AUTO,
          :VisitStatusHelper.TYPE_PLANNED_MANAGER
        )
        AND Start_Date__c >= :rangeStart
        AND Start_Date__c < :rangeEnd
      WITH USER_MODE
      ORDER BY Start_Date__c ASC
    ];

    WeekSubmitResult result = new WeekSubmitResult();
    result.submittedCount = 0;
    result.failedCount = 0;
    result.visits = new List<VisitSummary>();
    result.errors = new List<String>();
    for (Visit__c draft : drafts) {
      try {
        result.visits.add(submitVisit(draft.Id));
        result.submittedCount++;
      } catch (Exception ex) {
        result.failedCount++;
        result.errors.add(ex.getMessage());
      }
    }
    return result;
  }

  @AuraEnabled
  public static VisitSummary approvePlanVisit(Id visitId) {
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    Visit__c visit = [
      SELECT Id, Status__c, Visit_Type__c, Assigned_To__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visit.Status__c != VisitStatusHelper.STATUS_SUBMITTED) {
      throw new AuraHandledException('Only submitted visits can be approved.');
    }
    VisitStatusHelper.assertTransitionAllowed(
      visit.Status__c,
      VisitStatusHelper.STATUS_SCHEDULED,
      visit.Visit_Type__c,
      true
    );
    visit.Status__c = VisitStatusHelper.STATUS_SCHEDULED;
    update as user visit;
    return mapVisit(queryPlannerVisitById(visit.Id));
  }

  private static VisitSummary upsertVisitInternal(VisitInput input) {
    if (input == null) {
      throw new AuraHandledException('Visit details are required.');
    }
    if (input.accountId == null && input.id == null && input.zetaProjectId == null) {
      throw new AuraHandledException('Select an account for the visit.');
    }
    if (input.startDateTime == null || input.endDateTime == null) {
      throw new AuraHandledException('Start and end times are required.');
    }
    if (input.endDateTime <= input.startDateTime) {
      throw new AuraHandledException('End time must be after start time.');
    }

    Visit__c visit;
    String priorStatus;
    String visitType;
    Id assignedTo;
    DateTime priorStart;
    DateTime priorEnd;
    if (input.id != null) {
      visit = [
        SELECT Id, Status__c, Visit_Type__c, Assigned_To__c, Start_Date__c, End_Date__c
        FROM Visit__c
        WHERE Id = :input.id
        WITH USER_MODE
        LIMIT 1
      ];
      priorStatus = visit.Status__c;
      visitType = visit.Visit_Type__c;
      assignedTo = visit.Assigned_To__c;
      priorStart = visit.Start_Date__c;
      priorEnd = visit.End_Date__c;
      if (VisitStatusHelper.isLockedStatus(visit.Status__c)) {
        throw new AuraHandledException('Completed or cancelled visits cannot be changed from the planner.');
      }
      if (VisitStatusHelper.isPendingApproval(visit.Status__c)) {
        throw new AuraHandledException('Visits pending approval cannot be edited. Recall or wait for manager action.');
      }
    } else {
      visit = new Visit__c();
      visit.Assigned_To__c = UserInfo.getUserId();
      assignedTo = visit.Assigned_To__c;
      visitType = String.isBlank(input.visitType)
        ? VisitStatusHelper.TYPE_PLANNED_AUTO
        : input.visitType;
      visit.Visit_Type__c = visitType;
      if (VisitStatusHelper.isUnplannedVisitType(visitType)) {
        visit.Status__c = VisitStatusHelper.STATUS_SCHEDULED;
      } else {
        visit.Status__c = String.isBlank(input.status) ? VisitStatusHelper.STATUS_DRAFT : input.status;
      }
      priorStatus = null;
    }

    String targetStatus = String.isBlank(input.status) ? visit.Status__c : input.status;
    if (input.id != null && String.isNotBlank(input.status)) {
      targetStatus = input.status;
    }

    Boolean replan =
      input.id != null &&
      VisitStatusHelper.isPlannedVisitType(visitType) &&
      priorStatus == VisitStatusHelper.STATUS_SCHEDULED &&
      (priorStart != input.startDateTime || priorEnd != input.endDateTime);
    if (replan) {
      targetStatus = VisitStatusHelper.STATUS_SUBMITTED;
    }

    VisitStatusHelper.assertTransitionAllowed(priorStatus, targetStatus, visitType, false);
    VisitStatusHelper.validateStatusChange(targetStatus, input.startDateTime, input.cancellationReason);
    VisitConflictService.assertNoConflicts(
      assignedTo,
      input.startDateTime,
      input.endDateTime,
      input.id
    );

    visit.Status__c = targetStatus;
    if (targetStatus == VisitStatusHelper.STATUS_SUBMITTED && priorStatus != VisitStatusHelper.STATUS_SUBMITTED) {
      visit.Submitted_At__c = System.now();
    }
    if (input.accountId != null) {
      visit.Account__c = input.accountId;
    }
    if (input.zetaProjectId != null && plannerHasVisitZetaProjectField()) {
      visit.put('Pharma_Project__c', input.zetaProjectId);
    }
    if (String.isNotBlank(input.visitObjective)) {
      visit.Visit_Objective__c = input.visitObjective;
    }
    visit.Start_Date__c = input.startDateTime;
    visit.End_Date__c = input.endDateTime;
    visit.Visit_Date__c = input.startDateTime;
    visit.Cancellation_Reason__c = 'Cancelled' == input.status ? input.cancellationReason : null;

    if (input.id != null) {
      update as user visit;
    } else {
      insert as user visit;
    }

    return mapVisit(queryPlannerVisitById(visit.Id));
  }

  @AuraEnabled
  public static void deleteVisit(Id visitId) {
    assertCanMutatePlanner();
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    Visit__c visit = [
      SELECT Id, Status__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visit.Status__c == 'Completed') {
      throw new AuraHandledException('Completed visits cannot be deleted from the planner.');
    }
    delete as user visit;
  }

  @AuraEnabled(cacheable=true)
  public static VisitDetail getVisitDetail(Id visitId) {
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    List<Visit__c> visits = [
      SELECT
        Id,
        Name,
        Status__c,
        Visit_Type__c,
        Start_Date__c,
        End_Date__c,
        Visit_Objective__c,
        Visit_Notes__c,
        Products_Discussed__c,
        Product_Details__c,
        CLM_Presentation__c,
        Next_Visit_Date__c,
        Cancellation_Reason__c,
        Plan_Rejection_Reason__c,
        Account__c,
        Account__r.Name,
        Account__r.BillingCity,
        Account__r.BillingStreet,
        Account__r.Specialty_1__c,
        Account__r.RecordType.Name,
        Account__r.RecordType.DeveloperName,
        Assigned_To__r.Name
      FROM Visit__c
      WHERE Id = :visitId AND Assigned_To__c = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    return mapVisitDetail(visits[0]);
  }

  @AuraEnabled
  public static VisitDetail saveVisitWorkspace(
    Id visitId,
    String status,
    String visitObjective,
    String visitNotes,
    String productsDiscussed,
    String productDetails,
    String clmPresentation,
    Date nextVisitDate,
    String cancellationReason
  ) {
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    Visit__c visit = [
      SELECT Id, Status__c, Start_Date__c, Visit_Type__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (VisitStatusHelper.isLockedStatus(visit.Status__c)) {
      throw new AuraHandledException('Completed or cancelled visits cannot be edited.');
    }
    if (VisitStatusHelper.isPendingApproval(visit.Status__c)) {
      throw new AuraHandledException('Visits pending approval cannot be edited.');
    }
    VisitStatusHelper.assertTransitionAllowed(
      visit.Status__c,
      status,
      visit.Visit_Type__c,
      false
    );
    VisitStatusHelper.validateStatusChange(status, visit.Start_Date__c, cancellationReason);

    visit.Status__c = status;
    visit.Visit_Objective__c = visitObjective;
    visit.Visit_Notes__c = visitNotes;
    visit.Products_Discussed__c = productsDiscussed;
    visit.Product_Details__c = productDetails;
    visit.CLM_Presentation__c = clmPresentation;
    visit.Next_Visit_Date__c = nextVisitDate;
    visit.Cancellation_Reason__c = 'Cancelled' == status ? cancellationReason : null;
    update as user visit;

    return getVisitDetail(visitId);
  }

  @AuraEnabled
  public static TotSummary createTimeOff(
    String typeValue,
    String spanType,
    String durationHours,
    DateTime startDateTime,
    String comments,
    String stage
  ) {
    assertCanMutatePlanner();
    TotInput input = new TotInput();
    input.typeValue = typeValue;
    input.spanType = spanType;
    input.durationHours = durationHours;
    input.startDateTime = startDateTime;
    input.comments = comments;
    input.stage = stage;
    return createTimeOffInternal(input);
  }

  private static TotSummary createTimeOffInternal(TotInput input) {
    if (input == null) {
      throw new AuraHandledException('Time off details are required.');
    }
    if (String.isBlank(input.typeValue)) {
      throw new AuraHandledException('Select a time off type.');
    }
    if (String.isBlank(input.spanType)) {
      throw new AuraHandledException('Select full day or partial hours.');
    }
    if (input.startDateTime == null) {
      throw new AuraHandledException('Start date/time is required.');
    }

    Time_Off_Request__c request = new Time_Off_Request__c();
    request.Type__c = input.typeValue;
    request.Span_Type__c = input.spanType;
    request.Start_Date_Time__c = input.startDateTime;
    request.Comments__c = input.comments;
    String targetStage = String.isBlank(input.stage) ? 'Draft' : input.stage;

    if (input.spanType == 'Hours') {
      if (String.isBlank(input.durationHours)) {
        throw new AuraHandledException('Select duration for partial time off.');
      }
      request.Span_Duration_Select__c = input.durationHours;
      Decimal hours = Decimal.valueOf(input.durationHours);
      request.Span_Duration__c = hours;
      request.End_Date_Time__c = input.startDateTime.addSeconds(Integer.valueOf(hours * 3600));
    } else if (input.spanType == 'Full_Day') {
      Date day = input.startDateTime.date();
      request.Start_Date_Time__c = DateTime.newInstance(day, Time.newInstance(9, 0, 0, 0));
      request.End_Date_Time__c = DateTime.newInstance(day, Time.newInstance(17, 0, 0, 0));
      request.Span_Duration__c = 1;
    }

    request.Stage__c = targetStage;
    try {
      insert as user request;
    } catch (DmlException e) {
      throw new AuraHandledException(e.getDmlMessage(0));
    }

    return mapTimeOff([
      SELECT
        Id,
        Name,
        Type__c,
        Span_Type__c,
        Stage__c,
        Comments__c,
        Start_Date_Time__c,
        End_Date_Time__c
      FROM Time_Off_Request__c
      WHERE Id = :request.Id
      WITH USER_MODE
      LIMIT 1
    ]);
  }

  private static List<VisitSummary> queryVisits(DateTime rangeStart, DateTime rangeEnd, Id userId) {
    List<VisitSummary> results = new List<VisitSummary>();
    List<Visit__c> visits;
    if (plannerHasVisitZetaProjectField()) {
      visits = [
        SELECT
          Id,
          Name,
          Status__c,
          Visit_Type__c,
          Start_Date__c,
          End_Date__c,
          Cancellation_Reason__c,
          Account__c,
          Account__r.Name,
          Account__r.BillingLatitude,
          Account__r.BillingLongitude,
          Account__r.Specialty_1__c,
          Account__r.RecordType.Name,
          Account__r.RecordType.DeveloperName,
          Visit_Objective__c,
          Pharma_Project__c,
          Pharma_Project__r.Name
        FROM Visit__c
        WHERE
          Assigned_To__c = :userId
          AND Start_Date__c < :rangeEnd
          AND End_Date__c > :rangeStart
          AND Status__c IN (
            'Draft',
            'Submitted',
            'Scheduled',
            'Rescheduled',
            'Completed',
            'Cancelled'
          )
        WITH SYSTEM_MODE
        ORDER BY Start_Date__c ASC
      ];
    } else {
      visits = [
        SELECT
          Id,
          Name,
          Status__c,
          Visit_Type__c,
          Start_Date__c,
          End_Date__c,
          Cancellation_Reason__c,
          Account__c,
          Account__r.Name,
          Account__r.BillingLatitude,
          Account__r.BillingLongitude,
          Account__r.Specialty_1__c,
          Account__r.RecordType.Name,
          Account__r.RecordType.DeveloperName,
          Visit_Objective__c
        FROM Visit__c
        WHERE
          Assigned_To__c = :userId
          AND Start_Date__c < :rangeEnd
          AND End_Date__c > :rangeStart
          AND Status__c IN (
            'Draft',
            'Submitted',
            'Scheduled',
            'Rescheduled',
            'Completed',
            'Cancelled'
          )
        WITH SYSTEM_MODE
        ORDER BY Start_Date__c ASC
      ];
    }
    for (Visit__c visit : visits) {
      results.add(mapVisit(visit));
    }
    return results;
  }

  private static List<TotSummary> queryTimeOff(DateTime rangeStart, DateTime rangeEnd, Id userId) {
    List<TotSummary> results = new List<TotSummary>();
    for (Time_Off_Request__c request : [
      SELECT
        Id,
        Name,
        Type__c,
        Span_Type__c,
        Stage__c,
        Comments__c,
        Start_Date_Time__c,
        End_Date_Time__c
      FROM Time_Off_Request__c
      WHERE
        (CreatedById = :userId OR OwnerId = :userId)
        AND Stage__c IN ('Draft', 'Submitted for Approval', 'Approved')
        AND Start_Date_Time__c < :rangeEnd
        AND End_Date_Time__c > :rangeStart
      WITH USER_MODE
      ORDER BY Start_Date_Time__c ASC
    ]) {
      results.add(mapTimeOff(request));
    }
    return results;
  }

  private static List<MeetingSummary> queryMeetings(DateTime rangeStart, DateTime rangeEnd, Id userId) {
    List<MeetingSummary> results = new List<MeetingSummary>();
    for (Meeting__c meeting : [
      SELECT
        Id,
        Name,
        Status__c,
        Objectives__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Pharma_Project__c,
        Pharma_Project__r.Name,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE
        OwnerId = :userId
        AND Start_Date_Time__c < :rangeEnd
        AND End_Date_Time__c > :rangeStart
        AND Status__c NOT IN ('Cancelled')
      WITH USER_MODE
      ORDER BY Start_Date_Time__c ASC
    ]) {
      results.add(mapMeeting(meeting));
    }
    return results;
  }

  private static AccountPageResult queryAccountsPage(
    String searchTerm,
    String recordTypeDeveloperName,
    String specialty,
    String classification,
    Id brickId,
    Integer offset,
    Integer pageSize,
    Id contextUserId
  ) {
    Integer lim = pageSize == null ? DEFAULT_ACCOUNT_PAGE_SIZE : Math.min(pageSize, MAX_ACCOUNT_PAGE_SIZE);
    Integer rowOffset = offset == null || offset < 0 ? 0 : offset;
    String likePattern = String.isBlank(searchTerm)
      ? null
      : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
    Set<String> recordTypes = resolveRecordTypeFilter(recordTypeDeveloperName);
    Id resolvedUserId = resolveContextUserId(contextUserId);
    Set<Id> accountIds = resolveScopedAccountIds(resolvedUserId);
    accountIds = applyClassificationFilter(accountIds, classification, resolvedUserId);
    accountIds = applyBrickFilter(accountIds, brickId);

    AccountPageResult page = new AccountPageResult();
    page.accounts = new List<AccountSummary>();
    page.totalCount = 0;
    page.hasMore = false;

    if (accountIds != null && accountIds.isEmpty()) {
      return page;
    }

    page.totalCount = countPlannerAccounts(
      likePattern,
      recordTypes,
      accountIds,
      specialty
    );
    page.accounts = attachVisitMetricsToSummaries(
      attachBrickToSummaries(
        attachClassificationToSummaries(
          mapAccountSummaries(
            queryPlannerAccounts(likePattern, recordTypes, accountIds, specialty, lim, rowOffset)
          ),
          resolvedUserId
        )
      ),
      resolvedUserId
    );
    page.hasMore = rowOffset + page.accounts.size() < page.totalCount;
    return page;
  }

  private static List<AccountSummary> queryMapAccounts(Id contextUserId) {
    Set<String> recordTypes = PLANNER_ACCOUNT_RECORD_TYPES;
    Id resolvedUserId = resolveContextUserId(contextUserId);
    Set<Id> accountIds = resolveScopedAccountIds(resolvedUserId);
    List<Account> accounts;
    if (accountIds == null) {
      accounts = [
        SELECT
          Id,
          Name,
          Specialty_1__c,
          BillingCity,
          BillingStreet,
          BillingLatitude,
          BillingLongitude,
          RecordType.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE
          RecordType.DeveloperName IN :recordTypes
          AND BillingLatitude != NULL
          AND BillingLongitude != NULL
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT 2000
      ];
    } else {
      if (accountIds.isEmpty()) {
        return new List<AccountSummary>();
      }
      accounts = [
        SELECT
          Id,
          Name,
          Specialty_1__c,
          BillingCity,
          BillingStreet,
          BillingLatitude,
          BillingLongitude,
          RecordType.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :recordTypes
          AND BillingLatitude != NULL
          AND BillingLongitude != NULL
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT 2000
      ];
    }
    return attachVisitMetricsToSummaries(
      attachBrickToSummaries(
        attachClassificationToSummaries(mapAccountSummaries(accounts), resolvedUserId)
      ),
      resolvedUserId
    );
  }

  @TestVisible
  private static Set<String> resolveRecordTypeFilter(String recordTypeDeveloperName) {
    if (String.isBlank(recordTypeDeveloperName) || RECORD_TYPE_ALL.equals(recordTypeDeveloperName)) {
      return PLANNER_ACCOUNT_RECORD_TYPES;
    }
    if (PLANNER_ACCOUNT_RECORD_TYPES.contains(recordTypeDeveloperName)) {
      return new Set<String>{ recordTypeDeveloperName };
    }
    return PLANNER_ACCOUNT_RECORD_TYPES;
  }

  private static Integer countPlannerAccounts(
    String likePattern,
    Set<String> recordTypes,
    Set<Id> accountIds,
    String specialty
  ) {
    String specialtyFilter = resolveSpecialtyFilter(specialty);
    if (accountIds == null) {
      if (likePattern == null && specialtyFilter == null) {
        return [
          SELECT COUNT()
          FROM Account
          WHERE RecordType.DeveloperName IN :recordTypes
          WITH USER_MODE
        ];
      }
      if (likePattern == null) {
        return [
          SELECT COUNT()
          FROM Account
          WHERE RecordType.DeveloperName IN :recordTypes AND Specialty_1__c = :specialtyFilter
          WITH USER_MODE
        ];
      }
      if (specialtyFilter == null) {
        return [
          SELECT COUNT()
          FROM Account
          WHERE
            RecordType.DeveloperName IN :recordTypes
            AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
          WITH USER_MODE
        ];
      }
      return [
        SELECT COUNT()
        FROM Account
        WHERE
          RecordType.DeveloperName IN :recordTypes
          AND Specialty_1__c = :specialtyFilter
          AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
        WITH USER_MODE
      ];
    }

    if (accountIds.isEmpty()) {
      return 0;
    }
    if (likePattern == null && specialtyFilter == null) {
      return [
        SELECT COUNT()
        FROM Account
        WHERE Id IN :accountIds AND RecordType.DeveloperName IN :recordTypes
        WITH USER_MODE
      ];
    }
    if (likePattern == null) {
      return [
        SELECT COUNT()
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :recordTypes
          AND Specialty_1__c = :specialtyFilter
        WITH USER_MODE
      ];
    }
    if (specialtyFilter == null) {
      return [
        SELECT COUNT()
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :recordTypes
          AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
        WITH USER_MODE
      ];
    }
    return [
      SELECT COUNT()
      FROM Account
      WHERE
        Id IN :accountIds
        AND RecordType.DeveloperName IN :recordTypes
        AND Specialty_1__c = :specialtyFilter
        AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
      WITH USER_MODE
    ];
  }

  private static List<Account> queryPlannerAccounts(
    String likePattern,
    Set<String> recordTypes,
    Set<Id> accountIds,
    String specialty,
    Integer lim,
    Integer rowOffset
  ) {
    String specialtyFilter = resolveSpecialtyFilter(specialty);
    if (accountIds == null) {
      if (likePattern == null && specialtyFilter == null) {
        return [
          SELECT
            Id,
            Name,
            Specialty_1__c,
            BillingCity,
            BillingStreet,
            BillingLatitude,
            BillingLongitude,
            RecordType.Name,
            RecordType.DeveloperName
          FROM Account
          WHERE RecordType.DeveloperName IN :recordTypes
          WITH USER_MODE
          ORDER BY Name ASC
          LIMIT :lim
          OFFSET :rowOffset
        ];
      }
      if (likePattern == null) {
        return [
          SELECT
            Id,
            Name,
            Specialty_1__c,
            BillingCity,
            BillingStreet,
            BillingLatitude,
            BillingLongitude,
            RecordType.Name,
            RecordType.DeveloperName
          FROM Account
          WHERE RecordType.DeveloperName IN :recordTypes AND Specialty_1__c = :specialtyFilter
          WITH USER_MODE
          ORDER BY Name ASC
          LIMIT :lim
          OFFSET :rowOffset
        ];
      }
      if (specialtyFilter == null) {
        return [
          SELECT
            Id,
            Name,
            Specialty_1__c,
            BillingCity,
            BillingStreet,
            BillingLatitude,
            BillingLongitude,
            RecordType.Name,
            RecordType.DeveloperName
          FROM Account
          WHERE
            RecordType.DeveloperName IN :recordTypes
            AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
          WITH USER_MODE
          ORDER BY Name ASC
          LIMIT :lim
          OFFSET :rowOffset
        ];
      }
      return [
        SELECT
          Id,
          Name,
          Specialty_1__c,
          BillingCity,
          BillingStreet,
          BillingLatitude,
          BillingLongitude,
          RecordType.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE
          RecordType.DeveloperName IN :recordTypes
          AND Specialty_1__c = :specialtyFilter
          AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT :lim
        OFFSET :rowOffset
      ];
    }

    if (accountIds.isEmpty()) {
      return new List<Account>();
    }
    if (likePattern == null && specialtyFilter == null) {
      return [
        SELECT
          Id,
          Name,
          Specialty_1__c,
          BillingCity,
          BillingStreet,
          BillingLatitude,
          BillingLongitude,
          RecordType.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE Id IN :accountIds AND RecordType.DeveloperName IN :recordTypes
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT :lim
        OFFSET :rowOffset
      ];
    }
    if (likePattern == null) {
      return [
        SELECT
          Id,
          Name,
          Specialty_1__c,
          BillingCity,
          BillingStreet,
          BillingLatitude,
          BillingLongitude,
          RecordType.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :recordTypes
          AND Specialty_1__c = :specialtyFilter
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT :lim
        OFFSET :rowOffset
      ];
    }
    if (specialtyFilter == null) {
      return [
        SELECT
          Id,
          Name,
          Specialty_1__c,
          BillingCity,
          BillingStreet,
          BillingLatitude,
          BillingLongitude,
          RecordType.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE
          Id IN :accountIds
          AND RecordType.DeveloperName IN :recordTypes
          AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT :lim
        OFFSET :rowOffset
      ];
    }
    return [
      SELECT
        Id,
        Name,
        Specialty_1__c,
        BillingCity,
        BillingStreet,
        BillingLatitude,
        BillingLongitude,
        RecordType.Name,
        RecordType.DeveloperName
      FROM Account
      WHERE
        Id IN :accountIds
        AND RecordType.DeveloperName IN :recordTypes
        AND Specialty_1__c = :specialtyFilter
        AND (Name LIKE :likePattern OR Specialty_1__c LIKE :likePattern OR BillingCity LIKE :likePattern)
      WITH USER_MODE
      ORDER BY Name ASC
      LIMIT :lim
      OFFSET :rowOffset
    ];
  }

  @TestVisible
  private static Boolean hasFullPlannerAccountAccess() {
    if (isSystemAdministrator()) {
      return true;
    }
    Id headOfficeId = getHeadOfficeTerritoryId();
    if (headOfficeId == null) {
      return false;
    }
    for (UserTerritory2Association assignment : [
      SELECT Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :headOfficeId
      WITH USER_MODE
      LIMIT 1
    ]) {
      return true;
    }
    return false;
  }

  @TestVisible
  private static Id getHeadOfficeTerritoryId() {
    List<Territory2> territories = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = :HEAD_OFFICE_EXTERNAL_ID
      WITH USER_MODE
      LIMIT 1
    ];
    return territories.isEmpty() ? null : territories[0].Id;
  }

  @TestVisible
  private static Boolean isSystemAdministrator() {
    User currentUser = [
      SELECT Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH USER_MODE
      LIMIT 1
    ];
    return currentUser.Profile.Name == 'System Administrator';
  }

  @TestVisible
  private static Set<Id> getTerritoryAccountIds() {
    return resolveTerritoryAccountIds(expandTerritoryHierarchy(getUserTerritoryIds()));
  }

  private static Set<Id> resolveTerritoryAccountIds(Set<Id> territoryIds) {
    if (territoryIds == null || territoryIds.isEmpty()) {
      return new Set<Id>();
    }

    Set<String> territoryIdStrings = toTerritoryIdStrings(territoryIds);

    Set<Id> accountIds = new Set<Id>();
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c
      FROM Account_Territory_Fields__c
      WHERE
        Territory2_Id__c IN :territoryIdStrings
        AND Is_Active__c = TRUE
        AND Account__c != NULL
      WITH SYSTEM_MODE
    ]) {
      accountIds.add(atf.Account__c);
    }
    return accountIds;
  }

  @TestVisible
  private static Set<Id> getUserTerritoryIds() {
    Set<Id> territoryIds = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    return territoryIds;
  }

  @TestVisible
  private static Set<Id> expandTerritoryHierarchy(Set<Id> seedTerritoryIds) {
    Set<Id> allTerritoryIds = new Set<Id>(seedTerritoryIds);
    Boolean addedChildren = true;
    while (addedChildren) {
      addedChildren = false;
      List<Territory2> children = [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :allTerritoryIds AND Id NOT IN :allTerritoryIds
        WITH SYSTEM_MODE
      ];
      for (Territory2 child : children) {
        allTerritoryIds.add(child.Id);
        addedChildren = true;
      }
    }
    return allTerritoryIds;
  }

  private static List<AccountSummary> mapAccountSummaries(List<Account> accounts) {
    List<AccountSummary> results = new List<AccountSummary>();
    for (Account account : accounts) {
      AccountSummary summary = new AccountSummary();
      summary.id = account.Id;
      summary.name = account.Name;
      summary.specialty = MedicalSpecialtyPicklist.getLabel(account.Specialty_1__c);
      summary.specialtyApiValue = account.Specialty_1__c;
      summary.city = account.BillingCity;
      summary.street = account.BillingStreet;
      summary.latitude = account.BillingLatitude;
      summary.longitude = account.BillingLongitude;
      summary.recordTypeName = account.RecordType != null ? account.RecordType.Name : null;
      summary.recordTypeDeveloperName = account.RecordType != null
        ? account.RecordType.DeveloperName
        : null;
      results.add(summary);
    }
    return results;
  }

  private static VisitSummary mapVisit(Visit__c visit) {
    VisitSummary summary = new VisitSummary();
    summary.id = visit.Id;
    summary.name = visit.Name;
    summary.accountId = visit.Account__c;
    summary.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
    summary.status = visit.Status__c;
    summary.visitType = visit.Visit_Type__c;
    summary.cancellationReason = visit.Cancellation_Reason__c;
    summary.startDateTime = visit.Start_Date__c;
    summary.endDateTime = visit.End_Date__c;
    if (visit.Account__r != null) {
      summary.accountLatitude = visit.Account__r.BillingLatitude;
      summary.accountLongitude = visit.Account__r.BillingLongitude;
      summary.accountSpecialty = MedicalSpecialtyPicklist.getLabel(
        visit.Account__r.Specialty_1__c
      );
      summary.accountRecordTypeName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.Name
        : null;
      summary.accountRecordTypeDeveloperName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.DeveloperName
        : null;
    }
    if (plannerHasVisitZetaProjectField()) {
      summary.zetaProjectId = (Id) visit.get('Pharma_Project__c');
      SObject zetaProject = visit.getSObject('Pharma_Project__r');
      summary.zetaProjectName = zetaProject != null ? (String) zetaProject.get('Name') : null;
    }
    summary.visitObjective = visit.Visit_Objective__c;
    return summary;
  }

  private static MeetingSummary mapMeeting(Meeting__c meeting) {
    MeetingSummary summary = new MeetingSummary();
    summary.id = meeting.Id;
    summary.name = meeting.Name;
    summary.title = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c : meeting.Name;
    summary.status = meeting.Status__c;
    summary.startDateTime = meeting.Start_Date_Time__c;
    summary.endDateTime = meeting.End_Date_Time__c;
    summary.pharmaProjectId = meeting.Pharma_Project__c;
    summary.pharmaProjectName = meeting.Pharma_Project__r != null
      ? meeting.Pharma_Project__r.Name
      : null;
    summary.recordTypeDeveloperName = meeting.RecordType != null
      ? meeting.RecordType.DeveloperName
      : null;
    summary.recordTypeLabel = meeting.RecordType != null ? meeting.RecordType.Name : null;
    return summary;
  }

  private static VisitDetail mapVisitDetail(Visit__c visit) {
    VisitDetail detail = new VisitDetail();
    detail.id = visit.Id;
    detail.name = visit.Name;
    detail.status = visit.Status__c;
    detail.visitType = visit.Visit_Type__c;
    detail.startDateTime = visit.Start_Date__c;
    detail.endDateTime = visit.End_Date__c;
    detail.durationLabel = formatDurationLabel(visit.Start_Date__c, visit.End_Date__c);
    detail.visitObjective = visit.Visit_Objective__c;
    detail.visitNotes = visit.Visit_Notes__c;
    detail.productsDiscussed = visit.Products_Discussed__c;
    detail.productDetails = visit.Product_Details__c;
    detail.clmPresentation = visit.CLM_Presentation__c;
    detail.nextVisitDate = visit.Next_Visit_Date__c;
    detail.cancellationReason = visit.Cancellation_Reason__c;
    detail.planRejectionReason = visit.Plan_Rejection_Reason__c;
    detail.isLocked =
      VisitStatusHelper.isLockedStatus(visit.Status__c) ||
      VisitStatusHelper.isPendingApproval(visit.Status__c);
    detail.accountId = visit.Account__c;
    if (visit.Account__r != null) {
      detail.accountName = visit.Account__r.Name;
      detail.accountCity = visit.Account__r.BillingCity;
      detail.accountStreet = visit.Account__r.BillingStreet;
      detail.accountSpecialty = MedicalSpecialtyPicklist.getLabel(
        visit.Account__r.Specialty_1__c
      );
      detail.accountRecordTypeName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.Name
        : null;
      detail.accountRecordTypeDeveloperName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.DeveloperName
        : null;
    }
    detail.assignedToName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
    return detail;
  }

  private static String formatDurationLabel(DateTime startDateTime, DateTime endDateTime) {
    if (startDateTime == null || endDateTime == null) {
      return null;
    }
    Long minutes = (endDateTime.getTime() - startDateTime.getTime()) / (1000 * 60);
    if (minutes < 60) {
      return minutes + ' min';
    }
    Long hours = minutes / 60;
    Long remainder = Math.mod(minutes, 60);
    return remainder == 0 ? hours + ' hr' : hours + ' hr ' + remainder + ' min';
  }

  private static TotSummary mapTimeOff(Time_Off_Request__c request) {
    TotSummary summary = new TotSummary();
    summary.id = request.Id;
    summary.name = request.Name;
    summary.typeLabel = request.Type__c;
    summary.typeValue = request.Type__c;
    summary.comments = request.Comments__c;
    summary.spanType = request.Span_Type__c;
    summary.stage = request.Stage__c;
    summary.isFullDay = request.Span_Type__c == 'Full_Day';
    summary.startDateTime = request.Start_Date_Time__c;
    summary.endDateTime = request.End_Date_Time__c;

    if (summary.isFullDay && summary.startDateTime != null) {
      Date startDay = summary.startDateTime.date();
      summary.startDateTime = DateTime.newInstance(startDay, Time.newInstance(0, 0, 0, 0));
      summary.endDateTime = DateTime.newInstance(startDay.addDays(1), Time.newInstance(0, 0, 0, 0));
    }
    return summary;
  }

  private static Id resolveContextUserId(Id requestedUserId) {
    if (requestedUserId == null || requestedUserId == UserInfo.getUserId()) {
      return UserInfo.getUserId();
    }
    assertCanViewPlannerFor(requestedUserId);
    return requestedUserId;
  }

  private static void assertCanViewPlannerFor(Id targetUserId) {
    if (targetUserId == null || targetUserId == UserInfo.getUserId()) {
      return;
    }
    if (hasFullPlannerAccountAccess()) {
      Set<Id> allowed = getViewableUserIdsForAdmin();
      if (!allowed.contains(targetUserId)) {
        throw new AuraHandledException('You do not have permission to view this planner.');
      }
      return;
    }
    throw new AuraHandledException('You do not have permission to view this planner.');
  }

  private static void assertCanMutatePlanner() {
    // Mutations always apply to the running user only.
  }

  private static Set<Id> resolveScopedAccountIds(Id contextUserId) {
    if (contextUserId == UserInfo.getUserId() && hasFullPlannerAccountAccess()) {
      return null;
    }
    Set<Id> accountIds = getTerritoryAccountIdsForUser(contextUserId);
    if (!accountIds.isEmpty()) {
      return accountIds;
    }
    // Match Field Rep Home: fall back to the rep's monthly time-card account targets.
    return getTimeCardAccountIdsForUser(contextUserId);
  }

  private static Set<Id> getTimeCardAccountIdsForUser(Id userId) {
    Set<Id> accountIds = new Set<Id>();
    if (userId == null) {
      return accountIds;
    }
    Date monthStart = Date.today().toStartOfMonth();
    List<Employee_Time_Card__c> cards = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE
        Employee__c = :userId
        AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    if (cards.isEmpty()) {
      return accountIds;
    }
    for (Employee_Time_Card_Account_Target__c target : [
      SELECT Account__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE Employee_Time_Card__c = :cards[0].Id AND Account__c != NULL
      WITH USER_MODE
    ]) {
      accountIds.add(target.Account__c);
    }
    return accountIds;
  }

  private static Set<String> toTerritoryIdStrings(Set<Id> territoryIds) {
    Set<String> territoryIdStrings = new Set<String>();
    if (territoryIds == null || territoryIds.isEmpty()) {
      return territoryIdStrings;
    }
    for (Id territoryId : territoryIds) {
      territoryIdStrings.add(String.valueOf(territoryId));
    }
    return territoryIdStrings;
  }

  private static Set<Id> applyClassificationFilter(
    Set<Id> accountIds,
    String classification,
    Id contextUserId
  ) {
    if (String.isBlank(classification) || FILTER_ALL.equals(classification)) {
      return accountIds;
    }
    Set<String> territoryIdStrings = toTerritoryIdStrings(
      expandTerritoryHierarchy(getUserTerritoryIdsForUser(contextUserId))
    );
    if (territoryIdStrings.isEmpty()) {
      return new Set<Id>();
    }
    Set<Id> classifiedIds = new Set<Id>();
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c, Classification__c, HCP_Classification__c
      FROM Account_Territory_Fields__c
      WHERE
        Territory2_Id__c IN :territoryIdStrings
        AND Is_Active__c = TRUE
        AND Account__c != NULL
      WITH SYSTEM_MODE
    ]) {
      if (resolveClassification(atf) == classification) {
        classifiedIds.add(atf.Account__c);
      }
    }
    if (accountIds == null) {
      return classifiedIds;
    }
    classifiedIds.retainAll(accountIds);
    return classifiedIds;
  }

  private static Set<Id> applyBrickFilter(Set<Id> accountIds, Id brickId) {
    if (brickId == null) {
      return accountIds;
    }
    Set<Id> brickAccountIds = new Set<Id>();
    if (accountIds == null) {
      for (Account account : [
        SELECT Id
        FROM Account
        WHERE
          RecordType.DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
          AND Brick__c = :brickId
        WITH USER_MODE
      ]) {
        brickAccountIds.add(account.Id);
      }
      return brickAccountIds;
    }
    if (accountIds.isEmpty()) {
      return accountIds;
    }
    for (Account account : [
      SELECT Id
      FROM Account
      WHERE Id IN :accountIds AND Brick__c = :brickId
      WITH USER_MODE
    ]) {
      brickAccountIds.add(account.Id);
    }
    return brickAccountIds;
  }

  private static String resolveSpecialtyFilter(String specialty) {
    if (String.isBlank(specialty) || FILTER_ALL.equals(specialty)) {
      return null;
    }
    return MedicalSpecialtyPicklist.resolveApiValue(specialty);
  }

  private static Set<Id> getUserTerritoryIdsForUser(Id userId) {
    Set<Id> territoryIds = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :userId
      WITH SYSTEM_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    return territoryIds;
  }

  private static Set<Id> getTerritoryAccountIdsForUser(Id userId) {
    return resolveTerritoryAccountIds(expandTerritoryHierarchy(getUserTerritoryIdsForUser(userId)));
  }

  private static List<PlannerViewerOption> buildViewerOptionsForTerritories(Set<Id> territoryIds) {
    List<PlannerViewerOption> options = new List<PlannerViewerOption>();
    if (territoryIds == null || territoryIds.isEmpty()) {
      return options;
    }
    Map<Id, String> parentNamesByTerritoryId = new Map<Id, String>();
    for (Territory2 territory : [
      SELECT Id, ParentTerritory2Id, ParentTerritory2.Name
      FROM Territory2
      WHERE Id IN :territoryIds
      WITH USER_MODE
    ]) {
      parentNamesByTerritoryId.put(
        territory.Id,
        territory.ParentTerritory2 != null ? territory.ParentTerritory2.Name : null
      );
    }
    for (UserTerritory2Association assignment : [
      SELECT UserId, User.Name, Territory2Id, Territory2.Name
      FROM UserTerritory2Association
      WHERE Territory2Id IN :territoryIds AND User.IsActive = TRUE
      WITH USER_MODE
      ORDER BY Territory2.Name, User.Name
    ]) {
      if (assignment.UserId == UserInfo.getUserId()) {
        continue;
      }
      PlannerViewerOption option = new PlannerViewerOption();
      option.territoryId = assignment.Territory2Id;
      option.territoryName = assignment.Territory2.Name;
      option.userId = assignment.UserId;
      option.userName = assignment.User.Name;
      option.parentTerritoryName = parentNamesByTerritoryId.get(assignment.Territory2Id);
      option.label = assignment.Territory2.Name + ' — ' + assignment.User.Name;
      options.add(option);
    }
    return options;
  }

  private static Set<Id> getViewableUserIdsForAdmin() {
    Set<Id> userIds = new Set<Id>();
    Id headOfficeId = getHeadOfficeTerritoryId();
    if (headOfficeId == null) {
      return userIds;
    }
    Set<Id> territoryIds = expandTerritoryHierarchy(new Set<Id>{ headOfficeId });
    for (UserTerritory2Association assignment : [
      SELECT UserId
      FROM UserTerritory2Association
      WHERE Territory2Id IN :territoryIds AND User.IsActive = TRUE
      WITH USER_MODE
    ]) {
      userIds.add(assignment.UserId);
    }
    return userIds;
  }

  private static List<AccountSummary> attachClassificationToSummaries(
    List<AccountSummary> summaries,
    Id contextUserId
  ) {
    if (summaries == null || summaries.isEmpty()) {
      return summaries;
    }
    Set<Id> accountIds = new Set<Id>();
    for (AccountSummary summary : summaries) {
      accountIds.add(summary.id);
    }
    Set<String> territoryIdStrings = toTerritoryIdStrings(
      expandTerritoryHierarchy(getUserTerritoryIdsForUser(contextUserId))
    );
    Map<Id, String> classificationByAccountId = new Map<Id, String>();
    if (!territoryIdStrings.isEmpty()) {
      for (Account_Territory_Fields__c atf : [
        SELECT Account__c, Classification__c, HCP_Classification__c
        FROM Account_Territory_Fields__c
        WHERE
          Account__c IN :accountIds
          AND Territory2_Id__c IN :territoryIdStrings
          AND Is_Active__c = TRUE
        WITH SYSTEM_MODE
      ]) {
        if (!classificationByAccountId.containsKey(atf.Account__c)) {
          String classVal = resolveClassification(atf);
          if (String.isNotBlank(classVal)) {
            classificationByAccountId.put(atf.Account__c, classVal);
          }
        }
      }
    }
    for (AccountSummary summary : summaries) {
      summary.classification = classificationByAccountId.get(summary.id);
    }
    return summaries;
  }

  private static List<AccountSummary> attachVisitMetricsToSummaries(
    List<AccountSummary> summaries,
    Id contextUserId
  ) {
    if (summaries == null || summaries.isEmpty()) {
      return summaries;
    }
    Set<Id> accountIds = new Set<Id>();
    for (AccountSummary summary : summaries) {
      accountIds.add(summary.id);
    }
    Id resolvedUserId = resolveContextUserId(contextUserId);
    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    List<Employee_Time_Card__c> cards = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE
        Employee__c = :resolvedUserId
        AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    Map<Id, Employee_Time_Card_Account_Target__c> targetByAccountId = new Map<Id, Employee_Time_Card_Account_Target__c>();
    WorkingDaysSummary workingDays = new WorkingDaysSummary();
    Boolean hasTimeCard = !cards.isEmpty();
    if (hasTimeCard) {
      Id timeCardId = cards[0].Id;
      workingDays = computeWorkingDays(timeCardId, Date.today());
      for (Employee_Time_Card_Account_Target__c target : [
        SELECT
          Account__c,
          Actual_Visits__c,
          Target_Visit_Frequency__c,
          Frequency_Status__c
        FROM Employee_Time_Card_Account_Target__c
        WHERE Employee_Time_Card__c = :timeCardId AND Account__c IN :accountIds
        WITH USER_MODE
      ]) {
        targetByAccountId.put(target.Account__c, target);
      }
    }

    Map<Id, Integer> plannedByAccountId = loadPlannedVisitCounts(
      accountIds,
      resolvedUserId,
      monthEnd
    );

    for (AccountSummary summary : summaries) {
      summary.plannedVisits = plannedByAccountId.containsKey(summary.id)
        ? plannedByAccountId.get(summary.id)
        : 0;
      Employee_Time_Card_Account_Target__c target = targetByAccountId.get(summary.id);
      if (target != null) {
        summary.actualVisits = nvl(target.Actual_Visits__c);
        summary.targetVisits = target.Target_Visit_Frequency__c;
        summary.frequencyStatus = target.Frequency_Status__c;
      }
      applyPaceStatus(summary, hasTimeCard, workingDays);
    }
    return summaries;
  }

  private static Map<Id, Integer> loadPlannedVisitCounts(
    Set<Id> accountIds,
    Id userId,
    Date monthEnd
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    DateTime rangeStart = DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
    Set<String> plannedStatuses = new Set<String>(PLANNED_VISIT_STATUSES);
    for (AggregateResult agg : [
      SELECT Account__c accountId, COUNT(Id) visitCount
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :rangeStart
        AND Start_Date__c <= :rangeEnd
        AND Status__c IN :plannedStatuses
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      counts.put((Id) agg.get('accountId'), (Integer) agg.get('visitCount'));
    }
    return counts;
  }

  private static void applyPaceStatus(
    AccountSummary summary,
    Boolean hasTimeCard,
    WorkingDaysSummary workingDays
  ) {
    Decimal targetVisits = nvl(summary.targetVisits);
    Decimal actualVisits = nvl(summary.actualVisits);
    if (!hasTimeCard) {
      summary.paceStatus = 'na';
      summary.paceStatusLabel = paceStatusLabel(summary.paceStatus);
      return;
    }
    if (workingDays.paceRatio > 0 && targetVisits > 0) {
      Decimal projectedVisits = actualVisits / workingDays.paceRatio;
      Decimal projectedPercent = (projectedVisits / targetVisits) * 100;
      summary.paceStatus = paceStatusFromProjected(projectedPercent);
    } else if (targetVisits > 0 && actualVisits > 0) {
      summary.paceStatus = 'ahead';
    } else if (targetVisits > 0) {
      summary.paceStatus = 'critical';
    } else {
      summary.paceStatus = 'na';
    }
    summary.paceStatusLabel = paceStatusLabel(summary.paceStatus);
  }

  private static String paceStatusFromProjected(Decimal projectedPercent) {
    if (projectedPercent >= 100) {
      return 'ahead';
    }
    if (projectedPercent >= PACE_ON_TRACK_THRESHOLD) {
      return 'on_track';
    }
    if (projectedPercent >= PACE_CRITICAL_THRESHOLD) {
      return 'behind';
    }
    return 'critical';
  }

  private static String paceStatusLabel(String paceStatus) {
    if (paceStatus == 'ahead') {
      return 'Ahead';
    }
    if (paceStatus == 'on_track') {
      return 'On Track';
    }
    if (paceStatus == 'behind') {
      return 'Behind';
    }
    if (paceStatus == 'critical') {
      return 'Critical';
    }
    return 'N/A';
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private class WorkingDaysSummary {
    public Integer elapsedWorkingDays = 0;
    public Integer totalWorkingDays = 0;
    public Decimal paceRatio = 0;
  }

  private static WorkingDaysSummary computeWorkingDays(Id timeCardId, Date asOfDate) {
    WorkingDaysSummary summary = new WorkingDaysSummary();
    if (timeCardId == null) {
      return summary;
    }
    for (Employee_Time_Card_Day_Entry__c entry : [
      SELECT Date__c, Calendar_Working_Days__c
      FROM Employee_Time_Card_Day_Entry__c
      WHERE Employee_Time_Card__c = :timeCardId
      WITH USER_MODE
      ORDER BY Date__c ASC
    ]) {
      Integer calDays = nvl(entry.Calendar_Working_Days__c).intValue();
      summary.totalWorkingDays += calDays;
      if (entry.Date__c != null && entry.Date__c <= asOfDate) {
        summary.elapsedWorkingDays += calDays;
      }
    }
    if (summary.totalWorkingDays > 0) {
      summary.paceRatio =
        Decimal.valueOf(summary.elapsedWorkingDays) /
        Decimal.valueOf(summary.totalWorkingDays);
    }
    return summary;
  }

  private static String resolveClassification(Account_Territory_Fields__c atf) {
    if (atf == null) {
      return null;
    }
    if (String.isNotBlank(atf.Classification__c)) {
      return atf.Classification__c;
    }
    return atf.HCP_Classification__c;
  }

  private static List<AccountSummary> attachBrickToSummaries(List<AccountSummary> summaries) {
    if (summaries == null || summaries.isEmpty()) {
      return summaries;
    }
    Set<Id> accountIds = new Set<Id>();
    for (AccountSummary summary : summaries) {
      accountIds.add(summary.id);
    }
    Map<Id, Account> accountsById = new Map<Id, Account>([
      SELECT Id, Brick__c, Brick__r.Name
      FROM Account
      WHERE Id IN :accountIds
      WITH USER_MODE
    ]);
    for (AccountSummary summary : summaries) {
      Account account = accountsById.get(summary.id);
      if (account != null) {
        summary.brickId = account.Brick__c;
        summary.brickName = account.Brick__r != null ? account.Brick__r.Name : null;
      }
    }
    return summaries;
  }
}