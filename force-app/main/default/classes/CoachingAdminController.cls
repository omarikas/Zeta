public with sharing class CoachingAdminController {

    public class TemplateSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String templateType;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Datetime lastModified;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateSummary> getTemplateSummaries(String searchTerm, String activeFilter) {
        String soql =
            'SELECT Id, Template_Title__c, Template_Type__c, Is_Active__c, Start_Date__c, End_Date__c, LastModifiedDate ' +
            'FROM Coaching_Template__c WHERE Id != NULL';

        String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        if (term != null) {
            soql += ' AND Template_Title__c LIKE :term';
        }
        if (activeFilter == 'Active') {
            soql += ' AND Is_Active__c = TRUE';
        } else if (activeFilter == 'Inactive') {
            soql += ' AND Is_Active__c = FALSE';
        }
        soql += ' WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 200';

        List<TemplateSummary> rows = new List<TemplateSummary>();
        for (Coaching_Template__c template : Database.query(soql)) {
            TemplateSummary row = new TemplateSummary();
            row.id = template.Id;
            row.title = template.Template_Title__c;
            row.templateType = template.Template_Type__c;
            row.isActive = template.Is_Active__c == true;
            row.startDate = template.Start_Date__c;
            row.endDate = template.End_Date__c;
            row.lastModified = template.LastModifiedDate;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static Id createTemplate(String title, String templateType) {
        if (String.isBlank(title)) {
            throw new AuraHandledException('Template title is required.');
        }

        Coaching_Template__c template = new Coaching_Template__c(
            Template_Title__c = title.trim(),
            Template_Type__c = String.isBlank(templateType) ? 'Field Coaching' : templateType,
            Is_Active__c = true,
            Passing_Score__c = 70,
            Questions_JSON__c = '{"version":"1.2","totalQuestions":0,"totalPoints":0,"questions":[]}'
        );
        insert as user template;
        return template.Id;
    }

    @AuraEnabled
    public static Id cloneTemplate(Id templateId) {
        if (templateId == null) {
            throw new AuraHandledException('Template Id is required.');
        }

        List<Coaching_Template__c> sources = [
            SELECT
                Template_Title__c,
                Template_Type__c,
                Is_Active__c,
                Passing_Score__c,
                Description__c,
                Questions_JSON__c,
                Start_Date__c,
                End_Date__c
            FROM Coaching_Template__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (sources.isEmpty()) {
            throw new AuraHandledException('Template was not found.');
        }

        Coaching_Template__c source = sources[0];
        String title = String.isBlank(source.Template_Title__c)
            ? 'Coaching Template'
            : source.Template_Title__c.trim();
        title = title.endsWith('(Copy)') ? title + ' 2' : title + ' (Copy)';

        Coaching_Template__c cloned = new Coaching_Template__c(
            Template_Title__c = title,
            Template_Type__c = String.isBlank(source.Template_Type__c) ? 'Field Coaching' : source.Template_Type__c,
            Is_Active__c = source.Is_Active__c == true,
            Passing_Score__c = source.Passing_Score__c == null ? 70 : source.Passing_Score__c,
            Description__c = rewriteMrWording(source.Description__c),
            Questions_JSON__c = rewriteMrWording(source.Questions_JSON__c),
            Start_Date__c = source.Start_Date__c,
            End_Date__c = source.End_Date__c
        );
        insert as user cloned;
        return cloned.Id;
    }

    private static String rewriteMrWording(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.replaceAll('(?<![A-Za-z])MR(?![A-Za-z])', 'Representative');
    }
}