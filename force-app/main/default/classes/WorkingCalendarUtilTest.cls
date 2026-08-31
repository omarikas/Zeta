@IsTest
private class WorkingCalendarUtilTest {
    @IsTest
    static void workingDays_matchSatThroughWed() {
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 22))); // Sat
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 23))); // Sun
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 24))); // Mon
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 25))); // Tue
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 26))); // Wed
        System.assertEquals(false, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 27))); // Thu
        System.assertEquals(false, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 28))); // Fri
    }

    @IsTest
    static void addWorkingDays_skipsThuFri() {
        Date result = WorkingCalendarUtil.addWorkingDays(Date.newInstance(2026, 8, 26), 1); // Wed +1 => Sat
        System.assertEquals(Date.newInstance(2026, 8, 29), result);
    }
}
