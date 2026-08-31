@IsTest
private class FieldForceAgentActionsTest {
    @TestSetup
    static void setupData() {
        Account primary = new Account(Name = 'Affiliation Primary');
        Account related = new Account(Name = 'Affiliation Related');
        Account visitAccount = new Account(Name = 'Visit Account');
        insert new List<Account>{ primary, related, visitAccount };

        insert new Account_Affiliation__c(
            Primary_Account__c = primary.Id,
            Related_Account__c = related.Id,
            Affiliation_Type__c = 'Practice',
            Is_Active__c = true
        );

        Date monthStart = Date.today().toStartOfMonth();
        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = UserInfo.getUserId(),
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1)
        );
        insert timeCard;

        insert new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = visitAccount.Id,
            Target_Visit_Frequency__c = 4,
            Actual_Visits__c = 1,
            Potentiality__c = 'A',
            Rep__c = UserInfo.getUserId()
        );

        insert new Account_Territory_Fields__c(
            Account__c = visitAccount.Id,
            Territory2_Id__c = '0MNxxxxxxxxxxxxxxx',
            Classification__c = 'A',
            Is_Active__c = true
        );

        Product2 product = new Product2(Name = 'Agentforce Test Product', IsActive = true);
        insert product;

        insert new Account_Territory_Product_Fields__c(
            Account__c = visitAccount.Id,
            Product2_Id__c = String.valueOf(product.Id),
            Territory2_Id__c = '0MNxxxxxxxxxxxxxxx',
            Is_Active__c = true
        );

        insert new Product_Territory_Alignment__c(
            Product2_Id__c = String.valueOf(product.Id),
            Territory2_Id__c = '0MNxxxxxxxxxxxxxxx',
            Is_Active__c = true,
            Effective_Start_Date__c = Date.today().addDays(-30)
        );

        Datetime startDt = Datetime.now().addHours(2);
        Visit__c visit = new Visit__c(
            Account__c = visitAccount.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = startDt.addHours(1),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned',
            Visit_Objective__c = 'Detail key brands'
        );
        insert visit;

        insert new Visit_Attendee__c(
            Visit__c = visit.Id,
            Account__c = visitAccount.Id,
            Is_Primary__c = true,
            Role__c = 'Attendee',
            Display_Order__c = 1
        );

        insert new Visit_Product_Detail__c(
            Visit__c = visit.Id,
            Product2__c = product.Id,
            Detail_Type__c = 'Detail',
            Display_Order__c = 1,
            Notes__c = 'Key message'
        );

        insert new Visit_Sample__c(
            Visit__c = visit.Id,
            Quantity__c = 2
        );
    }

    @IsTest
    static void getHomeDashboardBrief_returnsSummary() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceHomeAgentAction.getHomeDashboardBrief(
            new List<FieldForceAgentActions.HomeDashboardRequest>{ new FieldForceAgentActions.HomeDashboardRequest() }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one home brief result.');
        System.assertNotEquals(null, results[0].summary, 'Expected a home summary.');
        System.assert(results[0].summary.contains('Field Rep Home'), 'Expected home context label.');
    }

    @IsTest
    static void getPlannerWeekBrief_returnsSummary() {
        FieldForceAgentActions.PlannerWeekRequest request = new FieldForceAgentActions.PlannerWeekRequest();
        request.weekStartDate = Date.today().toStartOfWeek();

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForcePlannerAgentAction.getPlannerWeekBrief(
            new List<FieldForceAgentActions.PlannerWeekRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one planner brief result.');
        System.assertNotEquals(null, results[0].summary, 'Expected a planner summary.');
        System.assert(results[0].summary.contains('Field Planner'), 'Expected planner context label.');
    }

    @IsTest
    static void getAccountFieldBrief_requiresAccountId() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAccountAgentAction.getAccountFieldBrief(
            new List<FieldForceAgentActions.AccountFieldRequest>{
                new FieldForceAgentActions.AccountFieldRequest()
            }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one account brief result.');
        System.assert(
            results[0].summary.contains('Account id is required'),
            'Expected missing account id message.'
        );
    }

    @IsTest
    static void getAccountFieldBrief_returnsSummaryForAccount() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Visit Account' LIMIT 1];

        FieldForceAgentActions.AccountFieldRequest request = new FieldForceAgentActions.AccountFieldRequest();
        request.accountId = account.Id;

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAccountAgentAction.getAccountFieldBrief(
            new List<FieldForceAgentActions.AccountFieldRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one account brief result.');
        System.assert(results[0].summary.contains('Visit Account'), 'Expected account name in summary.');
    }

    @IsTest
    static void getAccountsTabBrief_returnsSummary() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAccountsTabAgentAction.getAccountsTabBrief(
            new List<FieldForceAgentActions.AccountsTabRequest>{
                new FieldForceAgentActions.AccountsTabRequest()
            }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one accounts tab brief result.');
        System.assertNotEquals(null, results[0].summary, 'Expected accounts tab summary.');
        System.assert(results[0].summary.contains('Accounts tab'), 'Expected accounts tab context label.');
    }

    @IsTest
    static void getVisitCallBrief_requiresVisitId() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceVisitAgentAction.getVisitCallBrief(
            new List<FieldForceAgentActions.VisitCallRequest>{ new FieldForceAgentActions.VisitCallRequest() }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one visit brief result.');
        System.assert(
            results[0].summary.contains('Visit id is required'),
            'Expected missing visit id message.'
        );
    }

    @IsTest
    static void getVisitCallBrief_returnsSummaryForVisit() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        FieldForceAgentActions.VisitCallRequest request = new FieldForceAgentActions.VisitCallRequest();
        request.visitId = visit.Id;

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceVisitAgentAction.getVisitCallBrief(
            new List<FieldForceAgentActions.VisitCallRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one visit brief result.');
        System.assert(results[0].summary.contains('Visit call context'), 'Expected visit context label.');
        System.assert(results[0].summary.contains('Visit Account'), 'Expected account name.');
    }

    @IsTest
    static void getAffiliationBrief_requiresAccountOrVisit() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAffiliationAgentAction.getAffiliationBrief(
            new List<FieldForceAgentActions.AffiliationRequest>{
                new FieldForceAgentActions.AffiliationRequest()
            }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one affiliation brief result.');
        System.assert(
            results[0].summary.contains('Account id'),
            'Expected missing account guidance.'
        );
    }

    @IsTest
    static void getAffiliationBrief_returnsSummaryForAccount() {
        Account primary = [SELECT Id FROM Account WHERE Name = 'Affiliation Primary' LIMIT 1];
        FieldForceAgentActions.AffiliationRequest request = new FieldForceAgentActions.AffiliationRequest();
        request.accountId = primary.Id;

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAffiliationAgentAction.getAffiliationBrief(
            new List<FieldForceAgentActions.AffiliationRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one affiliation brief result.');
        System.assert(results[0].summary.contains('Affiliation Primary'), 'Expected account name.');
        System.assert(results[0].summary.contains('Affiliation Related'), 'Expected related account.');
    }

    @IsTest
    static void getAffiliationBrief_fromVisit() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        FieldForceAgentActions.AffiliationRequest request = new FieldForceAgentActions.AffiliationRequest();
        request.visitId = visit.Id;

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAffiliationAgentAction.getAffiliationBrief(
            new List<FieldForceAgentActions.AffiliationRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one affiliation brief result.');
        System.assert(results[0].summary.contains('Affiliation network'), 'Expected affiliation label.');
    }

    @IsTest
    static void getTerritoryProductBrief_returnsSummary() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Visit Account' LIMIT 1];
        FieldForceAgentActions.TerritoryProductRequest request = new FieldForceAgentActions.TerritoryProductRequest();
        request.accountId = account.Id;

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceTerritoryProductAgentAction.getTerritoryProductBrief(
            new List<FieldForceAgentActions.TerritoryProductRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one territory product brief result.');
        System.assertNotEquals(null, results[0].summary, 'Expected territory product summary.');
        System.assert(
            results[0].summary.contains('Territory product'),
            'Expected territory product context label.'
        );
    }
}