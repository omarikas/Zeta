public without sharing class HomeOfficeMessageController {

    private static final Integer DEFAULT_LIMIT = 8;
    private static final Integer LOOKBACK_DAYS = 90;

    public class HomeOfficeMessageRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String authorName;
        @AuraEnabled public DateTime publishedOn;
        @AuraEnabled public String publishedLabel;
        @AuraEnabled public String priority;
        @AuraEnabled public String audienceLabel;
        @AuraEnabled public Boolean isHighPriority;
    }

    public class PublishResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<HomeOfficeMessageRow> getMessages() {
        return getActiveMessages(DEFAULT_LIMIT);
    }

    @AuraEnabled(cacheable=true)
    public static List<HomeOfficeMessageRow> getActiveMessages(Integer limitSize) {
        Integer rowLimit = limitSize == null || limitSize < 1 ? DEFAULT_LIMIT : Math.min(limitSize, 25);
        TerritoryHierarchyService.HierarchyLabels labels = resolveCurrentUserLabels();
        DateTime cutoff = System.now().addDays(-LOOKBACK_DAYS);

        List<HomeOfficeMessageRow> rows = new List<HomeOfficeMessageRow>();
        for (Home_Office_Message__c record : [
            SELECT Id, Name, Message_Body__c, Audience_Scope__c, Priority__c, Published_On__c,
                Author__r.Name, Target_Bu_Territory_Id__c, Target_Line_Territory_Id__c,
                Target_District_Territory_Id__c
            FROM Home_Office_Message__c
            WHERE Is_Active__c = TRUE
            AND Published_On__c >= :cutoff
            WITH SYSTEM_MODE
            ORDER BY Priority__c DESC, Published_On__c DESC
            LIMIT 100
        ]) {
            if (!messageAppliesToUser(record, labels)) {
                continue;
            }
            rows.add(toRow(record));
            if (rows.size() >= rowLimit) {
                break;
            }
        }
        return rows;
    }

    @AuraEnabled
    public static PublishResult publishMessage(
        String subject,
        String body,
        String audienceScope,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        String priority
    ) {
        if (String.isBlank(subject) || String.isBlank(body)) {
            throw new AuraHandledException('Subject and message body are required.');
        }

        String scope = String.isBlank(audienceScope) ? 'All Business Units' : audienceScope.trim();
        Home_Office_Message__c record = new Home_Office_Message__c(
            Name = subject.trim().left(80),
            Message_Body__c = body.trim(),
            Audience_Scope__c = scope,
            Priority__c = String.isBlank(priority) ? 'Normal' : priority,
            Published_On__c = System.now(),
            Is_Active__c = true,
            Author__c = UserInfo.getUserId(),
            Target_Bu_Territory_Id__c = normalizeTerritoryId(buTerritoryId),
            Target_Line_Territory_Id__c = normalizeTerritoryId(lineTerritoryId),
            Target_District_Territory_Id__c = normalizeTerritoryId(districtTerritoryId)
        );
        insert as system record;

        PublishResult result = new PublishResult();
        result.recordId = record.Id;
        result.message = 'Message published to ' + buildAudienceLabel(record) + '.';
        return result;
    }

    private static TerritoryHierarchyService.HierarchyLabels resolveCurrentUserLabels() {
        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByUser =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>{ UserInfo.getUserId() });
        return labelsByUser.get(UserInfo.getUserId());
    }

    private static Boolean messageAppliesToUser(
        Home_Office_Message__c record,
        TerritoryHierarchyService.HierarchyLabels labels
    ) {
        String scope = record.Audience_Scope__c;
        if (String.isBlank(scope) || scope == 'All Business Units') {
            return true;
        }
        if (labels == null) {
            return scope == 'All Business Units';
        }
        if (scope == 'Business Unit') {
            return record.Target_Bu_Territory_Id__c == String.valueOf(labels.buTerritoryId);
        }
        if (scope == 'Line') {
            return record.Target_Line_Territory_Id__c == String.valueOf(labels.lineTerritoryId);
        }
        if (scope == 'District') {
            return record.Target_District_Territory_Id__c == String.valueOf(labels.districtTerritoryId);
        }
        return true;
    }

    private static HomeOfficeMessageRow toRow(Home_Office_Message__c record) {
        HomeOfficeMessageRow row = new HomeOfficeMessageRow();
        row.recordId = record.Id;
        row.subject = record.Name;
        row.body = record.Message_Body__c;
        row.authorName = record.Author__r == null ? 'Head Office' : record.Author__r.Name;
        row.publishedOn = record.Published_On__c;
        row.publishedLabel = formatPublishedLabel(record.Published_On__c);
        row.priority = record.Priority__c;
        row.isHighPriority = record.Priority__c == 'High';
        row.audienceLabel = buildAudienceLabel(record);
        return row;
    }

    private static String buildAudienceLabel(Home_Office_Message__c record) {
        if (record.Audience_Scope__c == 'All Business Units') {
            return 'All Business Units';
        }
        if (record.Audience_Scope__c == 'Business Unit') {
            return 'Business Unit';
        }
        if (record.Audience_Scope__c == 'Line') {
            return 'Product Line';
        }
        if (record.Audience_Scope__c == 'District') {
            return 'District';
        }
        return record.Audience_Scope__c;
    }

    private static String formatPublishedLabel(DateTime publishedOn) {
        if (publishedOn == null) {
            return '';
        }
        return publishedOn.format('MMM d, yyyy h:mm a');
    }

    private static String normalizeTerritoryId(String rawValue) {
        if (String.isBlank(rawValue) || rawValue == 'ALL') {
            return null;
        }
        try {
            return String.valueOf((Id) rawValue);
        } catch (Exception ex) {
            return null;
        }
    }
}
