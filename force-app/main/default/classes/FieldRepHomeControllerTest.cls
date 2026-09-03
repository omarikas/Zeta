@IsTest
private class FieldRepHomeControllerTest {
    private static Id territoryIdForTest;

    @TestSetup
    static void setup() {
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        territoryIdForTest = getOrCreateTestTerritory('TERR_TEST_FIELD_REP_HOME');
        System.assertNotEquals(null, territoryIdForTest, 'Expected Territory2 record for test ATF rows.');

        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = u.Id,
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthEnd,
            Active_Time_Card__c = true,
            Unique_Identifier__c = u.Id + ':' + String.valueOf(monthStart),
            Territory__c = 'Test Territory'
        );
        Database.insert(timeCard, AccessLevel.SYSTEM_MODE);

        // Accounts (ensure geolocation is present for NBC query)
        Account aA = new Account(
            Name = 'Account A',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357,
            BillingCity = 'Cairo'
        );
        Account aB = new Account(
            Name = 'Account B',
            BillingLatitude = 30.0450,
            BillingLongitude = 31.2360,
            BillingCity = 'Cairo'
        );
        Account aC = new Account(
            Name = 'Account C',
            BillingLatitude = 30.0460,
            BillingLongitude = 31.2370,
            BillingCity = 'Cairo'
        );
        Database.insert(new List<Account>{ aA, aB, aC }, AccessLevel.SYSTEM_MODE);

        // ATF rows for drill-down
        Account_Territory_Fields__c atfA = new Account_Territory_Fields__c(
            Account__c = aA.Id,
            Territory2_Id__c = territoryIdForTest,
            Potential__c = 'A',
            Penetration__c = '1',
            Matrix_Rating__c = 'A1',
            Classification__c = 'A',
            Is_Active__c = true
        );
        Account_Territory_Fields__c atfB = new Account_Territory_Fields__c(
            Account__c = aB.Id,
            Territory2_Id__c = territoryIdForTest,
            Potential__c = 'B',
            Penetration__c = '2',
            Matrix_Rating__c = 'B2',
            Classification__c = 'B',
            Is_Active__c = true
        );
        Account_Territory_Fields__c atfC = new Account_Territory_Fields__c(
            Account__c = aC.Id,
            Territory2_Id__c = territoryIdForTest,
            Potential__c = 'C',
            Penetration__c = '3',
            Matrix_Rating__c = 'C3',
            Classification__c = 'C',
            Is_Active__c = true
        );
        Database.insert(new List<Account_Territory_Fields__c>{ atfA, atfB, atfC }, AccessLevel.SYSTEM_MODE);

        // Targets on the time card
        Employee_Time_Card_Account_Target__c tA = new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = aA.Id,
            Account_Territory_Fields__c = atfA.Id,
            Target_Visit_Frequency__c = 10,
            Actual_Visits__c = 5,
            Potentiality__c = 'A',
            Unique_Key__c = timeCard.Id + ':' + aA.Id
        );
        Employee_Time_Card_Account_Target__c tB = new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = aB.Id,
            Account_Territory_Fields__c = atfB.Id,
            Target_Visit_Frequency__c = 20,
            Actual_Visits__c = 0,
            Potentiality__c = 'B',
            Unique_Key__c = timeCard.Id + ':' + aB.Id
        );
        Employee_Time_Card_Account_Target__c tC = new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = aC.Id,
            Account_Territory_Fields__c = atfC.Id,
            Target_Visit_Frequency__c = 5,
            Actual_Visits__c = 5,
            Potentiality__c = 'C',
            Unique_Key__c = timeCard.Id + ':' + aC.Id
        );
        Database.insert(new List<Employee_Time_Card_Account_Target__c>{ tA, tB, tC }, AccessLevel.SYSTEM_MODE);

        // Planned visit today for Account B (so NBC will apply plannedToday penalty)
        DateTime startToday = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        DateTime endToday = startToday.addMinutes(30);
        Database.insert(new Visit__c(
            Account__c = aB.Id,
            Assigned_To__c = u.Id,
            Visit_Date__c = Date.today(),
            Start_Date__c = startToday,
            End_Date__c = endToday,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            CLM_Presentation__c = 'CLM1'
        ), AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void getHomeMetrics_computesCoverageAndRF() {
        Test.startTest();
        FieldRepHomeController.HomeMetrics metrics = FieldRepHomeController.getHomeMetrics(null);
        Test.stopTest();

        System.assert(metrics.visitCoveragePercent > 28 && metrics.visitCoveragePercent < 29, 'Unexpected total visit coverage.');
        System.assert(metrics.customerCoveragePercent > 66 && metrics.customerCoveragePercent < 67, 'Unexpected total customer coverage.');

        FieldRepHomeController.ClassificationMetrics aRow = findByClass(metrics.byClassification, 'A');
        System.assertEquals(50, Integer.valueOf(aRow.visitCoveragePercent), 'Expected A class visit coverage 50%.');
        System.assertEquals(0, Integer.valueOf(aRow.rfPercent), 'Expected A class RF% 0%.');

        FieldRepHomeController.ClassificationMetrics cRow = findByClass(metrics.byClassification, 'C');
        System.assertEquals(100, Integer.valueOf(cRow.rfPercent), 'Expected C class RF% 100%.');
    }

    @IsTest
    static void getAccountCoverageRows_includesATFDrillDown() {
        List<FieldRepHomeController.AccountCoverageRow> rows = FieldRepHomeController.getAccountCoverageRows(null, 'A');
        System.assertEquals(1, rows.size());

        FieldRepHomeController.AccountCoverageRow row = rows[0];
        System.assertEquals('Account A', row.accountName);
        System.assertEquals('A', row.potential);
        System.assertEquals('1', row.penetration);
        System.assertEquals('A', row.calculatedClassification);
    }

    @IsTest
    static void getNextBestCustomers_ranksByScore() {
        List<FieldRepHomeController.NextBestCustomerRow> nbc = FieldRepHomeController.getNextBestCustomers(null, 5);
        System.assertEquals(2, nbc.size(), 'Only LCF accounts should be included.');

        System.assertEquals(1, nbc[0].rank);
        System.assertEquals('Account B', nbc[0].accountName);
        System.assertEquals(true, nbc[0].plannedToday, 'Expected planned today penalty for Account B.');

        System.assertEquals('Account A', nbc[1].accountName);
    }

    @IsTest
    static void getTodayPlan_returnsCurrentUserVisits() {
        FieldPlannerController.PlannerPayload plan = FieldRepHomeController.getTodayPlan(null, Date.today());
        System.assertNotEquals(null, plan);
        System.assertEquals(1, plan.visits == null ? 0 : plan.visits.size(), 'Expected one visit today.');
    }

    @IsTest
    static void getTodayPlan_rejectsUnauthorizedContextUser() {
        User other = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId() AND IsActive = TRUE LIMIT 1];
        Boolean threw = false;
        try {
            FieldRepHomeController.getTodayPlan(other.Id, Date.today());
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Expected unauthorized context user to be rejected.');
    }

    @IsTest
    static void getPerformanceRankings_returnsRankSummaryAndLeaderboard() {
        Test.startTest();
        FieldRepHomeController.PerformanceRankings rankings = FieldRepHomeController.getPerformanceRankings(null);
        Test.stopTest();

        System.assertNotEquals(null, rankings, 'Expected rankings payload.');
        System.assertNotEquals(null, rankings.top5InBu, 'Expected BU top 5 list.');
        System.assertNotEquals(null, rankings.top5Company, 'Expected company top 5 list.');
        System.assert(rankings.buTotal >= 1, 'Expected at least one rep in BU scope.');
        System.assert(rankings.companyTotal >= 1, 'Expected at least one rep in company scope.');
        System.assertNotEquals(null, rankings.buRank, 'Expected BU rank for current user.');
        System.assertNotEquals(null, rankings.companyRank, 'Expected company rank for current user.');
        System.assert(rankings.myCoveragePercent > 28 && rankings.myCoveragePercent < 29, 'Expected visit coverage from test targets.');
    }

    @IsTest
    static void getPerformanceGamification_returnsBadgesAndStreaks() {
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Account aA = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];

        Date today = Date.today();
        Date yesterday = today.addDays(-1);
        Date twoDaysAgo = today.addDays(-2);

        List<Visit__c> streakVisits = new List<Visit__c>();
        for (Date visitDay : new List<Date>{ twoDaysAgo, yesterday }) {
            if (visitDay.toStartOfWeek() != today.toStartOfWeek() || visitDay > today) {
                continue;
            }
            DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(8, 30, 0, 0));
            streakVisits.add(new Visit__c(
                Account__c = aA.Id,
                Assigned_To__c = u.Id,
                Visit_Date__c = startDt,
                Start_Date__c = startDt,
                End_Date__c = startDt.addMinutes(30),
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)',
                CLM_Presentation__c = 'CLM1'
            ));
        }
        if (!streakVisits.isEmpty()) {
            Database.insert(streakVisits, AccessLevel.SYSTEM_MODE);
        }

        Test.startTest();
        FieldRepHomeController.PerformanceGamification gamification = FieldRepHomeController.getPerformanceGamification(
            null,
            Date.today().toStartOfMonth()
        );
        Test.stopTest();

        System.assertNotEquals(null, gamification.userFirstName, 'Expected user first name.');
        System.assertNotEquals(null, gamification.streaks, 'Expected streak info.');
        System.assertNotEquals(null, gamification.badges, 'Expected badge list.');
        System.assertEquals(6, gamification.badges.size(), 'Expected six badge definitions.');

        FieldRepHomeController.BadgeResult onTarget = findBadge(gamification.badges, 'on_target');
        System.assertNotEquals(null, onTarget, 'Expected on_target badge.');
        System.assertEquals(false, onTarget.earned, 'Visit coverage below 100% should not earn On Target.');

        FieldRepHomeController.BadgeResult classAAce = findBadge(gamification.badges, 'class_a_ace');
        System.assertNotEquals(null, classAAce, 'Expected class_a_ace badge.');
        System.assertEquals(false, classAAce.earned, 'Class A coverage is 50% in test data.');
    }

    private static FieldRepHomeController.BadgeResult findBadge(
        List<FieldRepHomeController.BadgeResult> badges,
        String badgeId
    ) {
        for (FieldRepHomeController.BadgeResult badge : badges) {
            if (badge.badgeId == badgeId) {
                return badge;
            }
        }
        return null;
    }

    private static FieldRepHomeController.ClassificationMetrics findByClass(
        List<FieldRepHomeController.ClassificationMetrics> rows,
        String clazz
    ) {
        for (FieldRepHomeController.ClassificationMetrics row : rows) {
            if (row.classification == clazz) {
                return row;
            }
        }
        return null;
    }

    private static String getOrCreateTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return String.valueOf(existing[0].Id);
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = 'Field Rep Home Test',
            DeveloperName = 'Field_Rep_Home_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        // Territory2 is a setup object; isolate its DML to avoid MIXED_DML_OPERATION
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Database.insert(territory, AccessLevel.SYSTEM_MODE);
        }
        return String.valueOf(territory.Id);
    }
}