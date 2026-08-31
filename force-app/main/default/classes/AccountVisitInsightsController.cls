public with sharing class AccountVisitInsightsController {
  private static final Decimal ON_TRACK_THRESHOLD = 90;
  private static final Decimal CRITICAL_THRESHOLD = 50;
  private static final Integer DEFAULT_START_HOUR = 9;
  private static final Integer VISIT_SLOT_MINUTES = 60;
  private static final Decimal DEFAULT_RADIUS_KM = 25;
  private static final Decimal MAX_SEARCH_RADIUS_KM = 200;
  private static final Integer MAX_NEIGHBORS = 25;
  private static final Set<String> PLANNER_ACCOUNT_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Institution_HCO',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact',
    'Pharmacy'
  };

  public class FutureVisitRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
  }

  public class AccountVisitContext {
    @AuraEnabled
    public Boolean hasPlanTarget;
    @AuraEnabled
    public Boolean hasGeo;
    @AuraEnabled
    public Boolean canMutateVisits;
    @AuraEnabled
    public Decimal targetVisits;
    @AuraEnabled
    public Decimal actualVisits;
    @AuraEnabled
    public Decimal visitGap;
    @AuraEnabled
    public String frequencyStatus;
    @AuraEnabled
    public Decimal reachPercent;
    @AuraEnabled
    public Integer elapsedWorkingDays;
    @AuraEnabled
    public Integer totalWorkingDays;
    @AuraEnabled
    public Decimal projectedVisits;
    @AuraEnabled
    public Decimal projectedPercent;
    @AuraEnabled
    public Boolean willMeetTarget;
    @AuraEnabled
    public Decimal committedVisits;
    @AuraEnabled
    public String paceStatus;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Decimal centerLatitude;
    @AuraEnabled
    public Decimal centerLongitude;
    @AuraEnabled
    public List<FutureVisitRow> futureVisits;
  }

  public class NearbyPlanTarget {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Decimal distanceKm;
    @AuraEnabled
    public Decimal actualVisits;
    @AuraEnabled
    public Decimal targetVisits;
    @AuraEnabled
    public Decimal visitGap;
    @AuraEnabled
    public String frequencyStatus;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeName;
    @AuraEnabled
    public Boolean isCenterAccount;
    @AuraEnabled
    public Boolean selectedByDefault;
  }

  public class NearbyPlanTargetsResult {
    @AuraEnabled
    public Boolean hasGeo;
    @AuraEnabled
    public Decimal searchRadiusKm;
    @AuraEnabled
    public List<NearbyPlanTarget> targets;
  }

  public class DraftVisitSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
  }

  @AuraEnabled(cacheable=true)
  public static AccountVisitContext getAccountVisitContext(Id accountId) {
    AccountVisitContext result = new AccountVisitContext();
    result.hasPlanTarget = false;
    result.hasGeo = false;
    result.canMutateVisits = Schema.sObjectType.Visit__c.isCreateable();
    result.futureVisits = new List<FutureVisitRow>();
    result.targetVisits = 0;
    result.actualVisits = 0;
    result.visitGap = 0;
    result.committedVisits = 0;
    result.projectedVisits = 0;
    result.projectedPercent = 0;
    result.willMeetTarget = false;
    result.paceStatus = 'not_applicable';
    result.elapsedWorkingDays = 0;
    result.totalWorkingDays = 0;

    if (accountId == null) {
      return result;
    }

    List<Account> accounts = [
      SELECT Name, BillingLatitude, BillingLongitude
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      return result;
    }

    Account account = accounts[0];
    result.accountName = account.Name;
    result.hasGeo = account.BillingLatitude != null && account.BillingLongitude != null;
    result.centerLatitude = account.BillingLatitude;
    result.centerLongitude = account.BillingLongitude;

    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);

    PlanContext planContext = resolvePlanContext(accountId, monthStart);
    if (planContext == null) {
      return result;
    }
    Id timeCardId = planContext.timeCardId;
    Id repUserId = planContext.employeeId;

    List<Employee_Time_Card_Account_Target__c> targets = [
      SELECT
        Target_Visit_Frequency__c,
        Actual_Visits__c,
        Frequency_Status__c,
        Reach_Percent__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE Employee_Time_Card__c = :timeCardId AND Account__c = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (targets.isEmpty()) {
      return result;
    }

    Employee_Time_Card_Account_Target__c target = targets[0];
    result.hasPlanTarget = true;
    result.targetVisits = nvl(target.Target_Visit_Frequency__c);
    result.actualVisits = nvl(target.Actual_Visits__c);
    result.frequencyStatus = target.Frequency_Status__c;
    result.reachPercent = PercentFieldHelper.toDisplayScale(target.Reach_Percent__c);
    result.visitGap = Math.max(0, result.targetVisits - result.actualVisits);

    WorkingDaysSummary workingDays = computeWorkingDays(timeCardId, Date.today());
    result.elapsedWorkingDays = workingDays.elapsedWorkingDays;
    result.totalWorkingDays = workingDays.totalWorkingDays;
    Decimal paceRatio = workingDays.paceRatio;

    Integer futurePlannedThisMonth = 0;
    for (Visit__c visit : [
      SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
      FROM Visit__c
      WHERE
        Account__c = :accountId
        AND Assigned_To__c = :repUserId
        AND Start_Date__c >= :DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0))
        AND Start_Date__c <= :DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0))
        AND Status__c IN ('Draft', 'Scheduled', 'Rescheduled')
      WITH USER_MODE
      ORDER BY Start_Date__c ASC
    ]) {
      FutureVisitRow row = new FutureVisitRow();
      row.id = visit.Id;
      row.name = visit.Name;
      row.status = visit.Status__c;
      row.startDateTime = visit.Start_Date__c;
      row.endDateTime = visit.End_Date__c;
      result.futureVisits.add(row);
      futurePlannedThisMonth++;
    }

    result.committedVisits = result.actualVisits + futurePlannedThisMonth;
    if (paceRatio > 0) {
      result.projectedVisits = result.actualVisits / paceRatio;
    } else {
      result.projectedVisits = result.actualVisits;
    }
    if (result.targetVisits > 0) {
      result.projectedPercent = (result.projectedVisits / result.targetVisits) * 100;
      result.willMeetTarget = result.projectedVisits >= result.targetVisits;
    } else if (result.actualVisits > 0) {
      result.projectedPercent = 100;
      result.willMeetTarget = true;
    }
    result.paceStatus = paceStatusFromProjected(result.projectedPercent);
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static NearbyPlanTargetsResult getNearbyPlanTargets(Id accountId, Decimal radiusKm) {
    NearbyPlanTargetsResult result = new NearbyPlanTargetsResult();
    result.targets = new List<NearbyPlanTarget>();
    result.hasGeo = false;
    result.searchRadiusKm = DEFAULT_RADIUS_KM;

    if (accountId == null) {
      return result;
    }

    Decimal requestedRadius = radiusKm == null || radiusKm <= 0 ? DEFAULT_RADIUS_KM : radiusKm;

    List<Account> centerAccounts = [
      SELECT
        Name,
        BillingLatitude,
        BillingLongitude,
        Specialty_1__c,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (centerAccounts.isEmpty()) {
      return result;
    }

    Account center = centerAccounts[0];
    if (center.BillingLatitude == null || center.BillingLongitude == null) {
      return result;
    }
    result.hasGeo = true;

    Date monthStart = Date.today().toStartOfMonth();
    PlanContext planContext = resolvePlanContext(accountId, monthStart);
    if (planContext == null) {
      result.targets.add(buildCenterTarget(center, accountId, 0));
      result.searchRadiusKm = 0;
      return result;
    }

    List<NearbyPlanTarget> allCandidates = buildIncompletePlanTargetCandidates(
      planContext.timeCardId,
      center,
      accountId
    );
    Decimal effectiveRadius = resolveSearchRadius(requestedRadius, allCandidates, accountId);
    result.searchRadiusKm = effectiveRadius.setScale(1);

    List<NearbyPlanTarget> scored = new List<NearbyPlanTarget>();
    for (NearbyPlanTarget candidate : allCandidates) {
      if (candidate.distanceKm <= effectiveRadius) {
        scored.add(candidate);
      }
    }

    scored.sort(new NearbyPlanTargetDistanceComparator());
    Boolean centerIncluded = false;
    for (NearbyPlanTarget row : scored) {
      if (row.isCenterAccount) {
        centerIncluded = true;
      }
      result.targets.add(row);
      if (result.targets.size() >= MAX_NEIGHBORS) {
        break;
      }
    }

    if (!centerIncluded) {
      NearbyPlanTarget centerRow = buildCenterTarget(center, accountId, 0);
      Employee_Time_Card_Account_Target__c centerTarget = findTargetForAccount(planContext.timeCardId, accountId);
      if (centerTarget != null) {
        centerRow.actualVisits = nvl(centerTarget.Actual_Visits__c);
        centerRow.targetVisits = nvl(centerTarget.Target_Visit_Frequency__c);
        centerRow.visitGap = Math.max(0, centerRow.targetVisits - centerRow.actualVisits);
        centerRow.frequencyStatus = centerTarget.Frequency_Status__c;
      }
      result.targets.add(0, centerRow);
      if (result.targets.size() > MAX_NEIGHBORS) {
        result.targets.remove(result.targets.size() - 1);
      }
    }

    return result;
  }

  private static List<NearbyPlanTarget> buildIncompletePlanTargetCandidates(
    Id timeCardId,
    Account center,
    Id centerAccountId
  ) {
    List<NearbyPlanTarget> candidates = new List<NearbyPlanTarget>();
    for (Employee_Time_Card_Account_Target__c target : [
      SELECT
        Account__c,
        Account__r.Name,
        Account__r.Specialty_1__c,
        Account__r.BillingLatitude,
        Account__r.BillingLongitude,
        Account__r.RecordType.DeveloperName,
        Account__r.RecordType.Name,
        Target_Visit_Frequency__c,
        Actual_Visits__c,
        Frequency_Status__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE
        Employee_Time_Card__c = :timeCardId
        AND Account__r.BillingLatitude != NULL
        AND Account__r.BillingLongitude != NULL
        AND Account__r.RecordType.DeveloperName IN :PLANNER_ACCOUNT_RECORD_TYPES
      WITH USER_MODE
      LIMIT 500
    ]) {
      if (nvl(target.Actual_Visits__c) >= nvl(target.Target_Visit_Frequency__c)) {
        continue;
      }

      Decimal distanceKm = haversineKm(
        center.BillingLatitude,
        center.BillingLongitude,
        target.Account__r.BillingLatitude,
        target.Account__r.BillingLongitude
      );
      if (distanceKm > MAX_SEARCH_RADIUS_KM) {
        continue;
      }

      NearbyPlanTarget row = new NearbyPlanTarget();
      row.accountId = target.Account__c;
      row.name = target.Account__r.Name;
      row.specialty = MedicalSpecialtyPicklist.getLabel(target.Account__r.Specialty_1__c);
      row.latitude = target.Account__r.BillingLatitude;
      row.longitude = target.Account__r.BillingLongitude;
      row.distanceKm = distanceKm.setScale(1);
      row.actualVisits = nvl(target.Actual_Visits__c);
      row.targetVisits = nvl(target.Target_Visit_Frequency__c);
      row.visitGap = Math.max(0, row.targetVisits - row.actualVisits);
      row.frequencyStatus = target.Frequency_Status__c;
      row.recordTypeDeveloperName = target.Account__r.RecordType.DeveloperName;
      row.recordTypeName = target.Account__r.RecordType.Name;
      row.isCenterAccount = target.Account__c == centerAccountId;
      row.selectedByDefault = row.isCenterAccount;
      candidates.add(row);
    }
    return candidates;
  }

  private static Decimal resolveSearchRadius(
    Decimal requestedRadius,
    List<NearbyPlanTarget> candidates,
    Id centerAccountId
  ) {
    Decimal effectiveRadius = requestedRadius > MAX_SEARCH_RADIUS_KM
      ? MAX_SEARCH_RADIUS_KM
      : requestedRadius;
    if (hasNeighborWithinRadius(candidates, centerAccountId, effectiveRadius)) {
      return effectiveRadius;
    }

    Decimal nearestNeighborKm = null;
    for (NearbyPlanTarget candidate : candidates) {
      if (candidate.isCenterAccount) {
        continue;
      }
      if (nearestNeighborKm == null || candidate.distanceKm < nearestNeighborKm) {
        nearestNeighborKm = candidate.distanceKm;
      }
    }

    if (nearestNeighborKm == null) {
      return effectiveRadius;
    }

    return nearestNeighborKm > MAX_SEARCH_RADIUS_KM
      ? MAX_SEARCH_RADIUS_KM
      : nearestNeighborKm;
  }

  private static Boolean hasNeighborWithinRadius(
    List<NearbyPlanTarget> candidates,
    Id centerAccountId,
    Decimal radiusKm
  ) {
    for (NearbyPlanTarget candidate : candidates) {
      if (candidate.accountId == centerAccountId) {
        continue;
      }
      if (candidate.distanceKm <= radiusKm) {
        return true;
      }
    }
    return false;
  }

  @AuraEnabled
  public static List<DraftVisitSummary> bulkCreateDraftVisits(
    List<Id> accountIds,
    Date visitDate,
    Integer startHour
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      throw new AuraHandledException('Select at least one account.');
    }
    if (visitDate == null) {
      throw new AuraHandledException('Visit date is required.');
    }
    if (visitDate < Date.today()) {
      throw new AuraHandledException('Visit date cannot be in the past.');
    }
    if (!Schema.sObjectType.Visit__c.isCreateable()) {
      throw new AuraHandledException('You do not have permission to create visits.');
    }

    Integer hour = startHour == null ? DEFAULT_START_HOUR : startHour;
    Map<Id, Account> accountsById = new Map<Id, Account>(
      [
        SELECT Id, Name
        FROM Account
        WHERE Id IN :accountIds
        WITH USER_MODE
      ]
    );

    List<Visit__c> visitsToInsert = new List<Visit__c>();
    Integer slotIndex = 0;
    for (Id accountId : accountIds) {
      if (!accountsById.containsKey(accountId)) {
        continue;
      }
      DateTime startDt = DateTime.newInstance(visitDate, Time.newInstance(0, 0, 0, 0))
        .addHours(hour)
        .addMinutes(slotIndex * VISIT_SLOT_MINUTES);
      DateTime endDt = startDt.addMinutes(VISIT_SLOT_MINUTES);
      visitsToInsert.add(
        new Visit__c(
          Account__c = accountId,
          Assigned_To__c = UserInfo.getUserId(),
          Start_Date__c = startDt,
          End_Date__c = endDt,
          Visit_Date__c = startDt,
          Status__c = 'Draft',
          Visit_Type__c = 'Planned (Automatically)'
        )
      );
      slotIndex++;
    }

    if (visitsToInsert.isEmpty()) {
      throw new AuraHandledException('No valid accounts were selected.');
    }

    insert as user visitsToInsert;

    List<DraftVisitSummary> results = new List<DraftVisitSummary>();
    for (Visit__c visit : [
      SELECT Id, Account__c, Account__r.Name, Start_Date__c, End_Date__c
      FROM Visit__c
      WHERE Id IN :visitsToInsert
      WITH USER_MODE
      ORDER BY Start_Date__c ASC
    ]) {
      DraftVisitSummary row = new DraftVisitSummary();
      row.id = visit.Id;
      row.accountId = visit.Account__c;
      row.accountName = visit.Account__r.Name;
      row.startDateTime = visit.Start_Date__c;
      row.endDateTime = visit.End_Date__c;
      results.add(row);
    }
    return results;
  }

  private class WorkingDaysSummary {
    public Integer elapsedWorkingDays = 0;
    public Integer totalWorkingDays = 0;
    public Decimal paceRatio = 0;
  }

  private static WorkingDaysSummary computeWorkingDays(Id timeCardId, Date asOfDate) {
    WorkingDaysSummary summary = new WorkingDaysSummary();
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
      summary.paceRatio = Decimal.valueOf(summary.elapsedWorkingDays) /
        Decimal.valueOf(summary.totalWorkingDays);
    }
    return summary;
  }

  private class PlanContext {
    public Id timeCardId;
    public Id employeeId;
  }

  /**
   * Resolves the current-month plan cycle to use for this account. Prefers the
   * running user's own time card (rep viewing their own plan). If the running
   * user has no current-month time card, falls back to the rep whose plan cycle
   * actually targets this account, so managers/admins still see meaningful data.
   */
  private static PlanContext resolvePlanContext(Id accountId, Date monthStart) {
    Id userId = UserInfo.getUserId();
    List<Employee_Time_Card__c> ownCards = [
      SELECT Id, Employee__c
      FROM Employee_Time_Card__c
      WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    if (!ownCards.isEmpty()) {
      PlanContext ctx = new PlanContext();
      ctx.timeCardId = ownCards[0].Id;
      ctx.employeeId = ownCards[0].Employee__c;
      return ctx;
    }

    List<Employee_Time_Card_Account_Target__c> accountTargets = [
      SELECT Employee_Time_Card__c, Employee_Time_Card__r.Employee__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE
        Account__c = :accountId
        AND Employee_Time_Card__r.Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      ORDER BY Employee_Time_Card__r.Employee__c
      LIMIT 1
    ];
    if (!accountTargets.isEmpty()) {
      PlanContext ctx = new PlanContext();
      ctx.timeCardId = accountTargets[0].Employee_Time_Card__c;
      ctx.employeeId = accountTargets[0].Employee_Time_Card__r.Employee__c;
      return ctx;
    }

    return null;
  }

  private static Employee_Time_Card_Account_Target__c findTargetForAccount(
    Id timeCardId,
    Id accountId
  ) {
    List<Employee_Time_Card_Account_Target__c> targets = [
      SELECT Actual_Visits__c, Target_Visit_Frequency__c, Frequency_Status__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE Employee_Time_Card__c = :timeCardId AND Account__c = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    return targets.isEmpty() ? null : targets[0];
  }

  private static NearbyPlanTarget buildCenterTarget(Account center, Id accountId, Decimal distanceKm) {
    NearbyPlanTarget row = new NearbyPlanTarget();
    row.accountId = accountId;
    row.name = center.Name;
    row.specialty = MedicalSpecialtyPicklist.getLabel(center.Specialty_1__c);
    row.latitude = center.BillingLatitude;
    row.longitude = center.BillingLongitude;
    row.distanceKm = distanceKm;
    row.actualVisits = 0;
    row.targetVisits = 0;
    row.visitGap = 0;
    row.recordTypeDeveloperName = center.RecordType == null
      ? null
      : center.RecordType.DeveloperName;
    row.recordTypeName = center.RecordType == null ? null : center.RecordType.Name;
    row.isCenterAccount = true;
    row.selectedByDefault = true;
    return row;
  }

  private static String paceStatusFromProjected(Decimal projectedPercent) {
    if (projectedPercent >= 100) {
      return 'ahead';
    }
    if (projectedPercent >= ON_TRACK_THRESHOLD) {
      return 'on_track';
    }
    if (projectedPercent >= CRITICAL_THRESHOLD) {
      return 'behind';
    }
    return 'critical';
  }

  private static Decimal haversineKm(
    Decimal lat1,
    Decimal lng1,
    Decimal lat2,
    Decimal lng2
  ) {
    Double r = 6371.0;
    Double dLat = toRadians(lat2 - lat1);
    Double dLng = toRadians(lng2 - lng1);
    Double a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
    Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Decimal.valueOf(r * c);
  }

  private static Double toRadians(Decimal value) {
    return (value == null ? 0 : value.doubleValue()) * Math.PI / 180.0;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private class NearbyPlanTargetDistanceComparator implements System.Comparator<NearbyPlanTarget> {
    public Integer compare(NearbyPlanTarget a, NearbyPlanTarget b) {
      if (a.distanceKm == b.distanceKm) {
        return 0;
      }
      return a.distanceKm < b.distanceKm ? -1 : 1;
    }
  }
}