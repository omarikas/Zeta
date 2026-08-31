public with sharing class MeetingPlannerController {
  public class MeetingSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public Id pharmaProjectId;
    @AuraEnabled
    public String pharmaProjectName;
  }

  public class RecordTypeOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public RecordTypeOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<RecordTypeOption> getMeetingRecordTypes() {
    List<RecordTypeOption> options = new List<RecordTypeOption>();
    for (RecordType recordType : [
      SELECT Name, DeveloperName
      FROM RecordType
      WHERE
        SObjectType = 'Meeting__c'
        AND IsActive = TRUE
        AND DeveloperName IN (
          'Speaker_Meeting',
          'Regional_Standalone',
          'National_Standalone',
          'Advisory_Board',
          'RTD',
          'AV_Action',
          'Promotional_Activity'
        )
      WITH USER_MODE
      ORDER BY Name ASC
    ]) {
      options.add(new RecordTypeOption(recordType.Name, recordType.DeveloperName));
    }
    return options;
  }

  @AuraEnabled
  public static List<MeetingSummary> fetchMeetings(Date weekStart, Date weekEnd, Id contextUserId) {
    if (weekStart == null || weekEnd == null) {
      throw new AuraHandledException('Week start and end dates are required.');
    }
    Id userId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    DateTime rangeStart = DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
    List<MeetingSummary> results = new List<MeetingSummary>();
    for (Meeting__c meeting : [
      SELECT
        Id,
        Name,
        Status__c,
        Objectives__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Pharma_Project__c,
        Pharma_Project__r.Name,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE
        OwnerId = :userId
        AND Start_Date_Time__c < :rangeEnd
        AND End_Date_Time__c > :rangeStart
        AND Status__c NOT IN ('Cancelled')
      WITH USER_MODE
      ORDER BY Start_Date_Time__c ASC
    ]) {
      results.add(mapMeeting(meeting));
    }
    return results;
  }

  @AuraEnabled
  public static MeetingSummary createMeeting(
    String recordTypeDeveloperName,
    DateTime startDateTime,
    DateTime endDateTime,
    String title,
    Id pharmaProjectId
  ) {
    if (startDateTime == null || endDateTime == null || endDateTime <= startDateTime) {
      throw new AuraHandledException('Meeting needs a valid start and end time.');
    }
    if (String.isBlank(title)) {
      throw new AuraHandledException('Meeting title is required.');
    }
    String rtDevName = String.isBlank(recordTypeDeveloperName)
      ? 'Promotional_Activity'
      : recordTypeDeveloperName.trim();
    List<RecordType> recordTypes = [
      SELECT Id, DeveloperName, Name
      FROM RecordType
      WHERE SObjectType = 'Meeting__c' AND IsActive = TRUE AND DeveloperName = :rtDevName
      WITH USER_MODE
      LIMIT 1
    ];
    if (recordTypes.isEmpty()) {
      throw new AuraHandledException('Meeting record type not found: ' + rtDevName);
    }

    Meeting__c meeting = new Meeting__c(
      RecordTypeId = recordTypes[0].Id,
      Status__c = 'Draft',
      Start_Date_Time__c = startDateTime,
      End_Date_Time__c = endDateTime,
      Objectives__c = title.trim()
    );
    if (pharmaProjectId != null) {
      meeting.Pharma_Project__c = pharmaProjectId;
    }
    insert as user meeting;

    List<Meeting__c> created = [
      SELECT
        Id,
        Name,
        Status__c,
        Objectives__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Pharma_Project__c,
        Pharma_Project__r.Name,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE Id = :meeting.Id
      WITH USER_MODE
      LIMIT 1
    ];
    if (!created.isEmpty()) {
      return mapMeeting(created[0]);
    }

    // Insert succeeded but re-query returned nothing (FLS/sharing edge case).
    // Still return a usable summary so the calendar can show the new meeting.
    MeetingSummary fallback = new MeetingSummary();
    fallback.id = meeting.Id;
    fallback.name = meeting.Name;
    fallback.title = title.trim();
    fallback.status = 'Draft';
    fallback.startDateTime = startDateTime;
    fallback.endDateTime = endDateTime;
    fallback.pharmaProjectId = pharmaProjectId;
    fallback.recordTypeDeveloperName = recordTypes[0].DeveloperName;
    fallback.recordTypeLabel = recordTypes[0].Name;
    return fallback;
  }

  private static MeetingSummary mapMeeting(Meeting__c meeting) {
    MeetingSummary summary = new MeetingSummary();
    summary.id = meeting.Id;
    summary.name = meeting.Name;
    summary.title = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c : meeting.Name;
    summary.status = meeting.Status__c;
    summary.startDateTime = meeting.Start_Date_Time__c;
    summary.endDateTime = meeting.End_Date_Time__c;
    summary.pharmaProjectId = meeting.Pharma_Project__c;
    summary.pharmaProjectName = meeting.Pharma_Project__r != null
      ? meeting.Pharma_Project__r.Name
      : null;
    summary.recordTypeDeveloperName = meeting.RecordType != null
      ? meeting.RecordType.DeveloperName
      : null;
    summary.recordTypeLabel = meeting.RecordType != null ? meeting.RecordType.Name : null;
    return summary;
  }
}