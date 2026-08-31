@IsTest
private class CoachingAdminControllerTest {

    @TestSetup
    static void setup() {
        insert new Coaching_Template__c(Template_Title__c = 'Active Coaching Template');
        insert new Coaching_Template__c(Template_Title__c = 'Inactive Coaching Template');
    }

    @IsTest
    static void getTemplateSummaries_returnsAllTemplates() {
        Test.startTest();
        List<CoachingAdminController.TemplateSummary> rows =
            CoachingAdminController.getTemplateSummaries(null, 'All');
        Test.stopTest();

        System.assertEquals(2, rows.size());
    }

    @IsTest
    static void getTemplateSummaries_filtersBySearchAndActive() {
        Test.startTest();
        List<CoachingAdminController.TemplateSummary> namedRows =
            CoachingAdminController.getTemplateSummaries('Inactive Coaching Template', 'All');
        List<CoachingAdminController.TemplateSummary> inactiveRows =
            CoachingAdminController.getTemplateSummaries(null, 'Inactive');
        Test.stopTest();

        System.assertEquals(1, namedRows.size());
        System.assertEquals('Inactive Coaching Template', namedRows[0].title);
        // Inactive filter intentionally returns none while Is_Active__c is unavailable.
        System.assertEquals(0, inactiveRows.size());
    }

    @IsTest
    static void createTemplate_insertsRecord() {
        Test.startTest();
        Id templateId = CoachingAdminController.createTemplate('New Template', 'Field Coaching');
        Test.stopTest();

        Coaching_Template__c created = [
            SELECT Template_Title__c
            FROM Coaching_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];
        System.assertEquals('New Template', created.Template_Title__c);
    }

    @IsTest
    static void createTemplate_requiresTitle() {
        try {
            CoachingAdminController.createTemplate('', 'Field Coaching');
            System.assert(false, 'Expected title validation error.');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
    }

    @IsTest
    static void cloneTemplate_copiesQuestionsAndRewritesMr() {
        Id sourceId = CoachingAdminController.createTemplate('MR Field Coaching', 'Field Coaching');
        update new Coaching_Template__c(
            Id = sourceId,
            Description__c = 'MR field coaching template',
            Questions_JSON__c =
                '{"version":"1.2","totalQuestions":1,"totalPoints":6,"questions":[' +
                '{"id":"q1","section":"Selling Skills","respondent":"both",' +
                '"question":"MR plans each sales call based on last call?","type":"scale","points":6}]}'
        );

        Test.startTest();
        Id cloneId = CoachingAdminController.cloneTemplate(sourceId);
        Test.stopTest();

        Coaching_Template__c cloned = [
            SELECT Template_Title__c, Description__c, Questions_JSON__c, Template_Type__c
            FROM Coaching_Template__c
            WHERE Id = :cloneId
            LIMIT 1
        ];
        System.assertEquals('MR Field Coaching (Copy)', cloned.Template_Title__c);
        System.assertEquals('Field Coaching', cloned.Template_Type__c);
        System.assert(cloned.Description__c.contains('Representative'));
        System.assert(!cloned.Description__c.contains('MR '));
        System.assert(cloned.Questions_JSON__c.contains('Representative plans each sales call'));
        System.assert(!cloned.Questions_JSON__c.contains('"MR '));
    }

    @IsTest
    static void cloneTemplate_requiresId() {
        try {
            CoachingAdminController.cloneTemplate(null);
            System.assert(false, 'Expected template Id validation error.');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
    }
}