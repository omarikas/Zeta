@IsTest
private class CoachingEventServicesTest {

    private static final String TEMPLATE_JSON =
        '{"version":"1.2","totalQuestions":2,"totalPoints":12,"questions":[' +
        '{"id":"q1","section":"Core Values","respondent":"both","question":"Enthusiasm","type":"scale",' +
        '"scaleMin":1,"scaleMax":6,"scalePoints":[' +
        '{"value":1,"weight":1,"label":"Never"},{"value":6,"weight":6,"label":"All the times"}' +
        '],"points":6,"sortOrder":1},' +
        '{"id":"q2","section":"Selling Skills","respondent":"both","question":"Closing","type":"scale",' +
        '"scaleMin":1,"scaleMax":6,"scalePoints":[' +
        '{"value":1,"weight":1,"label":"Never"},{"value":6,"weight":6,"label":"All the times"}' +
        '],"points":6,"sortOrder":2}' +
        ']}';

    @TestSetup
    static void setup() {
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        Coaching_Template__c template = new Coaching_Template__c(
            Template_Title__c = 'Notifier Test Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true,
            Passing_Score__c = 70,
            Questions_JSON__c = TEMPLATE_JSON,
            Description__c = 'Test'
        );
        insert template;

        insert new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = runUser.Id,
            Manager__c = runUser.Id,
            Status__c = 'Draft'
        );
    }

    @IsTest
    static void testSectionScoreSync_buildRows() {
        String sectionJson =
            '{"Core Values":{"managerScore":83.3,"employeeScore":66.7},' +
            '"Selling Skills":{"managerScore":50.0,"employeeScore":75.0}}';

        List<Coaching_Event_Section_Score__c> rows =
            CoachingEventSectionScoreSync.buildRows(null, sectionJson);
        System.assertEquals(0, rows.size());

        Coaching_Event__c event = [SELECT Id FROM Coaching_Event__c LIMIT 1];
        rows = CoachingEventSectionScoreSync.buildRows(event.Id, sectionJson);
        System.assertEquals(2, rows.size());
    }

    @IsTest
    static void testSectionScoreSync_triggerOnEvaluationSave() {
        Coaching_Event__c event = [SELECT Id FROM Coaching_Event__c LIMIT 1];
        String responses =
            '{"version":"1.0","answers":[' +
            '{"questionId":"q1","managerValue":6,"employeeValue":4},' +
            '{"questionId":"q2","managerValue":3,"employeeValue":5}' +
            ']}';

        Test.startTest();
        CoachingEventController.saveEvaluation(event.Id, responses, 'Available for Scoring');
        Test.stopTest();

        List<Coaching_Event_Section_Score__c> rows = [
            SELECT Section_Name__c, Manager_Score__c, Employee_Score__c
            FROM Coaching_Event_Section_Score__c
            WHERE Coaching_Event__c = :event.Id
            ORDER BY Section_Name__c
        ];
        System.assertEquals(2, rows.size(), 'Section score rows should be created');
        System.assertEquals('Core Values', rows[0].Section_Name__c);
        System.assertEquals('Selling Skills', rows[1].Section_Name__c);
    }

    @IsTest
    static void testNotifier_insertAndStatusUpdate() {
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        Test.startTest();
        Coaching_Event__c created = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = runUser.Id,
            Manager__c = runUser.Id,
            Status__c = 'Draft'
        );
        insert created;

        created.Status__c = 'Available for Scoring';
        update created;

        created.Manager_Total_Score__c = 72.5;
        created.Employee_Total_Score__c = 68.0;
        update created;
        Test.stopTest();

        System.assertNotEquals(null, created.Id);
    }

    @IsTest
    static void testNotifier_selfEvaluationFlags() {
        Coaching_Event__c event = [SELECT Id FROM Coaching_Event__c LIMIT 1];

        Test.startTest();
        CoachingEventController.requestSelfEvaluation(event.Id);
        event = [
            SELECT Self_Evaluation_Requested__c
            FROM Coaching_Event__c
            WHERE Id = :event.Id
        ];
        System.assertEquals(true, event.Self_Evaluation_Requested__c);

        event.Self_Evaluation_Completed__c = true;
        update event;
        Test.stopTest();
    }
}