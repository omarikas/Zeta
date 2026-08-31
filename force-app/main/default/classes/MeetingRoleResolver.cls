public with sharing class MeetingRoleResolver {
    public static final String ROLE_ORGANIZER = 'Organizer';
    public static final String ROLE_APPROVER = 'Approver';
    public static final String ROLE_SECOND_APPROVER = 'SecondApprover';
    public static final String ROLE_CO_ORGANIZER = 'CoOrganizer';
    public static final String ROLE_PARTICIPANT = 'Participant';
    public static final String ROLE_SUPER_USER = 'SuperUser';

    public static Set<String> resolveRoles(Id meetingId, Id userId) {
        Set<String> roles = new Set<String>();
        if (meetingId == null || userId == null) {
            return roles;
        }

        if (FeatureManagement.checkPermission('Meeting_Super_User')) {
            roles.add(ROLE_SUPER_USER);
        }

        Meeting__c meeting = [
            SELECT Id, OwnerId
            FROM Meeting__c
            WHERE Id = :meetingId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (meeting.OwnerId == userId) {
            roles.add(ROLE_ORGANIZER);
        }

        for (Meeting_Member__c member : [
            SELECT Type__c, Colleague__c
            FROM Meeting_Member__c
            WHERE Meeting__c = :meetingId AND Colleague__c = :userId
            WITH SYSTEM_MODE
        ]) {
            String memberType = member.Type__c;
            if (memberType == 'Approver') {
                roles.add(ROLE_APPROVER);
            } else if (memberType == 'Second Approver') {
                roles.add(ROLE_SECOND_APPROVER);
            } else if (memberType == 'CoOrganizer') {
                roles.add(ROLE_CO_ORGANIZER);
            } else if (memberType == 'Organizer') {
                roles.add(ROLE_ORGANIZER);
            } else if (memberType == 'Participant') {
                roles.add(ROLE_PARTICIPANT);
            }
        }

        return roles;
    }
}