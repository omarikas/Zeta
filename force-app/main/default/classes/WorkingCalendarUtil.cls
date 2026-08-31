public with sharing class WorkingCalendarUtil {
    /**
     * BRD working week: Saturday through Wednesday.
     * Non-working: Thursday (4), Friday (5) in JavaScript Date.getDay() convention.
     */
    public static Boolean isWorkingDay(Date day) {
        if (day == null) {
            return false;
        }
        Integer dow = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(day), 7);
        // Salesforce Date.dayOfWeek(): 0=Sun ... 6=Sat in some contexts.
        // Use explicit day-of-week via Datetime for consistency.
        Datetime dt = Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
        String dayName = dt.format('u'); // ISO: 1=Mon ... 7=Sun
        Integer isoDow = Integer.valueOf(dayName);
        // Sat=6, Sun=7, Mon=1, Tue=2, Wed=3 are working
        return isoDow == 6 || isoDow == 7 || isoDow <= 3;
    }

    public static Boolean isNonWorkingDay(Date day) {
        return !isWorkingDay(day);
    }

    public static void assertWorkingDay(DateTime startDateTime) {
        if (startDateTime == null) {
            return;
        }
        if (isNonWorkingDay(startDateTime.date())) {
            throw new AuraHandledException(
                'Visits can only be scheduled on working days (Saturday through Wednesday).'
            );
        }
    }

    public static Date addWorkingDays(Date startDate, Integer workingDaysToAdd) {
        if (startDate == null || workingDaysToAdd == null || workingDaysToAdd <= 0) {
            return startDate;
        }
        Date cursor = startDate;
        Integer added = 0;
        while (added < workingDaysToAdd) {
            cursor = cursor.addDays(1);
            if (isWorkingDay(cursor)) {
                added++;
            }
        }
        return cursor;
    }

    public static final Integer DEFAULT_VALIDATION_DUE_WORKING_DAYS = 3;
}
