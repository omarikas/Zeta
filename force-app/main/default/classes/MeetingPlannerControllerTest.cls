@IsTest
private class MeetingPlannerControllerTest {
    @IsTest
    static void createAndFetchMeeting() {
        List<MeetingPlannerController.RecordTypeOption> types = MeetingPlannerController.getMeetingRecordTypes();
        System.assert(!types.isEmpty(), 'Expected meeting record types');

        String rt = 'Promotional_Activity';
        Boolean found = false;
        for (MeetingPlannerController.RecordTypeOption option : types) {
            if (option.value == rt) {
                found = true;
                break;
            }
        }
        if (!found) {
            rt = types[0].value;
        }

        Datetime startDt = System.now().addDays(1);
        Datetime endDt = startDt.addHours(2);

        Test.startTest();
        MeetingPlannerController.MeetingSummary created = MeetingPlannerController.createMeeting(
            rt,
            startDt,
            endDt,
            'Calendar create test meeting',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, created.id);
        System.assertEquals('Draft', created.status);
        System.assertEquals('Calendar create test meeting', created.title);

        Date weekStart = Date.today().toStartOfWeek();
        Date weekEnd = weekStart.addDays(14);
        List<MeetingPlannerController.MeetingSummary> meetings = MeetingPlannerController.fetchMeetings(
            weekStart,
            weekEnd,
            UserInfo.getUserId()
        );
        Boolean foundMeeting = false;
        for (MeetingPlannerController.MeetingSummary row : meetings) {
            if (row.id == created.id) {
                foundMeeting = true;
                break;
            }
        }
        System.assert(foundMeeting, 'Created meeting should appear in fetchMeetings');
    }
}