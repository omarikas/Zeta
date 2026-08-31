public without sharing class EmployeeTimeCardService {

    private static final String HEAD_OFFICE_EXTERNAL_ID = 'TERR_HEAD_OFFICE';

    private static Map<Id, String> departmentCache = new Map<Id, String>();
    private static Map<Id, String> territoryNameCache = new Map<Id, String>();

    public static Employee_Time_Card__c ensureMonthlyTimeCard(Id employeeId, Date monthStart) {
        return ensureMonthlyTimeCard(employeeId, monthStart, false);
    }

    public static Employee_Time_Card__c ensureMonthlyTimeCard(Id employeeId, Date monthStart, Boolean deferFlowRecalc) {
        return ensureMonthlyTimeCard(employeeId, monthStart, deferFlowRecalc, false);
    }

    public static Employee_Time_Card__c ensureMonthlyTimeCard(
        Id employeeId,
        Date monthStart,
        Boolean deferFlowRecalc,
        Boolean deferDayActivityRecalc
    ) {
        if (employeeId == null || monthStart == null) {
            return null;
        }
        Date normalizedStart = Date.newInstance(monthStart.year(), monthStart.month(), 1);
        Date monthEnd = normalizedStart.addMonths(1).addDays(-1);
        String uniqueKey = String.valueOf(employeeId) + ':' + String.valueOf(normalizedStart);

        List<Employee_Time_Card__c> existing = [
            SELECT Id, Employee__c, Time_Card_Month_Start_Date__c, Territory__c, Active_Time_Card__c
            FROM Employee_Time_Card__c
            WHERE Unique_Identifier__c = :uniqueKey
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        String territoryName = resolvePrimaryTerritoryNameCached(employeeId);
        Boolean isCurrentMonth = normalizedStart == Date.newInstance(Date.today().year(), Date.today().month(), 1);

        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = employeeId,
            Time_Card_Month_Start_Date__c = normalizedStart,
            Time_Card_Month_End_Date__c = monthEnd,
            Territory__c = territoryName,
            Active_Time_Card__c = isCurrentMonth,
            Unique_Identifier__c = uniqueKey
        );
        insert as system timeCard;
        createDayEntries(timeCard, normalizedStart, monthEnd, employeeId, deferFlowRecalc, deferDayActivityRecalc);
        EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(new Set<Id>{ timeCard.Id });
        return timeCard;
    }

    public static void syncAccountTargets(Id timeCardId) {
        if (timeCardId == null) {
            return;
        }

        Employee_Time_Card__c timeCard = [
            SELECT Id, Employee__c, Time_Card_Month_Start_Date__c, Territory__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCardId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Set<Id> territoryIds = resolveEmployeeTerritoryIds(timeCard.Employee__c);
        if (territoryIds.isEmpty()) {
            return;
        }

        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }

        List<Account_Territory_Fields__c> atfRecords = [
            SELECT Id, Account__c, Territory2_Id__c, Classification__c, Potential__c, Is_Active__c
            FROM Account_Territory_Fields__c
            WHERE Is_Active__c = true
            AND Territory2_Id__c IN :territoryIdStrings
            WITH SYSTEM_MODE
            LIMIT 500
        ];
        if (atfRecords.isEmpty()) {
            return;
        }

        Map<String, Decimal> frequencyByAtfKey = loadTargetFrequencies(atfRecords);
        Map<String, Employee_Time_Card_Account_Target__c> existingByKey = new Map<String, Employee_Time_Card_Account_Target__c>();
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Unique_Key__c, Account__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId
            WITH SYSTEM_MODE
        ]) {
            existingByKey.put(target.Unique_Key__c, target);
        }

        List<Employee_Time_Card_Account_Target__c> targetsToDelete = new List<Employee_Time_Card_Account_Target__c>();
        Set<Id> targetDeleteIds = new Set<Id>();
        Map<String, Employee_Time_Card_Account_Target__c> upsertsByKey = new Map<String, Employee_Time_Card_Account_Target__c>();
        for (Account_Territory_Fields__c atf : atfRecords) {
            String key = timeCardId + ':' + String.valueOf(atf.Account__c);
            if (!includeAccountInPlanCycle(atf.Account__c)) {
                if (existingByKey.containsKey(key)) {
                    Employee_Time_Card_Account_Target__c toDelete = existingByKey.get(key);
                    if (!targetDeleteIds.contains(toDelete.Id)) {
                        targetsToDelete.add(toDelete);
                        targetDeleteIds.add(toDelete.Id);
                    }
                }
                continue;
            }
            String freqKey = String.valueOf(atf.Account__c) + ':' + atf.Territory2_Id__c;
            Decimal targetFrequency = frequencyByAtfKey.containsKey(freqKey)
                ? frequencyByAtfKey.get(freqKey)
                : 1;

            Employee_Time_Card_Account_Target__c row = upsertsByKey.containsKey(key)
                ? upsertsByKey.get(key)
                : (existingByKey.containsKey(key)
                    ? existingByKey.get(key)
                    : new Employee_Time_Card_Account_Target__c(
                        Employee_Time_Card__c = timeCardId,
                        Unique_Key__c = key
                    ));
            row.Account__c = atf.Account__c;
            row.Account_Territory_Fields__c = atf.Id;
            row.Potentiality__c = resolvePotentiality(atf);
            if (
                !upsertsByKey.containsKey(key) ||
                targetFrequency > row.Target_Visit_Frequency__c
            ) {
                row.Target_Visit_Frequency__c = targetFrequency;
            }
            row.Rep__c = timeCard.Employee__c;
            upsertsByKey.put(key, row);
        }

        for (String key : existingByKey.keySet()) {
            if (!upsertsByKey.containsKey(key)) {
                Employee_Time_Card_Account_Target__c toDelete = existingByKey.get(key);
                if (!targetDeleteIds.contains(toDelete.Id)) {
                    targetsToDelete.add(toDelete);
                    targetDeleteIds.add(toDelete.Id);
                }
            }
        }

        if (!targetsToDelete.isEmpty()) {
            delete as system targetsToDelete;
        }

        if (!upsertsByKey.isEmpty()) {
            upsert as system upsertsByKey.values();
        }
    }

    public static void syncAccountTargetsForTimeCards(Id employeeId, List<Id> timeCardIds) {
        if (employeeId == null || timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }

        Set<Id> territoryIds = resolveEmployeeTerritoryIds(employeeId);
        if (territoryIds.isEmpty()) {
            return;
        }

        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }

        List<Account_Territory_Fields__c> atfRecords = [
            SELECT Id, Account__c, Territory2_Id__c, Classification__c, Potential__c, Is_Active__c
            FROM Account_Territory_Fields__c
            WHERE Is_Active__c = true
            AND Territory2_Id__c IN :territoryIdStrings
            WITH SYSTEM_MODE
            LIMIT 500
        ];
        if (atfRecords.isEmpty()) {
            return;
        }

        Map<String, Decimal> frequencyByAtfKey = loadTargetFrequencies(atfRecords);
        Map<Id, Map<String, Employee_Time_Card_Account_Target__c>> existingByCard = new Map<Id, Map<String, Employee_Time_Card_Account_Target__c>>();
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Unique_Key__c, Account__c, Employee_Time_Card__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            WITH SYSTEM_MODE
        ]) {
            if (!existingByCard.containsKey(target.Employee_Time_Card__c)) {
                existingByCard.put(target.Employee_Time_Card__c, new Map<String, Employee_Time_Card_Account_Target__c>());
            }
            existingByCard.get(target.Employee_Time_Card__c).put(target.Unique_Key__c, target);
        }

        Map<String, Employee_Time_Card_Account_Target__c> upsertsByKey = new Map<String, Employee_Time_Card_Account_Target__c>();
        List<Employee_Time_Card_Account_Target__c> targetsToDelete = new List<Employee_Time_Card_Account_Target__c>();
        Set<Id> targetDeleteIds = new Set<Id>();
        for (Id timeCardId : timeCardIds) {
            Map<String, Employee_Time_Card_Account_Target__c> existingByKey = existingByCard.containsKey(timeCardId)
                ? existingByCard.get(timeCardId)
                : new Map<String, Employee_Time_Card_Account_Target__c>();
            for (Account_Territory_Fields__c atf : atfRecords) {
                String key = timeCardId + ':' + String.valueOf(atf.Account__c);
                if (!includeAccountInPlanCycle(atf.Account__c)) {
                    if (existingByKey.containsKey(key)) {
                        Employee_Time_Card_Account_Target__c toDelete = existingByKey.get(key);
                        if (!targetDeleteIds.contains(toDelete.Id)) {
                            targetsToDelete.add(toDelete);
                            targetDeleteIds.add(toDelete.Id);
                        }
                    }
                    continue;
                }
                String freqKey = String.valueOf(atf.Account__c) + ':' + atf.Territory2_Id__c;
                Decimal targetFrequency = frequencyByAtfKey.containsKey(freqKey)
                    ? frequencyByAtfKey.get(freqKey)
                    : 1;

                Employee_Time_Card_Account_Target__c row = upsertsByKey.containsKey(key)
                    ? upsertsByKey.get(key)
                    : (existingByKey.containsKey(key)
                        ? existingByKey.get(key)
                        : new Employee_Time_Card_Account_Target__c(
                            Employee_Time_Card__c = timeCardId,
                            Unique_Key__c = key
                        ));
                row.Account__c = atf.Account__c;
                row.Account_Territory_Fields__c = atf.Id;
                row.Potentiality__c = resolvePotentiality(atf);
                if (
                    !upsertsByKey.containsKey(key) ||
                    targetFrequency > row.Target_Visit_Frequency__c
                ) {
                    row.Target_Visit_Frequency__c = targetFrequency;
                }
                row.Rep__c = employeeId;
                upsertsByKey.put(key, row);
            }
            for (String key : existingByKey.keySet()) {
                if (!upsertsByKey.containsKey(key)) {
                    Employee_Time_Card_Account_Target__c toDelete = existingByKey.get(key);
                    if (!targetDeleteIds.contains(toDelete.Id)) {
                        targetsToDelete.add(toDelete);
                        targetDeleteIds.add(toDelete.Id);
                    }
                }
            }
        }

        if (!targetsToDelete.isEmpty()) {
            delete as system targetsToDelete;
        }

        if (!upsertsByKey.isEmpty()) {
            upsert as system upsertsByKey.values();
        }
    }

    @TestVisible
    private static void createDayEntries(
        Employee_Time_Card__c timeCard,
        Date monthStart,
        Date monthEnd,
        Id employeeId
    ) {
        createDayEntries(timeCard, monthStart, monthEnd, employeeId, false);
    }

    @TestVisible
    private static void createDayEntries(
        Employee_Time_Card__c timeCard,
        Date monthStart,
        Date monthEnd,
        Id employeeId,
        Boolean deferFlowRecalc
    ) {
        createDayEntries(timeCard, monthStart, monthEnd, employeeId, deferFlowRecalc, false);
    }

    @TestVisible
    private static void createDayEntries(
        Employee_Time_Card__c timeCard,
        Date monthStart,
        Date monthEnd,
        Id employeeId,
        Boolean deferFlowRecalc,
        Boolean deferDayActivityRecalc
    ) {
        String department = getEmployeeDepartmentCached(employeeId);
        List<Employee_Time_Card_Day_Entry__c> entries = new List<Employee_Time_Card_Day_Entry__c>();
        for (Date d = monthStart; d <= monthEnd; d = d.addDays(1)) {
            Boolean weekend = EmployeeTimeCardFlowHelper.isWeekendDay(d, department);
            entries.add(new Employee_Time_Card_Day_Entry__c(
                Employee_Time_Card__c = timeCard.Id,
                Date__c = d,
                Day_Definition__c = weekend ? 'Weekend Day' : 'Weekday',
                Calendar_Working_Days__c = weekend ? 0 : 1,
                Submitted_Calls__c = 0,
                Days_with_Activities__c = 0,
                No_Activity_Days__c = 0,
                CLM_Visits__c = 0,
                TOT_Days__c = 0,
                TOT_Days_Excluding_Weekends__c = 0
            ));
        }
        if (!entries.isEmpty()) {
            insert as system entries;
        }
        if (!deferFlowRecalc) {
            EmployeeTimeCardFlowHelper.recalcDayDefinitionsForEmployeeAndRange(employeeId, monthStart, monthEnd);
            EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(employeeId, monthStart, monthEnd);
        }
        // EmployeeTimeCardMetricsService is not in this org; day-activity metrics stay at defaults.
    }

    @TestVisible
    private static String resolvePrimaryTerritoryNameCached(Id employeeId) {
        if (!territoryNameCache.containsKey(employeeId)) {
            territoryNameCache.put(employeeId, resolvePrimaryTerritoryName(employeeId));
        }
        return territoryNameCache.get(employeeId);
    }

    @TestVisible
    private static String getEmployeeDepartmentCached(Id employeeId) {
        if (!departmentCache.containsKey(employeeId)) {
            departmentCache.put(employeeId, getEmployeeDepartment(employeeId));
        }
        return departmentCache.get(employeeId);
    }

    @TestVisible
    private static String resolvePrimaryTerritoryName(Id employeeId) {
        List<UserTerritory2Association> assignments = [
            SELECT Territory2.Name
            FROM UserTerritory2Association
            WHERE UserId = :employeeId
            WITH SYSTEM_MODE
            ORDER BY Territory2.Name ASC
            LIMIT 1
        ];
        return assignments.isEmpty() ? null : assignments[0].Territory2.Name;
    }

    @TestVisible
    private static Set<Id> testOverrideTerritoryIds;

    @TestVisible
    private static Set<Id> resolveEmployeeTerritoryIds(Id employeeId) {
        if (testOverrideTerritoryIds != null) {
            return expandTerritoryHierarchy(testOverrideTerritoryIds);
        }
        Set<Id> territoryIds = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :employeeId
            WITH SYSTEM_MODE
        ]) {
            territoryIds.add(assignment.Territory2Id);
        }
        if (territoryIds.isEmpty()) {
            return territoryIds;
        }

        Id headOfficeId = getHeadOfficeTerritoryId();
        if (headOfficeId != null && territoryIds.contains(headOfficeId)) {
            return expandTerritoryHierarchy(new Set<Id>{ headOfficeId });
        }
        return territoryIds;
    }

    private static Id getHeadOfficeTerritoryId() {
        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :HEAD_OFFICE_EXTERNAL_ID
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return territories.isEmpty() ? null : territories[0].Id;
    }

    @TestVisible
    private static Set<Id> expandTerritoryHierarchy(Set<Id> rootTerritoryIds) {
        Set<Id> expanded = new Set<Id>(rootTerritoryIds);
        List<Id> frontier = new List<Id>(rootTerritoryIds);
        while (!frontier.isEmpty()) {
            List<Id> nextFrontier = new List<Id>();
            for (Territory2 child : [
                SELECT Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :frontier
                WITH SYSTEM_MODE
            ]) {
                if (!expanded.contains(child.Id)) {
                    expanded.add(child.Id);
                    nextFrontier.add(child.Id);
                }
            }
            frontier = nextFrontier;
        }
        return expanded;
    }

    @TestVisible
    private static Map<String, Decimal> loadTargetFrequencies(List<Account_Territory_Fields__c> atfRecords) {
        Set<String> accountIds = new Set<String>();
        Set<String> territoryIds = new Set<String>();
        for (Account_Territory_Fields__c atf : atfRecords) {
            accountIds.add(String.valueOf(atf.Account__c));
            territoryIds.add(atf.Territory2_Id__c);
        }

        Map<String, Decimal> result = new Map<String, Decimal>();
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT Account__c, Territory2_Id__c, Target_Visit_Frequency__c
            FROM Account_Territory_Product_Fields__c
            WHERE Territory2_Id__c IN :territoryIds
            WITH SYSTEM_MODE
        ]) {
            String key = String.valueOf(atpf.Account__c) + ':' + atpf.Territory2_Id__c;
            if (!accountIds.contains(String.valueOf(atpf.Account__c))) {
                continue;
            }
            Decimal mapped = mapFrequencyPicklist(atpf.Target_Visit_Frequency__c);
            if (!result.containsKey(key) || mapped > result.get(key)) {
                result.put(key, mapped);
            }
        }
        return result;
    }

    public static Decimal mapFrequencyPicklist(String frequencyValue) {
        if (String.isBlank(frequencyValue)) {
            return 1;
        }
        if (frequencyValue == 'Weekly') {
            return 4;
        }
        if (frequencyValue == 'Bi-Weekly') {
            return 2;
        }
        if (frequencyValue == 'Monthly') {
            return 1;
        }
        if (frequencyValue == 'Quarterly') {
            return 1;
        }
        return 0;
    }

    @TestVisible
    private static String resolvePotentiality(Account_Territory_Fields__c atf) {
        if (String.isNotBlank(atf.Classification__c)) {
            return atf.Classification__c;
        }
        if (String.isNotBlank(atf.Potential__c)) {
            return atf.Potential__c;
        }
        return 'Not Rated';
    }

    @TestVisible
    private static String getEmployeeDepartment(Id employeeId) {
        List<User> users = [SELECT Department FROM User WHERE Id = :employeeId LIMIT 1];
        return users.isEmpty() ? null : users[0].Department;
    }

    @TestVisible
    private static Boolean includeAccountInPlanCycle(Id accountId) {
        if (accountId == null) {
            return false;
        }
        // Keep ~20% of territory accounts out of the monthly plan cycle for demo variety.
        return Math.mod(Math.abs(String.valueOf(accountId).hashCode()), 5) != 0;
    }

    public static void applyVisionWeights(Id timeCardId, Map<String, Object> weights) {
        if (timeCardId == null || weights == null || weights.isEmpty()) {
            return;
        }
        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT Id, Potentiality__c, Target_Visit_Frequency__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId
            WITH SYSTEM_MODE
        ];
        if (targets.isEmpty()) {
            return;
        }
        for (Employee_Time_Card_Account_Target__c target : targets) {
            String classification = String.isNotBlank(target.Potentiality__c)
                ? target.Potentiality__c.left(1)
                : 'B';
            if (!weights.containsKey(classification)) {
                continue;
            }
            Object weightObj = weights.get(classification);
            Decimal weight = weightObj == null ? 1 : Decimal.valueOf(String.valueOf(weightObj));
            Decimal base = target.Target_Visit_Frequency__c == null ? 1 : target.Target_Visit_Frequency__c;
            target.Target_Visit_Frequency__c = (base * weight).setScale(0, System.RoundingMode.HALF_UP);
        }
        update as system targets;
    }
}
