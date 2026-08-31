/**
 * Invocable helper for Employee Time Card flows (dates in month).
 * Shared TOT recalc for day entries (TimeOffRequestTOTRecalc / TimeOffRequestTOTRecalcByRange).
 * Span Type Partial (Hours) (API Hours): adds Span_Duration__c/8 on the start date only.
 * Span Type Full Day (API Full_Day): adds 1 per working day from start, based on Span_Duration__c.
 * Legacy Days: adds 1 per calendar day in [start..end] inclusive.
 * Legacy records (no Span_Type__c): falls back to date-range overlap with +1 per day.
 */
public with sharing class EmployeeTimeCardFlowHelper {

    public static void recalcTOTForEmployeeAndRange(Id employeeId, Date startDate, Date endDate) {
        if (employeeId == null || startDate == null || endDate == null || startDate > endDate) {
            return;
        }
        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Date__c, Employee_Time_Card__r.Employee__c, TOT_Days__c, TOT_Days_Excluding_Weekends__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__r.Employee__c = :employeeId
            AND Date__c >= :startDate
            AND Date__c <= :endDate
        ];
        List<Time_Off_Request__c> approved = [
            SELECT Id, CreatedById, Start_Date_Time__c, End_Date_Time__c, Span_Type__c, Span_Duration__c
            FROM Time_Off_Request__c
            WHERE CreatedById = :employeeId
            AND Stage__c = 'Approved'
            AND Start_Date_Time__c <= :endDate
            AND End_Date_Time__c >= :startDate
        ];
        Map<Date, Decimal> totByDate = new Map<Date, Decimal>();
        Map<Date, Decimal> totWeekdayByDate = new Map<Date, Decimal>();
        for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
            totByDate.put(d, 0);
            totWeekdayByDate.put(d, 0);
        }
        String department = getEmployeeDepartment(employeeId);
        accumulateFromApprovedRequests(approved, startDate, endDate, totByDate, totWeekdayByDate, department);
        for (Employee_Time_Card_Day_Entry__c e : entries) {
            Decimal tot = totByDate.get(e.Date__c);
            Decimal totW = totWeekdayByDate.get(e.Date__c);
            if (tot != null && e.TOT_Days__c != tot) {
                e.TOT_Days__c = tot;
            }
            if (totW != null && e.TOT_Days_Excluding_Weekends__c != totW) {
                e.TOT_Days_Excluding_Weekends__c = totW;
            }
        }
        if (!entries.isEmpty()) {
            update entries;
        }
    }

    public static void recalcDayDefinitionsForEmployeeAndRange(Id employeeId, Date startDate, Date endDate) {
        if (employeeId == null || startDate == null || endDate == null || startDate > endDate) {
            return;
        }
        String department = getEmployeeDepartment(employeeId);
        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Date__c, Day_Definition__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__r.Employee__c = :employeeId
            AND Date__c >= :startDate
            AND Date__c <= :endDate
        ];
        for (Employee_Time_Card_Day_Entry__c e : entries) {
            String definition = getDayDefinition(e.Date__c, department);
            if (e.Day_Definition__c != definition) {
                e.Day_Definition__c = definition;
            }
        }
        if (!entries.isEmpty()) {
            update entries;
        }
    }

    public static String getDayDefinition(Date d, String department) {
        return isWeekendDay(d, department) ? 'Weekend Day' : 'Weekday';
    }

    public static String getEmployeeDepartment(Id employeeId) {
        List<User> users = [SELECT Department FROM User WHERE Id = :employeeId LIMIT 1];
        return users.isEmpty() ? null : users[0].Department;
    }

    @TestVisible
    private static void accumulateFromApprovedRequests(
        List<Time_Off_Request__c> approved,
        Date startDate,
        Date endDate,
        Map<Date, Decimal> totByDate,
        Map<Date, Decimal> totWeekdayByDate,
        String department
    ) {
        if (approved == null) {
            return;
        }
        for (Time_Off_Request__c req : approved) {
            if (req.Start_Date_Time__c == null || req.End_Date_Time__c == null) {
                continue;
            }
            Date reqStartDate = req.Start_Date_Time__c.date();
            Date reqEndDate = req.End_Date_Time__c.date();
            if (req.Span_Type__c == 'Hours' && req.Span_Duration__c != null) {
                Decimal inc = req.Span_Duration__c / 8.0;
                for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
                    if (d == reqStartDate) {
                        totByDate.put(d, totByDate.get(d) + inc);
                        if (!isWeekendDay(d, department)) {
                            totWeekdayByDate.put(d, totWeekdayByDate.get(d) + inc);
                        }
                    }
                }
            } else if (req.Span_Type__c == 'Full_Day') {
                Integer remaining = req.Span_Duration__c == null ? 0 : req.Span_Duration__c.intValue();
                Date cursor = reqStartDate;
                while (remaining > 0) {
                    if (!isWeekendDay(cursor, department)) {
                        if (cursor >= startDate && cursor <= endDate) {
                            totByDate.put(cursor, totByDate.get(cursor) + 1);
                            totWeekdayByDate.put(cursor, totWeekdayByDate.get(cursor) + 1);
                        }
                        remaining--;
                    }
                    cursor = cursor.addDays(1);
                }
            } else if (req.Span_Type__c == 'Days') {
                for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
                    if (d >= reqStartDate && d <= reqEndDate) {
                        totByDate.put(d, totByDate.get(d) + 1);
                        if (!isWeekendDay(d, department)) {
                            totWeekdayByDate.put(d, totWeekdayByDate.get(d) + 1);
                        }
                    }
                }
            } else {
                for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
                    if (req.Start_Date_Time__c.date() <= d && req.End_Date_Time__c.date() >= d) {
                        totByDate.put(d, totByDate.get(d) + 1);
                        if (!isWeekendDay(d, department)) {
                            totWeekdayByDate.put(d, totWeekdayByDate.get(d) + 1);
                        }
                    }
                }
            }
        }
    }

    public static Boolean isWeekendDay(Date d, String department) {
        Integer dayOfWeek = Math.mod(Date.newInstance(2000, 1, 2).daysBetween(d), 7);
        if (dayOfWeek < 0) {
            dayOfWeek += 7;
        }
        if (department == 'AM') {
            return dayOfWeek == 5 || dayOfWeek == 6;
        }
        if (department == 'PM') {
            return dayOfWeek == 4 || dayOfWeek == 5;
        }
        return dayOfWeek == 5 || dayOfWeek == 6;
    }

    public class GetDatesInMonthRequest {
        @InvocableVariable(required=true label='Target Year')
        public Integer targetYear;
        @InvocableVariable(required=true label='Target Month')
        public Integer targetMonth;
    }

    public class GetDatesInMonthResult {
        @InvocableVariable(label='Date')
        public Date dateValue;
    }

    @InvocableMethod(label='Get Dates In Month' description='Returns all dates in the given month for time card day entry creation.')
    public static List<List<GetDatesInMonthResult>> getDatesInMonth(List<GetDatesInMonthRequest> requests) {
        List<List<GetDatesInMonthResult>> results = new List<List<GetDatesInMonthResult>>();
        for (GetDatesInMonthRequest req : requests) {
            List<GetDatesInMonthResult> listResult = new List<GetDatesInMonthResult>();
            if (req.targetYear == null || req.targetMonth == null) {
                results.add(listResult);
                continue;
            }
            Date firstDay = Date.newInstance(req.targetYear, req.targetMonth, 1);
            Integer daysInMonth = firstDay.addMonths(1).addDays(-1).day();
            for (Integer d = 1; d <= daysInMonth; d++) {
                GetDatesInMonthResult r = new GetDatesInMonthResult();
                r.dateValue = Date.newInstance(req.targetYear, req.targetMonth, d);
                listResult.add(r);
            }
            results.add(listResult);
        }
        return results;
    }
}