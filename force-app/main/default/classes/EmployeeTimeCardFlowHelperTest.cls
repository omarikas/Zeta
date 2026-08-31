@IsTest
private class EmployeeTimeCardFlowHelperTest {

    private static Map<Date, Decimal> mapRange(Date startDate, Date endDate) {
        Map<Date, Decimal> m = new Map<Date, Decimal>();
        for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
            m.put(d, 0);
        }
        return m;
    }

    @IsTest
    static void getDatesInMonth_returns_days_in_month() {
        EmployeeTimeCardFlowHelper.GetDatesInMonthRequest req = new EmployeeTimeCardFlowHelper.GetDatesInMonthRequest();
        req.targetYear = 2026;
        req.targetMonth = 3;
        List<List<EmployeeTimeCardFlowHelper.GetDatesInMonthResult>> out = EmployeeTimeCardFlowHelper.getDatesInMonth(
            new List<EmployeeTimeCardFlowHelper.GetDatesInMonthRequest>{ req }
        );
        System.assertEquals(31, out[0].size());
    }

    @IsTest
    static void getDatesInMonth_nullYear_returns_empty() {
        EmployeeTimeCardFlowHelper.GetDatesInMonthRequest req = new EmployeeTimeCardFlowHelper.GetDatesInMonthRequest();
        List<List<EmployeeTimeCardFlowHelper.GetDatesInMonthResult>> out = EmployeeTimeCardFlowHelper.getDatesInMonth(
            new List<EmployeeTimeCardFlowHelper.GetDatesInMonthRequest>{ req }
        );
        System.assertEquals(0, out[0].size());
    }

    @IsTest
    static void isWeekendDay_department_shifts() {
        Date friday = Date.newInstance(2026, 5, 15);
        Date thursday = Date.newInstance(2026, 5, 14);
        Date saturday = Date.newInstance(2026, 5, 16);
        System.assert(EmployeeTimeCardFlowHelper.isWeekendDay(friday, 'AM'));
        System.assert(EmployeeTimeCardFlowHelper.isWeekendDay(saturday, 'AM'));
        System.assert(!EmployeeTimeCardFlowHelper.isWeekendDay(thursday, 'AM'));
        System.assert(EmployeeTimeCardFlowHelper.isWeekendDay(thursday, 'PM'));
        System.assert(EmployeeTimeCardFlowHelper.isWeekendDay(friday, 'PM'));
        System.assert(!EmployeeTimeCardFlowHelper.isWeekendDay(saturday, 'PM'));
    }

    @IsTest
    static void getDayDefinition_returns_expected_values() {
        Date friday = Date.newInstance(2026, 5, 15);
        Date saturday = Date.newInstance(2026, 5, 16);
        System.assertEquals('Weekend Day', EmployeeTimeCardFlowHelper.getDayDefinition(friday, 'AM'));
        System.assertEquals('Weekend Day', EmployeeTimeCardFlowHelper.getDayDefinition(friday, 'PM'));
        System.assertEquals('Weekday', EmployeeTimeCardFlowHelper.getDayDefinition(saturday, 'PM'));
    }

    @IsTest
    static void recalcTOTForEmployeeAndRange_executes() {
        Date d0 = Date.today();
        EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(UserInfo.getUserId(), d0.addDays(-2), d0.addDays(2));
        EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(null, d0, d0);
        EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(UserInfo.getUserId(), d0.addDays(2), d0);
        EmployeeTimeCardFlowHelper.recalcDayDefinitionsForEmployeeAndRange(UserInfo.getUserId(), d0.addDays(-2), d0.addDays(2));
        EmployeeTimeCardFlowHelper.recalcDayDefinitionsForEmployeeAndRange(null, d0, d0);
        EmployeeTimeCardFlowHelper.getEmployeeDepartment(UserInfo.getUserId());
    }

    @IsTest
    static void accumulate_hours_partial_day() {
        Date d0 = Date.newInstance(2026, 6, 1);
        Map<Date, Decimal> tot = mapRange(d0, d0);
        Map<Date, Decimal> totW = mapRange(d0, d0);
        Time_Off_Request__c req = new Time_Off_Request__c(
            Start_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(9, 0, 0, 0)),
            End_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(13, 0, 0, 0)),
            Span_Type__c = 'Hours',
            Span_Duration__c = 4
        );
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
            new List<Time_Off_Request__c>{ req },
            d0,
            d0,
            tot,
            totW,
            'AM'
        );
        System.assertEquals(0.5, tot.get(d0));
    }

    @IsTest
    static void accumulate_full_day_span() {
        Date d0 = Date.newInstance(2026, 6, 2);
        Map<Date, Decimal> tot = mapRange(d0, d0);
        Map<Date, Decimal> totW = mapRange(d0, d0);
        Time_Off_Request__c req = new Time_Off_Request__c(
            Start_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(8, 0, 0, 0)),
            End_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(23, 59, 59, 0)),
            Span_Type__c = 'Full_Day',
            Span_Duration__c = 1
        );
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
            new List<Time_Off_Request__c>{ req },
            d0,
            d0,
            tot,
            totW,
            'AM'
        );
        System.assertEquals(1, tot.get(d0));
    }

    @IsTest
    static void accumulate_legacy_days_and_blank_span() {
        Date d0 = Date.newInstance(2026, 6, 3);
        Date d1 = Date.newInstance(2026, 6, 4);
        Map<Date, Decimal> tot = mapRange(d0, d1);
        Map<Date, Decimal> totW = mapRange(d0, d1);
        Time_Off_Request__c daysReq = new Time_Off_Request__c(
            Start_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(0, 0, 0, 0)),
            End_Date_Time__c = Datetime.newInstance(d1, Time.newInstance(23, 59, 59, 0)),
            Span_Type__c = 'Days',
            Span_Duration__c = 2
        );
        Time_Off_Request__c legacyReq = new Time_Off_Request__c(
            Start_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(10, 0, 0, 0)),
            End_Date_Time__c = Datetime.newInstance(d0, Time.newInstance(18, 0, 0, 0)),
            Span_Type__c = null,
            Span_Duration__c = null
        );
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
            new List<Time_Off_Request__c>{ daysReq, legacyReq },
            d0,
            d1,
            tot,
            totW,
            'AM'
        );
        System.assertEquals(2, tot.get(d0));
        System.assertEquals(1, tot.get(d1));
    }

    @IsTest
    static void accumulate_skips_null_dates_and_null_list() {
        Date d0 = Date.newInstance(2026, 6, 5);
        Map<Date, Decimal> tot = mapRange(d0, d0);
        Map<Date, Decimal> totW = mapRange(d0, d0);
        Time_Off_Request__c bad = new Time_Off_Request__c(Span_Type__c = 'Hours', Span_Duration__c = 4);
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
            new List<Time_Off_Request__c>{ bad },
            d0,
            d0,
            tot,
            totW,
            'AM'
        );
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(null, d0, d0, tot, totW, 'AM');
        System.assertEquals(0, tot.get(d0));
    }
}