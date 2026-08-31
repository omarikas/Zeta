@IsTest
private class VisitConflictServiceTest {
    @IsTest
    static void blocksNonWorkingDay() {
        Account account = new Account(Name = 'Conflict Account');
        insert account;
        DateTime thursdayStart = DateTime.newInstance(Date.newInstance(2026, 8, 27), Time.newInstance(10, 0, 0, 0));
        DateTime thursdayEnd = thursdayStart.addHours(1);
        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(UserInfo.getUserId(), thursdayStart, thursdayEnd, null);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected non-working day block');
    }

    @IsTest
    static void blocksVisitOverlap() {
        Account account = new Account(Name = 'Overlap Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        Visit__c existing = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = endDt,
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert existing;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(
                UserInfo.getUserId(),
                startDt.addMinutes(30),
                endDt.addMinutes(30),
                null
            );
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected visit overlap block');
    }

    @IsTest
    static void blocksTotOverlap() {
        Account account = new Account(Name = 'TOT Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        insert new Time_Off_Request__c(
            Type__c = 'Holiday',
            Span_Type__c = 'Full_Day',
            Start_Date_Time__c = startDt.addMinutes(-30),
            End_Date_Time__c = endDt.addMinutes(30),
            Span_Duration__c = 1,
            Stage__c = 'Draft'
        );
        Time_Off_Request__c tot = [
            SELECT Id
            FROM Time_Off_Request__c
            WHERE Type__c = 'Holiday'
            LIMIT 1
        ];
        tot.Stage__c = 'Approved';
        update tot;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(UserInfo.getUserId(), startDt, endDt, null);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected TOT overlap block');
    }

    @IsTest
    static void allowsSameVisitWhenExcluded() {
        Account account = new Account(Name = 'Exclude Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        Visit__c existing = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = endDt,
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert existing;

        Test.startTest();
        VisitConflictService.assertNoConflicts(
            UserInfo.getUserId(),
            startDt.addMinutes(15),
            endDt.addMinutes(15),
            existing.Id
        );
        Test.stopTest();
        System.assert(true);
    }
}
