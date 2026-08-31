public with sharing class FieldRepHomeController {
    private static final Integer DEFAULT_NBC_LIMIT = 5;
    private static final Integer MAX_ACCOUNT_ROWS = 200;

    public class ClassificationMetrics {
        @AuraEnabled public String classification;
        @AuraEnabled public Decimal visitCoveragePercent;
        @AuraEnabled public Decimal customerCoveragePercent;

        @AuraEnabled public Decimal lfPercent;
        @AuraEnabled public Decimal rfPercent;
        @AuraEnabled public Decimal mfPercent;
    }

    public class HomeMetrics {
        @AuraEnabled public Decimal visitCoveragePercent;
        @AuraEnabled public Decimal customerCoveragePercent;

        @AuraEnabled public Decimal lfPercentTotal;
        @AuraEnabled public Decimal rfPercentTotal;
        @AuraEnabled public Decimal mfPercentTotal;

        @AuraEnabled public List<ClassificationMetrics> byClassification;
    }

    public class AccountCoverageRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;
        @AuraEnabled public String city;

        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;

        // From Account_Territory_Fields__c (drill-down)
        @AuraEnabled public String potential;
        @AuraEnabled public String penetration;
        @AuraEnabled public String matrixRating;
        @AuraEnabled public String calculatedClassification;

        // From Employee_Time_Card_Account_Target__c
        @AuraEnabled public String potentialityOnTarget;

        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetVisits;
        @AuraEnabled public Decimal visitGap;
        @AuraEnabled public Decimal reachPercent;
        @AuraEnabled public String frequencyStatus;
        @AuraEnabled public Boolean isVisited;
    }

    public class NextBestCustomerRow {
        @AuraEnabled public Integer rank;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;

        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetVisits;
        @AuraEnabled public Decimal visitGap;

        @AuraEnabled public Boolean planned;
        @AuraEnabled public Boolean plannedToday;
        @AuraEnabled public Decimal score;

        // Drill-down fields (optional, used by UI)
        @AuraEnabled public String potential;
        @AuraEnabled public String penetration;
        @AuraEnabled public String calculatedClassification;
    }

    public class BadgeResult {
        @AuraEnabled public String badgeId;
        @AuraEnabled public Boolean earned;
        @AuraEnabled public Decimal progressPercent;
    }

    public class StreakInfo {
        @AuraEnabled public Integer activityStreak;
        @AuraEnabled public Integer coverageStreak;
    }

    public class PerformanceGamification {
        @AuraEnabled public String userFirstName;
        @AuraEnabled public StreakInfo streaks;
        @AuraEnabled public List<BadgeResult> badges;
    }

    public class LeaderboardEntry {
        @AuraEnabled public Integer rank;
        @AuraEnabled public String name;
        @AuraEnabled public Id userId;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Boolean isCurrentUser;
        @AuraEnabled public String badgeIcon;
    }

    public class PersonAbove {
        @AuraEnabled public String name;
        @AuraEnabled public Integer rank;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal gapPercent;
    }

    public class PerformanceRankings {
        @AuraEnabled public String buName;
        @AuraEnabled public Integer buRank;
        @AuraEnabled public Integer buTotal;
        @AuraEnabled public Integer companyRank;
        @AuraEnabled public Integer companyTotal;
        @AuraEnabled public Decimal myCoveragePercent;
        @AuraEnabled public List<LeaderboardEntry> top5InBu;
        @AuraEnabled public List<LeaderboardEntry> top5Company;
        @AuraEnabled public PersonAbove personAbove;
        @AuraEnabled public Boolean isFirstInBu;
    }

    private class RepCoverageSnapshot {
        public Id userId;
        public Decimal coveragePercent;
        public Integer rank;
        public String sortName;
    }

    private static final Integer LEADERBOARD_TOP_COUNT = 5;
    private static final List<String> LEADERBOARD_BADGE_ICONS = new List<String>{ '🥇', '🥈', '🥉' };

    private static final Integer DEFAULT_DAILY_CALL_TARGET = 8;
    private static final Integer STREAK_LOOKBACK_DAYS = 60;
    private static final Date MONDAY_REFERENCE = Date.newInstance(2024, 1, 1);

    @AuraEnabled
    public static HomeMetrics getHomeMetrics(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard == null) {
            return emptyHomeMetrics();
        }

        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT
                Account__c,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Is_Visited__c,
                Frequency_Status__c,
                Potentiality__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            WITH USER_MODE
        ];

        Decimal actualTotal = 0;
        Decimal targetTotal = 0;
        Integer visitedCount = 0;
        Integer totalCount = 0;

        Map<String, Decimal> actualByClass = new Map<String, Decimal>();
        Map<String, Decimal> targetByClass = new Map<String, Decimal>();
        Map<String, Integer> visitedCountByClass = new Map<String, Integer>();
        Map<String, Integer> totalCountByClass = new Map<String, Integer>();
        Map<String, Integer> lcfCountByClass = new Map<String, Integer>();
        Map<String, Integer> rcfCountByClass = new Map<String, Integer>();
        Map<String, Integer> mcfCountByClass = new Map<String, Integer>();

        for (Employee_Time_Card_Account_Target__c t : targets) {
            String clazz = normalizeClass(t.Potentiality__c);
            totalCount++;

            if (t.Is_Visited__c == true) {
                visitedCount++;
            }

            actualTotal += valueOrZero(t.Actual_Visits__c);
            targetTotal += valueOrZero(t.Target_Visit_Frequency__c);

            actualByClass.put(clazz, valueOrZero(actualByClass.get(clazz)) + valueOrZero(t.Actual_Visits__c));
            targetByClass.put(clazz, valueOrZero(targetByClass.get(clazz)) + valueOrZero(t.Target_Visit_Frequency__c));

            if (!totalCountByClass.containsKey(clazz)) {
                totalCountByClass.put(clazz, 0);
            }
            if (!visitedCountByClass.containsKey(clazz)) {
                visitedCountByClass.put(clazz, 0);
            }
            totalCountByClass.put(clazz, totalCountByClass.get(clazz) + 1);
            if (t.Is_Visited__c == true) {
                visitedCountByClass.put(clazz, visitedCountByClass.get(clazz) + 1);
            }

            String status = t.Frequency_Status__c;
            if (status == 'LCF') {
                lcfCountByClass.put(clazz, valueOrZeroInt(lcfCountByClass.get(clazz)) + 1);
            } else if (status == 'RCF') {
                rcfCountByClass.put(clazz, valueOrZeroInt(rcfCountByClass.get(clazz)) + 1);
            } else if (status == 'MCF') {
                mcfCountByClass.put(clazz, valueOrZeroInt(mcfCountByClass.get(clazz)) + 1);
            }
        }

        HomeMetrics result = new HomeMetrics();
        result.visitCoveragePercent = calculatePercent(actualTotal, targetTotal);
        result.customerCoveragePercent = calculatePercent(visitedCount, totalCount);

        Integer lcfTotal = 0;
        Integer rcfTotal = 0;
        Integer mcfTotal = 0;
        for (String clazz : new List<String>{ 'A', 'B', 'C', 'Other' }) {
            lcfTotal += valueOrZeroInt(lcfCountByClass.get(clazz));
            rcfTotal += valueOrZeroInt(rcfCountByClass.get(clazz));
            mcfTotal += valueOrZeroInt(mcfCountByClass.get(clazz));
        }
        result.lfPercentTotal = calculatePercent(lcfTotal, totalCount);
        result.rfPercentTotal = calculatePercent(rcfTotal, totalCount);
        result.mfPercentTotal = calculatePercent(mcfTotal, totalCount);

        List<ClassificationMetrics> byClass = new List<ClassificationMetrics>();
        for (String clazz : new List<String>{ 'A', 'B', 'C' }) {
            ClassificationMetrics row = new ClassificationMetrics();
            row.classification = clazz;
            row.visitCoveragePercent = calculatePercent(actualByClass.get(clazz), targetByClass.get(clazz));
            row.customerCoveragePercent = calculatePercent(visitedCountByClass.get(clazz), totalCountByClass.get(clazz));
            row.lfPercent = calculatePercent(valueOrZeroInt(lcfCountByClass.get(clazz)), valueOrZeroInt(totalCountByClass.get(clazz)));
            row.rfPercent = calculatePercent(valueOrZeroInt(rcfCountByClass.get(clazz)), valueOrZeroInt(totalCountByClass.get(clazz)));
            row.mfPercent = calculatePercent(valueOrZeroInt(mcfCountByClass.get(clazz)), valueOrZeroInt(totalCountByClass.get(clazz)));
            byClass.add(row);
        }

        result.byClassification = byClass;
        return result;
    }

    @AuraEnabled
    public static List<AccountCoverageRow> getAccountCoverageRows(
        Id contextUserId,
        String classificationFilter
    ) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard == null) {
            return new List<AccountCoverageRow>();
        }

        String normalizedFilter = normalizeClass(classificationFilter);
        Boolean isAll = String.isBlank(normalizedFilter) || normalizedFilter == 'Other';

        // Drill-down requires potential + penetration from Account_Territory_Fields__c.
        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT
                Account__c,
                Account__r.Name,
                Account__r.BillingLatitude,
                Account__r.BillingLongitude,
                Account__r.Specialty_1__c,
                Account__r.BillingCity,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Reach_Percent__c,
                Frequency_Status__c,
                Is_Visited__c,
                Potentiality__c,
                Account_Territory_Fields__r.Potential__c,
                Account_Territory_Fields__r.Penetration__c,
                Account_Territory_Fields__r.Matrix_Rating__c,
                Account_Territory_Fields__r.Classification__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            WITH USER_MODE
            ORDER BY Potentiality__c ASC, Account__r.Name ASC
            LIMIT :MAX_ACCOUNT_ROWS
        ];

        List<AccountCoverageRow> rows = new List<AccountCoverageRow>();
        for (Employee_Time_Card_Account_Target__c t : targets) {
            String clazz = normalizeClass(t.Potentiality__c);
            if (!isAll && clazz != normalizedFilter) {
                continue;
            }

            AccountCoverageRow row = new AccountCoverageRow();
            row.accountId = t.Account__c;
            row.accountName = t.Account__r != null ? t.Account__r.Name : null;
            row.specialty = t.Account__r != null
                ? MedicalSpecialtyPicklist.getLabel(t.Account__r.Specialty_1__c)
                : null;
            row.city = t.Account__r != null ? t.Account__r.BillingCity : null;
            row.latitude = t.Account__r != null ? t.Account__r.BillingLatitude : null;
            row.longitude = t.Account__r != null ? t.Account__r.BillingLongitude : null;

            // ATF drill-down fields
            Account_Territory_Fields__c atf = t.Account_Territory_Fields__r;
            row.potential = atf != null ? atf.Potential__c : null;
            row.penetration = atf != null ? String.valueOf(atf.Penetration__c) : null;
            row.matrixRating = atf != null ? atf.Matrix_Rating__c : null;
            row.calculatedClassification = atf != null && String.isNotBlank(atf.Classification__c) ? atf.Classification__c : clazz;

            // Time-card drill-down fields
            row.potentialityOnTarget = t.Potentiality__c;

            row.actualVisits = valueOrZero(t.Actual_Visits__c);
            row.targetVisits = valueOrZero(t.Target_Visit_Frequency__c);
            row.visitGap = row.targetVisits - row.actualVisits;
            row.reachPercent = PercentFieldHelper.toDisplayScale(t.Reach_Percent__c);
            row.frequencyStatus = t.Frequency_Status__c;
            row.isVisited = t.Is_Visited__c;

            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static FieldPlannerController.PlannerPayload getTodayPlan(Id contextUserId, Date planDate) {
        Id resolvedUserId = FieldPlannerController.resolveViewerContextUserId(contextUserId);
        // Match Field Rep Planner: use the client calendar date when provided so visit
        // windows align with browser-local day columns (toDateKey), not only Apex Date.today().
        Date today = planDate != null ? planDate : Date.today();
        return FieldPlannerController.getPlannerData(today, today, resolvedUserId);
    }

    @AuraEnabled
    public static List<NextBestCustomerRow> getNextBestCustomers(
        Id contextUserId,
        Integer limitSize
    ) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard == null) {
            return new List<NextBestCustomerRow>();
        }

        Integer limitValue = limitSize == null || limitSize <= 0 ? DEFAULT_NBC_LIMIT : Math.min(limitSize, 25);

        Date today = Date.today();
        Date endWeek = today.addDays(7);

        DateTime startTodayDt = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        DateTime endTodayDt = DateTime.newInstance(today, Time.newInstance(23, 59, 59, 0));
        DateTime endWeekDt = DateTime.newInstance(endWeek, Time.newInstance(23, 59, 59, 0));

        List<Employee_Time_Card_Account_Target__c> candidateTargets = [
            SELECT
                Account__c,
                Account__r.Name,
                Account__r.Specialty_1__c,
                Account__r.BillingLatitude,
                Account__r.BillingLongitude,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Frequency_Status__c,
                Potentiality__c,
                Account_Territory_Fields__r.Potential__c,
                Account_Territory_Fields__r.Penetration__c,
                Account_Territory_Fields__r.Matrix_Rating__c,
                Account_Territory_Fields__r.Classification__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE
                Employee_Time_Card__c = :timeCard.Id
                AND Frequency_Status__c = 'LCF'
                AND Account__c != NULL
                AND Account__r.BillingLatitude != NULL
                AND Account__r.BillingLongitude != NULL
            WITH USER_MODE
            ORDER BY Potentiality__c ASC, Target_Visit_Frequency__c DESC
            LIMIT 200
        ];

        if (candidateTargets.isEmpty()) {
            return new List<NextBestCustomerRow>();
        }

        Set<Id> accountIds = new Set<Id>();
        for (Employee_Time_Card_Account_Target__c t : candidateTargets) {
            accountIds.add(t.Account__c);
        }

        Map<Id, Boolean> plannedByAccount = new Map<Id, Boolean>();
        Map<Id, Boolean> plannedTodayByAccount = new Map<Id, Boolean>();
        for (Id accountId : accountIds) {
            plannedByAccount.put(accountId, false);
            plannedTodayByAccount.put(accountId, false);
        }

        for (Visit__c v : [
            SELECT
                Id,
                Account__c,
                Start_Date__c,
                Status__c
            FROM Visit__c
            WHERE
                Account__c IN :accountIds
                AND Assigned_To__c = :resolvedUserId
                AND Start_Date__c >= :startTodayDt
                AND Start_Date__c <= :endWeekDt
                AND Status__c IN ('Draft', 'Scheduled')
            WITH USER_MODE
        ]) {
            if (v.Account__c == null) {
                continue;
            }
            plannedByAccount.put(v.Account__c, true);
            if (v.Start_Date__c >= startTodayDt && v.Start_Date__c <= endTodayDt) {
                plannedTodayByAccount.put(v.Account__c, true);
            }
        }

        List<NextBestCustomerRow> ranked = new List<NextBestCustomerRow>();
        for (Employee_Time_Card_Account_Target__c t : candidateTargets) {
            NextBestCustomerRow row = new NextBestCustomerRow();
            row.accountId = t.Account__c;
            row.accountName = t.Account__r != null ? t.Account__r.Name : null;
            row.specialty = t.Account__r != null
                ? MedicalSpecialtyPicklist.getLabel(t.Account__r.Specialty_1__c)
                : null;

            row.actualVisits = valueOrZero(t.Actual_Visits__c);
            row.targetVisits = valueOrZero(t.Target_Visit_Frequency__c);
            row.visitGap = row.targetVisits - row.actualVisits;

            row.planned = plannedByAccount.get(t.Account__c);
            row.plannedToday = plannedTodayByAccount.get(t.Account__c);

            Account_Territory_Fields__c atf = t.Account_Territory_Fields__r;
            String calculatedClass = atf != null && String.isNotBlank(atf.Classification__c)
                ? atf.Classification__c
                : normalizeClass(t.Potentiality__c);
            row.calculatedClassification = calculatedClass;
            row.potential = atf != null ? atf.Potential__c : null;
            row.penetration = atf != null ? String.valueOf(atf.Penetration__c) : null;

            Decimal weight = classificationWeight(calculatedClass);
            Decimal score = weight + (row.visitGap * 15);
            if (t.Frequency_Status__c == 'LCF') {
                score += 40;
            }
            if (row.plannedToday == true) {
                score -= 50;
            }
            row.score = score;

            ranked.add(row);
        }

        // Apex list.sort with comparator is not consistently supported across orgs,
        // so do a simple selection sort for stable deterministic ordering.
        for (Integer x = 0; x < ranked.size(); x++) {
            Integer bestIndex = x;
            for (Integer y = x + 1; y < ranked.size(); y++) {
                if (ranked[y].score != null && (ranked[bestIndex].score == null || ranked[y].score > ranked[bestIndex].score)) {
                    bestIndex = y;
                }
            }
            if (bestIndex != x) {
                NextBestCustomerRow tmp = ranked[x];
                ranked[x] = ranked[bestIndex];
                ranked[bestIndex] = tmp;
            }
        }

        Integer i = 0;
        List<NextBestCustomerRow> limited = new List<NextBestCustomerRow>();
        for (NextBestCustomerRow row : ranked) {
            i++;
            if (i > limitValue) {
                break;
            }
            row.rank = i;
            limited.add(row);
        }

        return limited;
    }

    @AuraEnabled
    public static PerformanceGamification getPerformanceGamification(Id contextUserId, Date monthStart) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date resolvedMonth = monthStart != null ? monthStart.toStartOfMonth() : Date.today().toStartOfMonth();
        Date monthEnd = resolvedMonth.addMonths(1).addDays(-1);
        Date streakStart = Date.today().addDays(-STREAK_LOOKBACK_DAYS);

        HomeMetrics metrics = getHomeMetrics(contextUserId);
        Employee_Time_Card__c timeCard = getTimeCardForMonth(resolvedUserId, resolvedMonth);

        Set<Date> activeVisitDays = loadActiveVisitDays(resolvedUserId, streakStart, Date.today());
        Map<Date, Integer> visitsPerDay = loadVisitCountsByDay(resolvedUserId, streakStart, Date.today());
        Set<Date> workingDays = buildWorkingDaySet(timeCard, streakStart, Date.today());
        List<Employee_Time_Card_Day_Entry__c> dayEntries = loadDayEntries(timeCard, resolvedMonth, monthEnd);

        Integer dailyCallTarget = resolveDailyCallTarget(timeCard, workingDays, resolvedMonth, monthEnd);
        Integer activityStreak = computeConsecutiveStreak(activeVisitDays, workingDays, Date.today(), false);
        Integer coverageStreak = computeConsecutiveStreak(
            selectDaysMeetingTarget(visitsPerDay, workingDays, dailyCallTarget),
            workingDays,
            Date.today(),
            false
        );

        StreakInfo streaks = new StreakInfo();
        streaks.activityStreak = activityStreak;
        streaks.coverageStreak = coverageStreak;

        PerformanceGamification result = new PerformanceGamification();
        result.userFirstName = UserInfo.getFirstName();
        result.streaks = streaks;
        result.badges = buildBadgeResults(
            metrics,
            activityStreak,
            activeVisitDays,
            dayEntries,
            resolvedUserId,
            resolvedMonth,
            monthEnd
        );
        return result;
    }

    @AuraEnabled
    public static PerformanceRankings getPerformanceRankings(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date monthStart = Date.today().toStartOfMonth();

        Map<Id, Decimal> coverageByRep = loadVisitCoverageByRep(monthStart);
        Set<Id> companyRepIds = TerritoryHierarchyService.resolveScopedEmployeeIds(null, null, null);
        companyRepIds.add(resolvedUserId);

        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByUser =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>{ resolvedUserId });
        TerritoryHierarchyService.HierarchyLabels userLabels = labelsByUser.get(resolvedUserId);
        Id buId = userLabels != null ? userLabels.buTerritoryId : null;
        String buName = userLabels != null && String.isNotBlank(userLabels.businessUnit)
            ? userLabels.businessUnit
            : 'Your team';

        Set<Id> buRepIds = buId != null
            ? TerritoryHierarchyService.resolveScopedEmployeeIds(buId, null, null)
            : new Set<Id>(companyRepIds);
        buRepIds.add(resolvedUserId);

        Set<Id> allRepIds = new Set<Id>(companyRepIds);
        allRepIds.addAll(buRepIds);
        allRepIds.add(resolvedUserId);
        Map<Id, User> usersById = loadUsersForLeaderboard(allRepIds);

        List<RepCoverageSnapshot> companyRanked = buildRankedCoverageList(companyRepIds, coverageByRep, usersById);
        List<RepCoverageSnapshot> buRanked = buildRankedCoverageList(buRepIds, coverageByRep, usersById);

        RepCoverageSnapshot companySelf = findSnapshotForUser(companyRanked, resolvedUserId);
        RepCoverageSnapshot buSelf = findSnapshotForUser(buRanked, resolvedUserId);
        Decimal myCoverage = buSelf != null
            ? buSelf.coveragePercent
            : (companySelf != null ? companySelf.coveragePercent : 0);

        PerformanceRankings result = new PerformanceRankings();
        result.buName = buName;
        result.buRank = buSelf != null ? buSelf.rank : null;
        result.buTotal = buRanked.size();
        result.companyRank = companySelf != null ? companySelf.rank : null;
        result.companyTotal = companyRanked.size();
        result.myCoveragePercent = myCoverage;
        result.top5InBu = buildLeaderboardEntries(buRanked, usersById, resolvedUserId, LEADERBOARD_TOP_COUNT);
        result.top5Company = buildLeaderboardEntries(companyRanked, usersById, resolvedUserId, LEADERBOARD_TOP_COUNT);
        result.isFirstInBu = buSelf != null && buSelf.rank == 1;
        result.personAbove = buildPersonAbove(buRanked, buSelf, usersById);
        return result;
    }

    private static Map<Id, Decimal> loadVisitCoverageByRep(Date monthStart) {
        Map<Id, Decimal> coverageByRep = new Map<Id, Decimal>();
        for (AggregateResult aggregateRow : [
            SELECT
                Employee_Time_Card__r.Employee__c employeeId,
                SUM(Actual_Visits__c) actualSum,
                SUM(Target_Visit_Frequency__c) targetSum
            FROM Employee_Time_Card_Account_Target__c
            WHERE
                Employee_Time_Card__r.Time_Card_Month_Start_Date__c = :monthStart
                AND Employee_Time_Card__r.Employee__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Employee_Time_Card__r.Employee__c
        ]) {
            Id employeeId = (Id) aggregateRow.get('employeeId');
            Decimal actualSum = (Decimal) aggregateRow.get('actualSum');
            Decimal targetSum = (Decimal) aggregateRow.get('targetSum');
            coverageByRep.put(employeeId, calculatePercent(actualSum, targetSum));
        }
        return coverageByRep;
    }

    private static Map<Id, User> loadUsersForLeaderboard(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Id, FirstName, LastName, Name
            FROM User
            WHERE Id IN :userIds
            WITH SYSTEM_MODE
        ]);
    }

    private static List<RepCoverageSnapshot> buildRankedCoverageList(
        Set<Id> repIds,
        Map<Id, Decimal> coverageByRep,
        Map<Id, User> usersById
    ) {
        List<RepCoverageSnapshot> snapshots = new List<RepCoverageSnapshot>();
        if (repIds == null || repIds.isEmpty()) {
            return snapshots;
        }

        for (Id repId : repIds) {
            RepCoverageSnapshot snapshot = new RepCoverageSnapshot();
            snapshot.userId = repId;
            snapshot.coveragePercent = valueOrZero(coverageByRep.get(repId));
            User repUser = usersById.get(repId);
            snapshot.sortName = repUser != null ? repUser.Name : String.valueOf(repId);
            snapshots.add(snapshot);
        }

        for (Integer x = 0; x < snapshots.size(); x++) {
            Integer bestIndex = x;
            for (Integer y = x + 1; y < snapshots.size(); y++) {
                RepCoverageSnapshot candidate = snapshots[y];
                RepCoverageSnapshot best = snapshots[bestIndex];
                if (candidate.coveragePercent > best.coveragePercent) {
                    bestIndex = y;
                } else if (
                    candidate.coveragePercent == best.coveragePercent
                    && candidate.sortName < best.sortName
                ) {
                    bestIndex = y;
                }
            }
            if (bestIndex != x) {
                RepCoverageSnapshot tmp = snapshots[x];
                snapshots[x] = snapshots[bestIndex];
                snapshots[bestIndex] = tmp;
            }
        }

        for (Integer i = 0; i < snapshots.size(); i++) {
            snapshots[i].rank = i + 1;
        }
        return snapshots;
    }

    private static RepCoverageSnapshot findSnapshotForUser(List<RepCoverageSnapshot> ranked, Id userId) {
        for (RepCoverageSnapshot snapshot : ranked) {
            if (snapshot.userId == userId) {
                return snapshot;
            }
        }
        return null;
    }

    private static List<LeaderboardEntry> buildLeaderboardEntries(
        List<RepCoverageSnapshot> ranked,
        Map<Id, User> usersById,
        Id currentUserId,
        Integer limitSize
    ) {
        List<LeaderboardEntry> entries = new List<LeaderboardEntry>();
        Integer count = 0;
        for (RepCoverageSnapshot snapshot : ranked) {
            if (count >= limitSize) {
                break;
            }
            User repUser = usersById.get(snapshot.userId);
            LeaderboardEntry entry = new LeaderboardEntry();
            entry.rank = snapshot.rank;
            entry.userId = snapshot.userId;
            entry.name = formatLeaderboardName(repUser);
            entry.coveragePercent = snapshot.coveragePercent;
            entry.isCurrentUser = snapshot.userId == currentUserId;
            entry.badgeIcon = snapshot.rank != null && snapshot.rank <= LEADERBOARD_BADGE_ICONS.size()
                ? LEADERBOARD_BADGE_ICONS[snapshot.rank - 1]
                : null;
            entries.add(entry);
            count++;
        }
        return entries;
    }

    private static PersonAbove buildPersonAbove(
        List<RepCoverageSnapshot> ranked,
        RepCoverageSnapshot self,
        Map<Id, User> usersById
    ) {
        if (self == null || self.rank == null || self.rank <= 1) {
            return null;
        }

        RepCoverageSnapshot above = ranked[self.rank - 2];
        if (above == null) {
            return null;
        }

        PersonAbove result = new PersonAbove();
        result.rank = above.rank;
        result.name = formatLeaderboardName(usersById.get(above.userId));
        result.coveragePercent = above.coveragePercent;
        result.gapPercent = valueOrZero(above.coveragePercent) - valueOrZero(self.coveragePercent);
        return result;
    }

    private static String formatLeaderboardName(User repUser) {
        if (repUser == null) {
            return 'Rep';
        }
        String firstName = String.isNotBlank(repUser.FirstName) ? repUser.FirstName.trim() : '';
        String lastName = String.isNotBlank(repUser.LastName) ? repUser.LastName.trim() : '';
        if (String.isBlank(firstName) && String.isBlank(lastName)) {
            return String.isNotBlank(repUser.Name) ? repUser.Name : 'Rep';
        }
        if (String.isBlank(lastName)) {
            return firstName;
        }
        return firstName + ' ' + lastName.left(1).toUpperCase() + '.';
    }

    private static List<BadgeResult> buildBadgeResults(
        HomeMetrics metrics,
        Integer activityStreak,
        Set<Date> activeVisitDays,
        List<Employee_Time_Card_Day_Entry__c> dayEntries,
        Id userId,
        Date monthStart,
        Date monthEnd
    ) {
        Decimal visitCoverage = valueOrZero(metrics.visitCoveragePercent);
        Decimal classACoverage = 0;
        for (ClassificationMetrics row : metrics.byClassification) {
            if (row.classification == 'A') {
                classACoverage = valueOrZero(row.visitCoveragePercent);
                break;
            }
        }

        List<BadgeResult> badges = new List<BadgeResult>();
        badges.add(buildBadge('coverage_champion', visitCoverage >= 80, progressToward(visitCoverage, 80)));
        badges.add(buildBadge('on_target', visitCoverage >= 100, progressToward(visitCoverage, 100)));
        badges.add(buildBadge('class_a_ace', classACoverage >= 90, progressToward(classACoverage, 90)));
        badges.add(buildBadge('streak_starter', activityStreak >= 3, progressToward(activityStreak, 3)));
        badges.add(buildBadge('perfect_week', hasPerfectWeek(activeVisitDays), perfectWeekProgress(activeVisitDays)));
        Boolean earlyBird = hasEarlyBirdCheckIn(dayEntries, userId, monthStart, monthEnd);
        badges.add(buildBadge('early_bird', earlyBird, earlyBird ? 100 : 0));
        return badges;
    }

    private static BadgeResult buildBadge(String badgeId, Boolean earned, Decimal progressPercent) {
        BadgeResult badge = new BadgeResult();
        badge.badgeId = badgeId;
        badge.earned = earned;
        badge.progressPercent = earned ? 100 : Math.min(99, progressPercent == null ? 0 : progressPercent);
        return badge;
    }

    private static Decimal progressToward(Decimal current, Decimal target) {
        if (target == null || target <= 0) {
            return 0;
        }
        return Math.min(100, (valueOrZero(current) / target) * 100);
    }

    private static Decimal progressToward(Integer current, Integer target) {
        return progressToward(Decimal.valueOf(current), Decimal.valueOf(target));
    }

    private static Boolean hasPerfectWeek(Set<Date> activeVisitDays) {
        Date monday = getWeekMonday(Date.today());
        for (Integer offset = 0; offset < 5; offset++) {
            if (!activeVisitDays.contains(monday.addDays(offset))) {
                return false;
            }
        }
        return true;
    }

    private static Decimal perfectWeekProgress(Set<Date> activeVisitDays) {
        Date monday = getWeekMonday(Date.today());
        Integer daysWithVisits = 0;
        for (Integer offset = 0; offset < 5; offset++) {
            if (activeVisitDays.contains(monday.addDays(offset))) {
                daysWithVisits++;
            }
        }
        return progressToward(daysWithVisits, 5);
    }

    private static Boolean hasEarlyBirdCheckIn(
        List<Employee_Time_Card_Day_Entry__c> dayEntries,
        Id userId,
        Date monthStart,
        Date monthEnd
    ) {
        if (dayEntryHasCheckInField() && dayEntries != null) {
            for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
                if (isBeforeNineAm(entry.Check_In_Time__c)) {
                    return true;
                }
            }
        }
        return hasEarlyBirdVisitStart(userId, monthStart, monthEnd);
    }

    private static Boolean hasEarlyBirdVisitStart(Id userId, Date monthStart, Date monthEnd) {
        DateTime rangeStart = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime rangeEnd = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        for (Visit__c visit : [
            SELECT Start_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :userId
                AND Status__c IN ('Draft', 'Scheduled', 'Completed')
                AND Start_Date__c >= :rangeStart
                AND Start_Date__c <= :rangeEnd
            WITH USER_MODE
        ]) {
            if (isBeforeNineAm(visit.Start_Date__c)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isBeforeNineAm(DateTime value) {
        if (value == null) {
            return false;
        }
        Time checkIn = value.time();
        return checkIn.hour() < 9;
    }

    private static Set<Date> selectDaysMeetingTarget(
        Map<Date, Integer> visitsPerDay,
        Set<Date> workingDays,
        Integer dailyCallTarget
    ) {
        Set<Date> result = new Set<Date>();
        if (visitsPerDay == null) {
            return result;
        }
        for (Date day : visitsPerDay.keySet()) {
            if (workingDays.contains(day) && visitsPerDay.get(day) >= dailyCallTarget) {
                result.add(day);
            }
        }
        return result;
    }

    private static Integer computeConsecutiveStreak(
        Set<Date> qualifyingDays,
        Set<Date> workingDays,
        Date asOfDate,
        Boolean requireToday
    ) {
        Integer streak = 0;
        Date cursor = asOfDate;

        if (!requireToday && workingDays.contains(cursor) && !qualifyingDays.contains(cursor)) {
            cursor = cursor.addDays(-1);
        }

        Date streakStart = asOfDate.addDays(-STREAK_LOOKBACK_DAYS);
        while (cursor >= streakStart) {
            if (!workingDays.contains(cursor)) {
                cursor = cursor.addDays(-1);
                continue;
            }
            if (!qualifyingDays.contains(cursor)) {
                break;
            }
            streak++;
            cursor = cursor.addDays(-1);
        }
        return streak;
    }

    private static Integer resolveDailyCallTarget(
        Employee_Time_Card__c timeCard,
        Set<Date> workingDays,
        Date monthStart,
        Date monthEnd
    ) {
        Integer workingDaysInMonth = countWorkingDaysInRange(workingDays, monthStart, monthEnd);
        if (
            timeCard != null
            && hasAccessibleField(Employee_Time_Card__c.SObjectType, 'Visit_Target__c')
            && timeCard.Visit_Target__c != null
            && timeCard.Visit_Target__c > 0
            && workingDaysInMonth > 0
        ) {
            return Math.max(1, Integer.valueOf(Math.ceil(timeCard.Visit_Target__c / workingDaysInMonth)));
        }
        return DEFAULT_DAILY_CALL_TARGET;
    }

    private static Integer countWorkingDaysInRange(Set<Date> workingDays, Date rangeStart, Date rangeEnd) {
        Integer count = 0;
        for (Date day = rangeStart; day <= rangeEnd; day = day.addDays(1)) {
            if (workingDays.contains(day)) {
                count++;
            }
        }
        return count;
    }

    private static Set<Date> buildWorkingDaySet(Employee_Time_Card__c timeCard, Date rangeStart, Date rangeEnd) {
        Set<Date> workingDays = new Set<Date>();
        Map<Date, Employee_Time_Card_Day_Entry__c> entriesByDate = new Map<Date, Employee_Time_Card_Day_Entry__c>();
        if (timeCard != null) {
            for (Employee_Time_Card_Day_Entry__c entry : loadDayEntries(timeCard, rangeStart, rangeEnd)) {
                if (entry.Date__c != null) {
                    entriesByDate.put(entry.Date__c, entry);
                }
            }
        }

        for (Date day = rangeStart; day <= rangeEnd; day = day.addDays(1)) {
            if (entriesByDate.containsKey(day)) {
                if (isWorkingDayEntry(entriesByDate.get(day))) {
                    workingDays.add(day);
                }
            } else if (isWeekday(day)) {
                workingDays.add(day);
            }
        }
        return workingDays;
    }

    private static Boolean isWorkingDayEntry(Employee_Time_Card_Day_Entry__c entry) {
        if (entry == null) {
            return false;
        }
        if (
            hasAccessibleField(Employee_Time_Card_Day_Entry__c.SObjectType, 'Day_Definition__c')
            && entry.Day_Definition__c == 'Weekend Day'
        ) {
            return false;
        }
        if (hasAccessibleField(Employee_Time_Card_Day_Entry__c.SObjectType, 'Calendar_Working_Days__c')) {
            return valueOrZero(entry.Calendar_Working_Days__c) > 0;
        }
        return entry.Date__c != null && isWeekday(entry.Date__c);
    }

    private static Boolean isWeekday(Date day) {
        Integer dayIndex = Math.mod(MONDAY_REFERENCE.daysBetween(day), 7);
        return dayIndex >= 0 && dayIndex <= 4;
    }

    private static Date getWeekMonday(Date day) {
        Integer dayIndex = Math.mod(MONDAY_REFERENCE.daysBetween(day), 7);
        return day.addDays(-dayIndex);
    }

    private static Set<Date> loadActiveVisitDays(Id userId, Date rangeStart, Date rangeEnd) {
        Set<Date> activeDays = new Set<Date>();
        for (Visit__c visit : queryVisitsForGamification(userId, rangeStart, rangeEnd)) {
            Date visitDate = resolveVisitDate(visit);
            if (visitDate != null) {
                activeDays.add(visitDate);
            }
        }
        return activeDays;
    }

    private static Map<Date, Integer> loadVisitCountsByDay(Id userId, Date rangeStart, Date rangeEnd) {
        Map<Date, Integer> counts = new Map<Date, Integer>();
        for (Visit__c visit : queryVisitsForGamification(userId, rangeStart, rangeEnd)) {
            Date visitDate = resolveVisitDate(visit);
            if (visitDate == null) {
                continue;
            }
            counts.put(visitDate, valueOrZeroInt(counts.get(visitDate)) + 1);
        }
        return counts;
    }

    private static List<Visit__c> queryVisitsForGamification(Id userId, Date rangeStart, Date rangeEnd) {
        DateTime startDt = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(rangeEnd, Time.newInstance(23, 59, 59, 0));
        return [
            SELECT Visit_Date__c, Start_Date__c, Status__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :userId
                AND Status__c IN ('Draft', 'Scheduled', 'Completed')
                AND (
                    (Visit_Date__c >= :startDt AND Visit_Date__c <= :endDt)
                    OR (Start_Date__c >= :startDt AND Start_Date__c <= :endDt)
                )
            WITH USER_MODE
        ];
    }

    private static List<Employee_Time_Card_Day_Entry__c> loadDayEntries(
        Employee_Time_Card__c timeCard,
        Date rangeStart,
        Date rangeEnd
    ) {
        if (timeCard == null) {
            return new List<Employee_Time_Card_Day_Entry__c>();
        }

        List<String> fields = new List<String>{ 'Date__c' };
        addDayEntryFieldIfPresent(fields, 'Check_In_Time__c');
        addDayEntryFieldIfPresent(fields, 'Day_Definition__c');
        addDayEntryFieldIfPresent(fields, 'Calendar_Working_Days__c');
        addDayEntryFieldIfPresent(fields, 'Total_Visits__c');

        Id timeCardId = timeCard.Id;
        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM Employee_Time_Card_Day_Entry__c' +
            ' WHERE Employee_Time_Card__c = :timeCardId' +
            ' AND Date__c >= :rangeStart' +
            ' AND Date__c <= :rangeEnd' +
            ' WITH USER_MODE';
        return Database.query(soql);
    }

    private static void addDayEntryFieldIfPresent(List<String> fields, String fieldApiName) {
        if (hasAccessibleField(Employee_Time_Card_Day_Entry__c.SObjectType, fieldApiName)) {
            fields.add(fieldApiName);
        }
    }

    private static Boolean dayEntryHasCheckInField() {
        return hasAccessibleField(
            Employee_Time_Card_Day_Entry__c.SObjectType,
            'Check_In_Time__c'
        );
    }

    private static Date resolveVisitDate(Visit__c visit) {
        if (visit.Visit_Date__c != null) {
            return visit.Visit_Date__c.date();
        }
        if (visit.Start_Date__c != null) {
            return visit.Start_Date__c.date();
        }
        return null;
    }

    private static Employee_Time_Card__c getTimeCardForMonth(Id employeeId, Date monthStart) {
        List<String> fields = new List<String>{ 'Id', 'Time_Card_Month_Start_Date__c', 'Time_Card_Month_End_Date__c' };
        if (hasAccessibleField(Employee_Time_Card__c.SObjectType, 'Visit_Target__c')) {
            fields.add('Visit_Target__c');
        }

        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM Employee_Time_Card__c' +
            ' WHERE Employee__c = :employeeId' +
            ' AND Time_Card_Month_Start_Date__c = :monthStart' +
            ' WITH USER_MODE' +
            ' LIMIT 1';
        List<Employee_Time_Card__c> cards = Database.query(soql);
        return cards.isEmpty() ? null : cards[0];
    }

    private static Decimal calculatePercent(Decimal numerator, Decimal denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (numerator / denominator) * 100;
    }

    private static Decimal calculatePercent(Integer numerator, Integer denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (Decimal.valueOf(numerator) / Decimal.valueOf(denominator)) * 100;
    }

    private static Decimal valueOrZero(Decimal d) {
        return d == null ? 0 : d;
    }

    private static Integer valueOrZeroInt(Integer i) {
        return i == null ? 0 : i;
    }

    private static String normalizeClass(String value) {
        if (String.isBlank(value)) {
            return 'Other';
        }
        String v = value.trim().toUpperCase();
        if (v == 'A' || v == 'B' || v == 'C') {
            return v;
        }
        return 'Other';
    }

    private static Decimal classificationWeight(String clazz) {
        String c = normalizeClass(clazz);
        if (c == 'A') {
            return 100;
        }
        if (c == 'B') {
            return 60;
        }
        if (c == 'C') {
            return 30;
        }
        return 10;
    }

    private static Employee_Time_Card__c getCurrentTimeCard(Id employeeId) {
        Date monthStart = Date.today().toStartOfMonth();
        List<Employee_Time_Card__c> cards = [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Employee__c = :employeeId
                AND Time_Card_Month_Start_Date__c = :monthStart
            WITH USER_MODE
            LIMIT 1
        ];
        return cards.isEmpty() ? null : cards[0];
    }

    private static Employee_Time_Card__c resolveOrEnsureTimeCard(Id employeeId) {
        Employee_Time_Card__c timeCard = getCurrentTimeCard(employeeId);
        if (timeCard != null) {
            return timeCard;
        }
        try {
            Date monthStart = Date.today().toStartOfMonth();
            timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(employeeId, monthStart);
            if (timeCard != null) {
                EmployeeTimeCardService.syncAccountTargets(timeCard.Id);
            }
            return timeCard;
        } catch (Exception e) {
            return null;
        }
    }

    private static HomeMetrics emptyHomeMetrics() {
        HomeMetrics result = new HomeMetrics();
        result.visitCoveragePercent = 0;
        result.customerCoveragePercent = 0;
        result.lfPercentTotal = 0;
        result.rfPercentTotal = 0;
        result.mfPercentTotal = 0;

        List<ClassificationMetrics> byClass = new List<ClassificationMetrics>();
        for (String clazz : new List<String>{ 'A', 'B', 'C' }) {
            ClassificationMetrics row = new ClassificationMetrics();
            row.classification = clazz;
            row.visitCoveragePercent = 0;
            row.customerCoveragePercent = 0;
            row.lfPercent = 0;
            row.rfPercent = 0;
            row.mfPercent = 0;
            byClass.add(row);
        }
        result.byClassification = byClass;
        return result;
    }

    private static Id resolveUserId(Id requestedUserId) {
        if (requestedUserId == null || requestedUserId == UserInfo.getUserId()) {
            return UserInfo.getUserId();
        }
        throw new AuraHandledException('You cannot view home metrics for other users.');
    }

    private static Boolean hasAccessibleField(Schema.SObjectType sobjectType, String fieldApiName) {
        if (sobjectType == null || String.isBlank(fieldApiName)) {
            return false;
        }
        Schema.SObjectField fieldToken = sobjectType.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        return fieldToken != null && fieldToken.getDescribe().isAccessible();
    }
}

