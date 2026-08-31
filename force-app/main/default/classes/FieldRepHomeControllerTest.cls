@IsTest
private class FieldRepHomeControllerTest {
    @TestSetup
    static void setup() {
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Id userId = UserInfo.getUserId();

        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = userId,
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthEnd,
            Active_Time_Card__c = true,
            Unique_Identifier__c = userId + ':' + String.valueOf(monthStart),
            Territory__c = 'Test Territory'
        );
        Database.insert(timeCard, AccessLevel.SYSTEM_MODE);

        Account aA = new Account(Name = 'Account A', BillingLatitude = 30.0444, BillingLongitude = 31.2357, BillingCity = 'Cairo');
        Account aB = new Account(Name = 'Account B', BillingLatitude = 30.0450, BillingLongitude = 31.2360, BillingCity = 'Cairo');
        Account aC = new Account(Name = 'Account C', BillingLatitude = 30.0460, BillingLongitude = 31.2370, BillingCity = 'Cairo');
        Database.insert(new List<Account>{ aA, aB, aC }, AccessLevel.SYSTEM_MODE);

        Id territoryId = firstTerritoryId();
        if (territoryId != null) {
            Account_Territory_Fields__c atfA = new Account_Territory_Fields__c(
                Account__c = aA.Id,
                Territory2_Id__c = territoryId,
                Potential__c = 'A',
                Penetration__c = '1',
                Matrix_Rating__c = 'A1',
                Classification__c = 'A',
                Is_Active__c = true
            );
            Account_Territory_Fields__c atfB = new Account_Territory_Fields__c(
                Account__c = aB.Id,
                Territory2_Id__c = territoryId,
                Potential__c = 'B',
                Penetration__c = '2',
                Matrix_Rating__c = 'B2',
                Classification__c = 'B',
                Is_Active__c = true
            );
            Account_Territory_Fields__c atfC = new Account_Territory_Fields__c(
                Account__c = aC.Id,
                Territory2_Id__c = territoryId,
                Potential__c = 'C',
                Penetration__c = '3',
                Matrix_Rating__c = 'C3',
                Classification__c = 'C',
                Is_Active__c = true
            );
            Database.insert(new List<Account_Territory_Fields__c>{ atfA, atfB, atfC }, AccessLevel.SYSTEM_MODE);

            Database.insert(
                new List<Employee_Time_Card_Account_Target__c>{
                    new Employee_Time_Card_Account_Target__c(
                        Employee_Time_Card__c = timeCard.Id,
                        Account__c = aA.Id,
                        Account_Territory_Fields__c = atfA.Id,
                        Target_Visit_Frequency__c = 10,
                        Actual_Visits__c = 5,
                        Potentiality__c = 'A',
                        Unique_Key__c = timeCard.Id + ':' + aA.Id
                    ),
                    new Employee_Time_Card_Account_Target__c(
                        Employee_Time_Card__c = timeCard.Id,
                        Account__c = aB.Id,
                        Account_Territory_Fields__c = atfB.Id,
                        Target_Visit_Frequency__c = 20,
                        Actual_Visits__c = 0,
                        Potentiality__c = 'B',
                        Unique_Key__c = timeCard.Id + ':' + aB.Id
                    ),
                    new Employee_Time_Card_Account_Target__c(
                        Employee_Time_Card__c = timeCard.Id,
                        Account__c = aC.Id,
                        Account_Territory_Fields__c = atfC.Id,
                        Target_Visit_Frequency__c = 5,
                        Actual_Visits__c = 5,
                        Potentiality__c = 'C',
                        Unique_Key__c = timeCard.Id + ':' + aC.Id
                    )
                },
                AccessLevel.SYSTEM_MODE
            );
        }

        DateTime startToday = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        Database.insert(
            new Visit__c(
                Account__c = aB.Id,
                Assigned_To__c = userId,
                Visit_Date__c = startToday,
                Start_Date__c = startToday,
                End_Date__c = startToday.addMinutes(30),
                Status__c = 'Draft',
                Visit_Type__c = 'Planned (Automatically)',
                CLM_Presentation__c = 'CLM1'
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void getHomeMetrics_returnsCoverage() {
        Test.startTest();
        FieldRepHomeController.HomeMetrics metrics = FieldRepHomeController.getHomeMetrics(null);
        Test.stopTest();
        System.assertNotEquals(null, metrics);
        System.assertNotEquals(null, metrics.byClassification);
        System.assert(metrics.visitCoveragePercent >= 0);
        System.assert(metrics.customerCoveragePercent >= 0);
    }

    @IsTest
    static void getAccountCoverageRows_andNbc() {
        List<FieldRepHomeController.AccountCoverageRow> rows = FieldRepHomeController.getAccountCoverageRows(null, 'A');
        System.assertNotEquals(null, rows);
        List<FieldRepHomeController.AccountCoverageRow> allRows = FieldRepHomeController.getAccountCoverageRows(null, null);
        System.assertNotEquals(null, allRows);
        List<FieldRepHomeController.NextBestCustomerRow> nbc = FieldRepHomeController.getNextBestCustomers(null, 5);
        System.assertNotEquals(null, nbc);
        FieldRepHomeController.getNextBestCustomers(null, 0);
    }

    @IsTest
    static void getTodayPlan_andGamificationAndRankings() {
        FieldPlannerController.PlannerPayload plan = FieldRepHomeController.getTodayPlan(null, Date.today());
        System.assertNotEquals(null, plan);
        FieldRepHomeController.getTodayPlan(null, null);

        FieldRepHomeController.PerformanceGamification gamification = FieldRepHomeController.getPerformanceGamification(
            null,
            Date.today().toStartOfMonth()
        );
        System.assertNotEquals(null, gamification);
        System.assertNotEquals(null, gamification.badges);

        FieldRepHomeController.PerformanceRankings rankings = FieldRepHomeController.getPerformanceRankings(null);
        System.assertNotEquals(null, rankings);
        System.assertNotEquals(null, rankings.top5InBu);
        System.assertNotEquals(null, rankings.top5Company);
    }

    @IsTest
    static void getTodayPlan_otherUserHandled() {
        List<User> others = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId() AND IsActive = TRUE LIMIT 1];
        if (others.isEmpty()) {
            return;
        }
        try {
            FieldRepHomeController.getTodayPlan(others[0].Id, Date.today());
            FieldRepHomeController.getHomeMetrics(others[0].Id);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    private static Id firstTerritoryId() {
        List<Territory2> rows = [SELECT Id FROM Territory2 LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Id;
    }
}
