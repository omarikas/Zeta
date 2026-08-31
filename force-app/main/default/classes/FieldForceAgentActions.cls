public with sharing class FieldForceAgentActions {
    private static final Integer MAX_VISIT_LINES = 12;
    private static final Integer MAX_NBC_LINES = 5;
    private static final Integer MAX_NEARBY_LINES = 5;
    private static final Integer MAX_AFFILIATION_LINES = 12;
    private static final Integer MAX_PRODUCT_LINES = 12;
    private static final Integer MAX_ACCOUNTS_TAB_ROWS = 8;
    private static final Integer MAX_CLASSIFICATION_BUCKETS = 8;

    public class HomeDashboardRequest {
        @InvocableVariable(
            label='Context User Id'
            description='Optional user id. Defaults to the running user.'
        )
        public Id contextUserId;
    }

    public class PlannerWeekRequest {
        @InvocableVariable(
            label='Context User Id'
            description='Optional user id. Defaults to the running user.'
        )
        public Id contextUserId;

        @InvocableVariable(
            label='Week Start Date'
            description='Optional Monday of the planner week. Defaults to the current week.'
        )
        public Date weekStartDate;
    }

    public class AccountFieldRequest {
        @InvocableVariable(
            required=true
            label='Account Id'
            description='The Account record to summarize. Use the current record id when the user is on an account page.'
        )
        public Id accountId;
    }

    public class AccountsTabRequest {
        @InvocableVariable(
            label='Context User Id'
            description='Optional user id. Defaults to the running user.'
        )
        public Id contextUserId;

        @InvocableVariable(
            label='Scope'
            description='Plan-cycle scope: in, out, or both. Defaults to in.'
        )
        public String scope;
    }

    public class VisitCallRequest {
        @InvocableVariable(
            required=true
            label='Visit Id'
            description='The Visit__c record to summarize. Use the current record id when the user is on a visit page.'
        )
        public Id visitId;
    }

    public class AffiliationRequest {
        @InvocableVariable(
            label='Account Id'
            description='Account whose affiliations to summarize. Prefer this when on an Account page.'
        )
        public Id accountId;

        @InvocableVariable(
            label='Visit Id'
            description='Optional Visit__c id. When provided without accountId, affiliations for the visit account are summarized.'
        )
        public Id visitId;
    }

    public class TerritoryProductRequest {
        @InvocableVariable(
            label='Context User Id'
            description='Optional user id. Defaults to the running user.'
        )
        public Id contextUserId;

        @InvocableVariable(
            label='Account Id'
            description='Optional account id to include product ratings (ATPF) for that account.'
        )
        public Id accountId;
    }

    public class BriefResult {
        @InvocableVariable(label='Summary' description='Field-force context for the agent to answer with.')
        public String summary;
    }

    public static List<BriefResult> buildHomeDashboardBrief(List<HomeDashboardRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (HomeDashboardRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildHomeSummary(request == null ? null : request.contextUserId);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildPlannerWeekBrief(List<PlannerWeekRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (PlannerWeekRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildPlannerSummary(request);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildAccountFieldBrief(List<AccountFieldRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (AccountFieldRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildAccountSummary(request == null ? null : request.accountId);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildAccountsTabBrief(List<AccountsTabRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (AccountsTabRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildAccountsTabSummary(request);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildVisitCallBrief(List<VisitCallRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (VisitCallRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildVisitSummary(request == null ? null : request.visitId);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildAffiliationBrief(List<AffiliationRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (AffiliationRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildAffiliationSummary(request);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildTerritoryProductBrief(List<TerritoryProductRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (TerritoryProductRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildTerritoryProductSummary(request);
            results.add(result);
        }
        return results;
    }

    private static String buildHomeSummary(Id contextUserId) {
        Id userId = resolveUserId(contextUserId);
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        List<String> lines = new List<String>();
        lines.add('Field Rep Home dashboard context:');

        Employee_Time_Card__c timeCard = findTimeCard(userId, monthStart);
        if (timeCard == null) {
            lines.add('No active plan cycle (employee time card) for this month.');
        } else {
            List<Employee_Time_Card_Account_Target__c> targets = queryTargets(timeCard.Id, null, 200);
            Integer inPlan = targets.size();
            Integer visited = 0;
            Decimal targetVisits = 0;
            Decimal actualVisits = 0;
            Map<String, Integer> classCounts = new Map<String, Integer>();
            List<String> nbcLines = new List<String>();

            for (Employee_Time_Card_Account_Target__c target : targets) {
                Decimal targetFreq = nvl(target.Target_Visit_Frequency__c);
                Decimal actual = nvl(target.Actual_Visits__c);
                targetVisits += targetFreq;
                actualVisits += actual;
                if (actual > 0 || target.Is_Visited__c == true) {
                    visited++;
                }
                String classification = resolveTargetClassification(target);
                Integer classCount = classCounts.containsKey(classification) ? classCounts.get(classification) : 0;
                classCounts.put(classification, classCount + 1);

                Decimal gap = Math.max(0, targetFreq - actual);
                if (gap > 0 && nbcLines.size() < MAX_NBC_LINES) {
                    nbcLines.add(
                        safeString(target.Account__r.Name) +
                        ' (gap ' +
                        formatDecimal(gap) +
                        ', class ' +
                        classification +
                        ')'
                    );
                }
            }

            Decimal visitCoverage = targetVisits == 0 ? 0 : (actualVisits / targetVisits) * 100;
            Decimal customerCoverage = inPlan == 0 ? 0 : (Decimal.valueOf(visited) / Decimal.valueOf(inPlan)) * 100;
            lines.add(
                'Plan-cycle coverage: visit coverage ' +
                formatPercent(visitCoverage) +
                ', customer coverage ' +
                formatPercent(customerCoverage) +
                ', in-plan accounts ' +
                inPlan +
                '.'
            );
            if (!classCounts.isEmpty()) {
                lines.add('By classification — ' + joinCountMap(classCounts) + '.');
            }
            if (!nbcLines.isEmpty()) {
                lines.add('Top next-best customers: ' + String.join(nbcLines, '; ') + '.');
            } else {
                lines.add('No next-best customer recommendations are available right now.');
            }
        }

        List<Visit__c> todayVisits = queryVisitsForUser(userId, Date.today(), Date.today(), MAX_VISIT_LINES);
        lines.add('Today: ' + todayVisits.size() + ' visit(s) in range.');
        if (!todayVisits.isEmpty()) {
            lines.add('Up next today: ' + formatVisitList(todayVisits) + '.');
        }
        return String.join(lines, '\n');
    }

    private static String buildPlannerSummary(PlannerWeekRequest request) {
        Id userId = resolveUserId(request == null ? null : request.contextUserId);
        Date weekStart = request == null || request.weekStartDate == null
            ? startOfWeek(Date.today())
            : request.weekStartDate;
        Date weekEnd = weekStart.addDays(6);

        List<String> lines = new List<String>();
        lines.add(
            'Field Planner context for week ' +
            formatDate(weekStart) +
            ' to ' +
            formatDate(weekEnd) +
            ':'
        );

        List<Visit__c> visits = queryVisitsForUser(userId, weekStart, weekEnd, 200);
        lines.add('Scheduled visits: ' + visits.size() + '.');

        if (visits.isEmpty()) {
            lines.add('No visits are scheduled this week yet.');
        } else {
            Map<String, Integer> visitsByDay = new Map<String, Integer>();
            for (Visit__c visit : visits) {
                Date visitDay = visit.Start_Date__c == null ? null : visit.Start_Date__c.date();
                String dayKey = formatDate(visitDay);
                Integer dayCount = visitsByDay.containsKey(dayKey) ? visitsByDay.get(dayKey) : 0;
                visitsByDay.put(dayKey, dayCount + 1);
            }
            lines.add('Visits by day — ' + joinCountMap(visitsByDay) + '.');
            lines.add('Upcoming visits: ' + formatVisitList(limitVisits(visits, MAX_VISIT_LINES)) + '.');
        }

        Employee_Time_Card__c timeCard = findTimeCard(userId, Date.today().toStartOfMonth());
        if (timeCard != null) {
            Set<Id> plannedAccountIds = new Set<Id>();
            for (Visit__c visit : visits) {
                if (visit.Account__c != null) {
                    plannedAccountIds.add(visit.Account__c);
                }
            }
            List<String> gapLines = new List<String>();
            for (Employee_Time_Card_Account_Target__c target : queryTargets(timeCard.Id, null, 100)) {
                if (plannedAccountIds.contains(target.Account__c)) {
                    continue;
                }
                Decimal gap = Math.max(0, nvl(target.Target_Visit_Frequency__c) - nvl(target.Actual_Visits__c));
                if (gap <= 0) {
                    continue;
                }
                gapLines.add(safeString(target.Account__r.Name) + ' (gap ' + formatDecimal(gap) + ')');
                if (gapLines.size() >= MAX_NBC_LINES) {
                    break;
                }
            }
            if (!gapLines.isEmpty()) {
                lines.add('Unplanned high-priority accounts to consider: ' + String.join(gapLines, '; ') + '.');
            }
        }

        return String.join(lines, '\n');
    }

    private static String buildAccountSummary(Id accountId) {
        if (accountId == null) {
            return 'Account id is required to summarize field-force account context.';
        }

        List<Account> accounts = [
            SELECT Name
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return 'Account not found for id ' + accountId + '.';
        }

        List<String> lines = new List<String>();
        lines.add('Account field context for ' + safeString(accounts[0].Name) + ':');
        appendAccountClassificationLines(lines, accountId);
        appendAccountProductRatingLines(lines, accountId);

        Employee_Time_Card__c timeCard = findTimeCard(UserInfo.getUserId(), Date.today().toStartOfMonth());
        if (timeCard == null) {
            lines.add('No active plan-cycle target is assigned to this account.');
        } else {
            List<Employee_Time_Card_Account_Target__c> targets = queryTargets(timeCard.Id, accountId, 1);
            if (targets.isEmpty()) {
                lines.add('No active plan-cycle target is assigned to this account.');
            } else {
                Employee_Time_Card_Account_Target__c target = targets[0];
                Decimal targetVisits = nvl(target.Target_Visit_Frequency__c);
                Decimal actualVisits = nvl(target.Actual_Visits__c);
                Decimal gap = Math.max(0, targetVisits - actualVisits);
                lines.add(
                    'Plan-cycle target ' +
                    formatDecimal(targetVisits) +
                    ' visits, actual ' +
                    formatDecimal(actualVisits) +
                    ', gap ' +
                    formatDecimal(gap) +
                    ', reach ' +
                    formatPercent(target.Reach_Percent__c) +
                    ', frequency status ' +
                    safeString(target.Frequency_Status__c) +
                    '.'
                );
            }
        }

        List<Visit__c> upcoming = [
            SELECT Start_Date__c, Status__c
            FROM Visit__c
            WHERE Account__c = :accountId AND Start_Date__c >= :Datetime.now()
            ORDER BY Start_Date__c ASC
            LIMIT :MAX_VISIT_LINES
        ];
        if (upcoming.isEmpty()) {
            lines.add('No upcoming visits are scheduled for this account.');
        } else {
            List<String> visitLines = new List<String>();
            for (Visit__c visit : upcoming) {
                visitLines.add(formatDateTime(visit.Start_Date__c) + ' — ' + safeString(visit.Status__c));
            }
            lines.add('Upcoming visits: ' + String.join(visitLines, '; ') + '.');
        }

        return String.join(lines, '\n');
    }

    private static String buildAccountsTabSummary(AccountsTabRequest request) {
        Id userId = resolveUserId(request == null ? null : request.contextUserId);
        String scope = request == null || String.isBlank(request.scope) ? 'in' : request.scope.trim().toLowerCase();
        if (scope != 'in' && scope != 'out' && scope != 'both') {
            scope = 'in';
        }

        Date monthStart = Date.today().toStartOfMonth();
        List<String> lines = new List<String>();
        lines.add('Accounts tab plan-cycle context for ' + formatDate(monthStart) + ':');

        Employee_Time_Card__c timeCard = findTimeCard(userId, monthStart);
        if (timeCard == null) {
            lines.add('No active employee time card / plan cycle was found for this user.');
            return String.join(lines, '\n');
        }

        List<Employee_Time_Card_Account_Target__c> targets = queryTargets(timeCard.Id, null, 500);
        Integer behindPace = 0;
        Map<String, Integer> classCounts = new Map<String, Integer>();
        List<String> behindLines = new List<String>();
        List<String> topLines = new List<String>();

        for (Employee_Time_Card_Account_Target__c target : targets) {
            String classification = resolveTargetClassification(target);
            Integer classCount = classCounts.containsKey(classification) ? classCounts.get(classification) : 0;
            classCounts.put(classification, classCount + 1);

            Decimal targetVisits = nvl(target.Target_Visit_Frequency__c);
            Decimal actualVisits = nvl(target.Actual_Visits__c);
            Decimal gap = Math.max(0, targetVisits - actualVisits);
            Boolean behind = gap > 0 && (String.isBlank(target.Frequency_Status__c)
                || target.Frequency_Status__c.toLowerCase().contains('behind')
                || actualVisits < (targetVisits * 0.5));

            if (behind) {
                behindPace++;
                if (behindLines.size() < MAX_ACCOUNTS_TAB_ROWS) {
                    behindLines.add(
                        safeString(target.Account__r.Name) +
                        ' (gap ' +
                        formatDecimal(gap) +
                        ', class ' +
                        classification +
                        ')'
                    );
                }
            }

            if (topLines.size() < MAX_ACCOUNTS_TAB_ROWS) {
                topLines.add(
                    safeString(target.Account__r.Name) +
                    ' (class ' +
                    classification +
                    ', gap ' +
                    formatDecimal(gap) +
                    ', status ' +
                    safeString(target.Frequency_Status__c) +
                    ')'
                );
            }
        }

        lines.add(
            'In plan: ' +
            targets.size() +
            ', behind pace (heuristic): ' +
            behindPace +
            ' (scope=' +
            scope +
            ').'
        );
        if (!classCounts.isEmpty()) {
            lines.add('Classification mix — ' + joinCountMap(classCounts) + '.');
        }
        if (!behindLines.isEmpty()) {
            lines.add('Behind-pace accounts: ' + String.join(behindLines, '; ') + '.');
        } else {
            lines.add('No behind-pace accounts detected in the current plan cycle.');
        }
        if (!topLines.isEmpty()) {
            lines.add('Priority accounts: ' + String.join(topLines, '; ') + '.');
        }
        return String.join(lines, '\n');
    }

    private static String buildVisitSummary(Id visitId) {
        if (visitId == null) {
            return 'Visit id is required to summarize call-report context.';
        }

        List<Visit__c> visits = [
            SELECT
                Name,
                Status__c,
                Visit_Type__c,
                Start_Date__c,
                Visit_Objective__c,
                Account__c,
                Account__r.Name,
                Account__r.RecordType.Name
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            return 'Visit not found for id ' + visitId + '.';
        }

        Visit__c visit = visits[0];
        List<String> lines = new List<String>();
        lines.add('Visit call context for ' + safeString(visit.Name) + ':');
        lines.add(
            'Account ' +
            safeString(visit.Account__r.Name) +
            ' (' +
            safeString(visit.Account__r.RecordType.Name) +
            '), status ' +
            safeString(visit.Status__c) +
            ', type ' +
            safeString(visit.Visit_Type__c) +
            ', start ' +
            formatDateTime(visit.Start_Date__c) +
            '.'
        );
        if (String.isNotBlank(visit.Visit_Objective__c)) {
            lines.add('Objective: ' + visit.Visit_Objective__c);
        }
        if (visit.Account__c != null) {
            appendAccountClassificationLines(lines, visit.Account__c);
        }

        List<Visit_Attendee__c> attendees = [
            SELECT Account__r.Name, Role__c, Is_Primary__c
            FROM Visit_Attendee__c
            WHERE Visit__c = :visitId
            ORDER BY Display_Order__c NULLS LAST, CreatedDate ASC
            LIMIT :MAX_VISIT_LINES
        ];
        if (attendees.isEmpty()) {
            lines.add('No attendees captured yet.');
        } else {
            List<String> attendeeLines = new List<String>();
            for (Visit_Attendee__c attendee : attendees) {
                attendeeLines.add(
                    safeString(attendee.Account__r.Name) +
                    (attendee.Is_Primary__c == true ? ' (primary)' : '') +
                    (String.isBlank(attendee.Role__c) ? '' : ' — ' + attendee.Role__c)
                );
            }
            lines.add('Attendees: ' + String.join(attendeeLines, '; ') + '.');
        }

        List<Visit_Product_Detail__c> products = [
            SELECT Product2__r.Name
            FROM Visit_Product_Detail__c
            WHERE Visit__c = :visitId
            ORDER BY Display_Order__c NULLS LAST, CreatedDate ASC
            LIMIT :MAX_PRODUCT_LINES
        ];
        if (products.isEmpty()) {
            lines.add('No products detailed yet on this visit.');
        } else {
            List<String> productLines = new List<String>();
            for (Visit_Product_Detail__c product : products) {
                productLines.add(safeString(product.Product2__r.Name));
            }
            lines.add('Products detailed: ' + String.join(productLines, '; ') + '.');
        }

        Set<Id> productIds = getPtaProductIds(expandTerritoryHierarchy(getUserTerritoryIds(UserInfo.getUserId())));
        if (!productIds.isEmpty()) {
            List<String> alignedLines = new List<String>();
            Integer count = 0;
            for (Product2 product : [
                SELECT Name
                FROM Product2
                WHERE Id IN :productIds AND IsActive = TRUE
               
                ORDER BY Name
                LIMIT :MAX_PRODUCT_LINES
            ]) {
                alignedLines.add(product.Name);
                count++;
            }
            if (count > 0) {
                lines.add('Territory-aligned products to consider: ' + String.join(alignedLines, '; ') + '.');
            }
        }

        Integer sampleCount = [
            SELECT COUNT()
            FROM Visit_Sample__c
            WHERE Visit__c = :visitId
        ];
        if (sampleCount > 0) {
            lines.add('Samples recorded: ' + sampleCount + '.');
        }

        if (visit.Account__c != null) {
            lines.add(buildAffiliationSummaryForAccount(visit.Account__c));
        }
        return String.join(lines, '\n');
    }

    private static String buildAffiliationSummary(AffiliationRequest request) {
        Id accountId = request == null ? null : request.accountId;
        if (accountId == null && request != null && request.visitId != null) {
            List<Visit__c> visits = [
                SELECT Account__c
                FROM Visit__c
                WHERE Id = :request.visitId
               
                LIMIT 1
            ];
            accountId = visits.isEmpty() ? null : visits[0].Account__c;
        }
        if (accountId == null) {
            return 'Account id (or Visit id with an account) is required to summarize affiliations.';
        }
        return buildAffiliationSummaryForAccount(accountId);
    }

    private static String buildAffiliationSummaryForAccount(Id accountId) {
        List<Account> accounts = [
            SELECT Name
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        String accountName = accounts.isEmpty() ? String.valueOf(accountId) : accounts[0].Name;

        List<Account_Affiliation__c> affiliations = [
            SELECT
                Primary_Account__c,
                Primary_Account__r.Name,
                Related_Account__c,
                Related_Account__r.Name,
                Affiliation_Type__c,
                Role__c,
                Strength__c,
                Influence__c,
                Outside_Territory__c
            FROM Account_Affiliation__c
            WHERE
                Is_Active__c = TRUE
                AND (Primary_Account__c = :accountId OR Related_Account__c = :accountId)
            ORDER BY Outside_Territory__c ASC, Strength__c DESC NULLS LAST, LastModifiedDate DESC
            LIMIT :MAX_AFFILIATION_LINES
        ];

        List<String> lines = new List<String>();
        lines.add('Affiliation network for ' + safeString(accountName) + ':');
        if (affiliations.isEmpty()) {
            lines.add('No active affiliations found.');
            return String.join(lines, '\n');
        }

        Integer outsideCount = 0;
        List<String> affiliationLines = new List<String>();
        for (Account_Affiliation__c affiliation : affiliations) {
            if (affiliation.Outside_Territory__c == true) {
                outsideCount++;
            }
            String otherName = affiliation.Primary_Account__c == accountId
                ? affiliation.Related_Account__r.Name
                : affiliation.Primary_Account__r.Name;
            affiliationLines.add(
                safeString(otherName) +
                ' via ' +
                safeString(affiliation.Affiliation_Type__c) +
                (String.isBlank(affiliation.Role__c) ? '' : ', role ' + affiliation.Role__c) +
                (String.isBlank(affiliation.Strength__c) ? '' : ', strength ' + affiliation.Strength__c) +
                (String.isBlank(affiliation.Influence__c) ? '' : ', influence ' + affiliation.Influence__c) +
                (affiliation.Outside_Territory__c == true ? ' [outside territory]' : '')
            );
        }
        lines.add('Active affiliations: ' + affiliations.size() + ' (outside territory: ' + outsideCount + ').');
        lines.add(String.join(affiliationLines, '; ') + '.');
        return String.join(lines, '\n');
    }

    private static String buildTerritoryProductSummary(TerritoryProductRequest request) {
        Id contextUserId = resolveUserId(request == null ? null : request.contextUserId);
        Id accountId = request == null ? null : request.accountId;

        Set<Id> territoryIds = getUserTerritoryIds(contextUserId);
        Set<Id> expandedTerritoryIds = expandTerritoryHierarchy(territoryIds);

        List<String> lines = new List<String>();
        lines.add('Territory product and classification context:');

        if (expandedTerritoryIds.isEmpty()) {
            lines.add('No territories are assigned to this user.');
            return String.join(lines, '\n');
        }

        List<Territory2> territories = [
            SELECT Name
            FROM Territory2
            WHERE Id IN :territoryIds
            ORDER BY Name
            LIMIT 10
        ];
        List<String> territoryNames = new List<String>();
        for (Territory2 territory : territories) {
            territoryNames.add(territory.Name);
        }
        lines.add('Assigned territories: ' + String.join(territoryNames, ', ') + '.');

        Map<String, Integer> classificationCounts = new Map<String, Integer>();
        Integer atfCount = 0;
        for (Account_Territory_Fields__c atf : [
            SELECT Classification__c, HCP_Classification__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :toTerritoryKeys(expandedTerritoryIds) AND Is_Active__c = TRUE
            LIMIT 5000
        ]) {
            atfCount++;
            String classification = String.isNotBlank(atf.Classification__c)
                ? atf.Classification__c
                : (String.isNotBlank(atf.HCP_Classification__c) ? atf.HCP_Classification__c : 'Unclassified');
            Integer count = classificationCounts.containsKey(classification)
                ? classificationCounts.get(classification)
                : 0;
            classificationCounts.put(classification, count + 1);
        }
        lines.add('Active account-territory classifications counted: ' + atfCount + '.');
        if (!classificationCounts.isEmpty()) {
            List<String> classLines = new List<String>();
            Integer bucketCount = 0;
            for (String classification : classificationCounts.keySet()) {
                classLines.add(classification + ': ' + classificationCounts.get(classification));
                bucketCount++;
                if (bucketCount >= MAX_CLASSIFICATION_BUCKETS) {
                    break;
                }
            }
            lines.add('Classification mix — ' + String.join(classLines, '; ') + '.');
        }

        Set<Id> productIds = getPtaProductIds(expandedTerritoryIds);
        if (productIds.isEmpty()) {
            lines.add('No active product-territory alignments found.');
        } else {
            List<String> productLines = new List<String>();
            Integer count = 0;
            for (Product2 product : [
                SELECT Name
                FROM Product2
                WHERE Id IN :productIds AND IsActive = TRUE
               
                ORDER BY Name
                LIMIT :MAX_PRODUCT_LINES
            ]) {
                productLines.add(product.Name);
                count++;
            }
            lines.add(
                'Aligned products (' +
                productIds.size() +
                ' total, showing ' +
                count +
                '): ' +
                String.join(productLines, '; ') +
                '.'
            );
        }

        if (accountId != null) {
            appendAccountClassificationLines(lines, accountId);
            appendAccountProductRatingLines(lines, accountId);
        }

        return String.join(lines, '\n');
    }

    private static void appendAccountClassificationLines(List<String> lines, Id accountId) {
        List<Account_Territory_Fields__c> atfRows = [
            SELECT
                Classification__c,
                HCP_Classification__c,
                Matrix_Rating__c,
                Potential__c,
                Penetration__c,
                Is_KOL__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :accountId AND Is_Active__c = TRUE
            ORDER BY LastModifiedDate DESC
            LIMIT 3
        ];
        if (atfRows.isEmpty()) {
            lines.add('No active territory classification (ATF) found for this account.');
            return;
        }
        List<String> classLines = new List<String>();
        for (Account_Territory_Fields__c atf : atfRows) {
            String classification = String.isNotBlank(atf.Classification__c)
                ? atf.Classification__c
                : safeString(atf.HCP_Classification__c);
            classLines.add(
                'class ' +
                classification +
                ', matrix ' +
                safeString(atf.Matrix_Rating__c) +
                ', potential ' +
                safeString(atf.Potential__c) +
                ', penetration ' +
                safeString(atf.Penetration__c) +
                (atf.Is_KOL__c == true ? ', KOL' : '')
            );
        }
        lines.add('Territory classification — ' + String.join(classLines, '; ') + '.');
    }

    private static void appendAccountProductRatingLines(List<String> lines, Id accountId) {
        List<Account_Territory_Product_Fields__c> atpfRows = [
            SELECT
                Product2_Id__c,
                Adoption__c,
                Loyalty__c,
                Product_Matrix_Rating__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c = :accountId AND Is_Active__c = TRUE AND Product2_Id__c != NULL
            ORDER BY LastModifiedDate DESC
            LIMIT :MAX_PRODUCT_LINES
        ];
        if (atpfRows.isEmpty()) {
            return;
        }

        Set<Id> productIds = new Set<Id>();
        for (Account_Territory_Product_Fields__c atpf : atpfRows) {
            try {
                productIds.add((Id) atpf.Product2_Id__c);
            } catch (Exception ex) {
                // Skip invalid product ids.
            }
        }
        Map<Id, String> productNames = new Map<Id, String>();
        if (!productIds.isEmpty()) {
            for (Product2 product : [
                SELECT Id, Name
                FROM Product2
                WHERE Id IN :productIds
               
            ]) {
                productNames.put(product.Id, product.Name);
            }
        }

        List<String> productLines = new List<String>();
        for (Account_Territory_Product_Fields__c atpf : atpfRows) {
            Id productId;
            try {
                productId = (Id) atpf.Product2_Id__c;
            } catch (Exception ex) {
                continue;
            }
            productLines.add(
                safeString(productNames.containsKey(productId) ? productNames.get(productId) : String.valueOf(productId)) +
                ' (matrix ' +
                safeString(atpf.Product_Matrix_Rating__c) +
                ', adoption ' +
                safeString(atpf.Adoption__c) +
                ', loyalty ' +
                safeString(atpf.Loyalty__c) +
                ')'
            );
        }
        if (!productLines.isEmpty()) {
            lines.add('Product ratings — ' + String.join(productLines, '; ') + '.');
        }
    }

    private static Employee_Time_Card__c findTimeCard(Id userId, Date monthStart) {
        List<Employee_Time_Card__c> cards = [
            SELECT Id, Name, Time_Card_Month_Start_Date__c
            FROM Employee_Time_Card__c
            WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :monthStart
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return cards.isEmpty() ? null : cards[0];
    }

    private static List<Employee_Time_Card_Account_Target__c> queryTargets(
        Id timeCardId,
        Id accountId,
        Integer rowLimit
    ) {
        if (accountId == null) {
            return [
                SELECT
                    Account__c,
                    Account__r.Name,
                    Target_Visit_Frequency__c,
                    Actual_Visits__c,
                    Frequency_Status__c,
                    Reach_Percent__c,
                    Potentiality__c,
                    Is_Visited__c,
                    Account_Territory_Fields__r.Classification__c,
                    Account_Territory_Fields__r.HCP_Classification__c
                FROM Employee_Time_Card_Account_Target__c
                WHERE Employee_Time_Card__c = :timeCardId
               
                ORDER BY Actual_Visits__c ASC NULLS FIRST, Target_Visit_Frequency__c DESC NULLS LAST
                LIMIT :rowLimit
            ];
        }
        return [
            SELECT
                Account__c,
                Account__r.Name,
                Target_Visit_Frequency__c,
                Actual_Visits__c,
                Frequency_Status__c,
                Reach_Percent__c,
                Potentiality__c,
                Is_Visited__c,
                Account_Territory_Fields__r.Classification__c,
                Account_Territory_Fields__r.HCP_Classification__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId AND Account__c = :accountId
            LIMIT :rowLimit
        ];
    }

    private static List<Visit__c> queryVisitsForUser(Id userId, Date startDay, Date endDay, Integer rowLimit) {
        Datetime startDt = Datetime.newInstance(startDay, Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(endDay.addDays(1), Time.newInstance(0, 0, 0, 0));
        return [
            SELECT Name, Status__c, Start_Date__c, Account__c, Account__r.Name
            FROM Visit__c
            WHERE
                Assigned_To__c = :userId
                AND Start_Date__c >= :startDt
                AND Start_Date__c < :endDt
                AND Status__c != 'Cancelled'
            ORDER BY Start_Date__c ASC
            LIMIT :rowLimit
        ];
    }

    private static String resolveTargetClassification(Employee_Time_Card_Account_Target__c target) {
        if (target.Account_Territory_Fields__r != null) {
            if (String.isNotBlank(target.Account_Territory_Fields__r.Classification__c)) {
                return target.Account_Territory_Fields__r.Classification__c;
            }
            if (String.isNotBlank(target.Account_Territory_Fields__r.HCP_Classification__c)) {
                return target.Account_Territory_Fields__r.HCP_Classification__c;
            }
        }
        return String.isBlank(target.Potentiality__c) ? 'Unclassified' : target.Potentiality__c;
    }

    private static List<Visit__c> limitVisits(List<Visit__c> visits, Integer maxRows) {
        List<Visit__c> limited = new List<Visit__c>();
        for (Visit__c visit : visits) {
            limited.add(visit);
            if (limited.size() >= maxRows) {
                break;
            }
        }
        return limited;
    }

    private static String formatVisitList(List<Visit__c> visits) {
        List<String> visitLines = new List<String>();
        for (Visit__c visit : visits) {
            visitLines.add(
                formatDateTime(visit.Start_Date__c) +
                ' — ' +
                safeString(visit.Account__r.Name) +
                ' (' +
                safeString(visit.Status__c) +
                ')'
            );
        }
        return String.join(visitLines, '; ');
    }

    private static Set<Id> getUserTerritoryIds(Id userId) {
        Set<Id> territoryIds = new Set<Id>();
        Id resolvedUserId = resolveUserId(userId);
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :resolvedUserId
        ]) {
            territoryIds.add(assignment.Territory2Id);
        }
        return territoryIds;
    }

    private static Set<Id> expandTerritoryHierarchy(Set<Id> seedTerritoryIds) {
        Set<Id> allTerritoryIds = new Set<Id>(seedTerritoryIds);
        if (allTerritoryIds.isEmpty()) {
            return allTerritoryIds;
        }
        Boolean addedChildren = true;
        while (addedChildren) {
            addedChildren = false;
            List<Territory2> children = [
                SELECT Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :allTerritoryIds AND Id NOT IN :allTerritoryIds
               
            ];
            for (Territory2 child : children) {
                allTerritoryIds.add(child.Id);
                addedChildren = true;
            }
        }
        return allTerritoryIds;
    }

    private static Set<Id> getPtaProductIds(Set<Id> territoryIds) {
        Set<Id> productIds = new Set<Id>();
        if (territoryIds.isEmpty()) {
            return productIds;
        }
        Date today = Date.today();
        Set<String> territoryKeys = toTerritoryKeys(territoryIds);
        for (Product_Territory_Alignment__c alignment : [
            SELECT Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE
                Territory2_Id__c IN :territoryKeys
                AND Product2_Id__c != NULL
                AND Is_Active__c = TRUE
                AND (Effective_Start_Date__c = NULL OR Effective_Start_Date__c <= :today)
                AND (Effective_End_Date__c = NULL OR Effective_End_Date__c >= :today)
        ]) {
            try {
                productIds.add((Id) alignment.Product2_Id__c);
            } catch (Exception ex) {
                // Skip invalid ids.
            }
        }
        return productIds;
    }

    private static Set<String> toTerritoryKeys(Set<Id> territoryIds) {
        Set<String> keys = new Set<String>();
        for (Id territoryId : territoryIds) {
            keys.add(String.valueOf(territoryId));
        }
        return keys;
    }

    private static Id resolveUserId(Id contextUserId) {
        return contextUserId == null ? UserInfo.getUserId() : contextUserId;
    }

    private static Date startOfWeek(Date value) {
        Date anchor = value == null ? Date.today() : value;
        Datetime anchorDt = Datetime.newInstance(anchor, Time.newInstance(0, 0, 0, 0));
        Integer isoDay = Integer.valueOf(anchorDt.format('u'));
        Integer diff = isoDay == 7 ? -6 : 1 - isoDay;
        return anchor.addDays(diff);
    }

    private static String joinCountMap(Map<String, Integer> values) {
        List<String> parts = new List<String>();
        for (String key : values.keySet()) {
            parts.add(key + ': ' + values.get(key));
        }
        return String.join(parts, '; ');
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String formatPercent(Decimal value) {
        if (value == null) {
            return '0%';
        }
        return String.valueOf(value.setScale(0)) + '%';
    }

    private static String formatDecimal(Decimal value) {
        if (value == null) {
            return '0';
        }
        return String.valueOf(value.setScale(1));
    }

    private static String safeString(String value) {
        return String.isBlank(value) ? '—' : value;
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '—';
        }
        return value.format();
    }

    private static String formatDateTime(DateTime value) {
        if (value == null) {
            return '—';
        }
        return value.format('yyyy-MM-dd HH:mm');
    }
}