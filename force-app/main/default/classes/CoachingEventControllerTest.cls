@IsTest
private class CoachingEventControllerTest {

    private static final String TEMPLATE_JSON =
        '{"version":"1.2","totalQuestions":2,"totalPoints":12,"questions":[' +
        '{"id":"q1","section":"Core Values","respondent":"both","question":"Enthusiasm","type":"scale",' +
        '"scaleMin":1,"scaleMax":6,"scalePoints":[' +
        '{"value":1,"weight":1,"label":"Never"},{"value":2,"weight":2,"label":"Rarely"},' +
        '{"value":3,"weight":3,"label":"Sometimes"},{"value":4,"weight":4,"label":"Often"},' +
        '{"value":5,"weight":5,"label":"Most of times"},{"value":6,"weight":6,"label":"All the times"}' +
        '],"points":6,"sortOrder":1},' +
        '{"id":"q2","section":"Selling Skills","respondent":"both","question":"Closing","type":"scale",' +
        '"scaleMin":1,"scaleMax":6,"scalePoints":[' +
        '{"value":1,"weight":1,"label":"Never"},{"value":2,"weight":2,"label":"Rarely"},' +
        '{"value":3,"weight":3,"label":"Sometimes"},{"value":4,"weight":4,"label":"Often"},' +
        '{"value":5,"weight":5,"label":"Most of times"},{"value":6,"weight":6,"label":"All the times"}' +
        '],"points":6,"sortOrder":2}' +
        ']}';

    @TestSetup
    static void setup() {
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        Coaching_Template__c template = new Coaching_Template__c(
            Template_Title__c = 'Test Coaching Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true,
            Passing_Score__c = 70,
            Questions_JSON__c = TEMPLATE_JSON,
            Description__c = 'Test coaching template'
        );
        insert template;

        Coaching_Event__c event = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = runUser.Id,
            Manager__c = runUser.Id,
            Status__c = 'Draft'
        );
        insert event;
    }

    @IsTest
    static void testComputeScores_dualScoring() {
        String responses =
            '{"version":"1.0","answers":[' +
            '{"questionId":"q1","managerValue":6,"employeeValue":6},' +
            '{"questionId":"q2","managerValue":3,"employeeValue":5}' +
            ']}';

        CoachingScoringService.ScoreResult result =
            CoachingScoringService.computeScores(TEMPLATE_JSON, responses);

        System.assertEquals(75.0, result.managerTotalScore, 'Manager total should be 75%');
        System.assertEquals(91.67, result.employeeTotalScore, 'Employee total should be ~92%');

        Map<String, Object> sections = (Map<String, Object>) JSON.deserializeUntyped(result.sectionScoresJson);
        System.assert(sections.containsKey('Core Values'));
        System.assert(sections.containsKey('Selling Skills'));
    }

    @IsTest
    static void testComputeScores_strengthsAndWeaknesses() {
        String responses =
            '{"version":"1.0","answers":[' +
            '{"questionId":"q1","managerValue":6,"employeeValue":6},' +
            '{"questionId":"q2","managerValue":1,"employeeValue":1}' +
            ']}';

        CoachingScoringService.ScoreResult result =
            CoachingScoringService.computeScores(TEMPLATE_JSON, responses);

        Map<String, Object> sections = (Map<String, Object>) JSON.deserializeUntyped(result.sectionScoresJson);
        Map<String, Object> selling = (Map<String, Object>) sections.get('Selling Skills');
        List<Object> weaknesses = (List<Object>) selling.get('weaknesses');
        System.assertEquals(1, weaknesses.size(), 'Closing should be a weakness');
    }

    @IsTest
    static void testComputeScores_gaps() {
        String responses =
            '{"version":"1.0","answers":[' +
            '{"questionId":"q1","managerValue":3,"employeeValue":6},' +
            '{"questionId":"q2","managerValue":4,"employeeValue":4}' +
            ']}';

        CoachingScoringService.ScoreResult result =
            CoachingScoringService.computeScores(TEMPLATE_JSON, responses);

        Map<String, Object> sections = (Map<String, Object>) JSON.deserializeUntyped(result.sectionScoresJson);
        Map<String, Object> core = (Map<String, Object>) sections.get('Core Values');
        List<Object> gaps = (List<Object>) core.get('gaps');
        System.assertEquals(1, gaps.size(), 'Should detect gap on q1');
    }

    @IsTest
    static void testBuildActionPlan() {
        String responses =
            '{"version":"1.0","answers":[' +
            '{"questionId":"q1","managerValue":6,"employeeValue":6},' +
            '{"questionId":"q2","managerValue":1,"employeeValue":1}' +
            ']}';

        CoachingScoringService.ScoreResult result =
            CoachingScoringService.computeScores(TEMPLATE_JSON, responses);

        System.assertNotEquals(null, result.recommendedActionPlan);
        System.assert(result.recommendedActionPlan.contains('Closing'), 'Action plan should reference weakness');
    }

    @IsTest
    static void testGetEvaluationData() {
        Coaching_Event__c event = [SELECT Id FROM Coaching_Event__c LIMIT 1];

        CoachingEventController.EvaluationData data =
            CoachingEventController.getEvaluationData(event.Id);
        System.assertNotEquals(null, data.templateJson);
        System.assertEquals('manager', data.userRole);
    }

    @IsTest
    static void testSaveEvaluation() {
        Coaching_Event__c event = [SELECT Id FROM Coaching_Event__c LIMIT 1];

        String responses =
            '{"version":"1.0","answers":[' +
            '{"questionId":"q1","managerValue":5,"managerComments":"Good energy","employeeValue":6,"employeeComments":"Confident"},' +
            '{"questionId":"q2","managerValue":4,"employeeValue":4}' +
            ']}';

        CoachingEventController.SaveResult result = CoachingEventController.saveEvaluation(
            event.Id,
            responses,
            'Available for Scoring'
        );
        System.assertNotEquals(null, result.managerTotalScore);

        Coaching_Event__c updated = [
            SELECT Manager_Total_Score__c, Employee_Total_Score__c, Section_Scores_JSON__c,
                   Status__c, Recommended_Action_Plan__c
            FROM Coaching_Event__c
            WHERE Id = :event.Id
        ];
        System.assertEquals('Available for Scoring', updated.Status__c);
        System.assertNotEquals(null, updated.Manager_Total_Score__c);
        System.assertNotEquals(null, updated.Section_Scores_JSON__c);
        System.assertNotEquals(null, updated.Recommended_Action_Plan__c);
    }

    @IsTest
    static void testRequestSelfEvaluation() {
        Coaching_Event__c event = [SELECT Id FROM Coaching_Event__c LIMIT 1];

        CoachingEventController.requestSelfEvaluation(event.Id);

        event = [SELECT Self_Evaluation_Requested__c, Status__c FROM Coaching_Event__c WHERE Id = :event.Id];
        System.assertEquals(true, event.Self_Evaluation_Requested__c);
        System.assertEquals('Available for Scoring', event.Status__c);
    }

    @IsTest
    static void testPreviousScoreLookup() {
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        Coaching_Event__c completed = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = runUser.Id,
            Manager__c = runUser.Id,
            Status__c = 'Closed',
            Manager_Total_Score__c = 82.5,
            Event_End__c = System.now().addDays(-7)
        );
        insert completed;

        Coaching_Event__c newEvent = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = runUser.Id,
            Manager__c = runUser.Id,
            Status__c = 'Draft'
        );
        insert newEvent;

        CoachingEventController.EvaluationData data =
            CoachingEventController.getEvaluationData(newEvent.Id);
        System.assertEquals(82.5, data.previousScore);
    }
}