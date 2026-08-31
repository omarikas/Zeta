public with sharing class CoachingModuleSeed {

    public class SeedResult {
        public Id templateId;
        public Id eventId;
        public String message;
    }

    /**
     * Seeds / refreshes pharma field coaching template from static resource.
     * Run: CoachingModuleSeed.seedDemoData(null, null);
     * Or pass existing User Ids for Employee (rep) and Manager (DM).
     */
    public static SeedResult seedDemoData(Id employeeUserId, Id managerUserId) {
        SeedResult result = new SeedResult();

        String templateJson = getPharmaTemplateJson();

        Coaching_Template__c template;
        List<Coaching_Template__c> existing = [
            SELECT Id
            FROM Coaching_Template__c
            WHERE Template_Title__c = 'Pharma Field Coaching — MR Call Skills'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            template = existing[0];
            template.Template_Type__c = 'Field Coaching';
            template.Is_Active__c = true;
            template.Passing_Score__c = 70;
            template.Description__c =
                'MR field coaching — Selling Skills, Soft Skills, Technical Skills, Product Knowledge, and Core Values.';
            template.Questions_JSON__c = templateJson;
            update template;
        } else {
            template = new Coaching_Template__c(
                Template_Title__c = 'Pharma Field Coaching — MR Call Skills',
                Template_Type__c = 'Field Coaching',
                Is_Active__c = true,
                Passing_Score__c = 70,
                Description__c =
                    'MR field coaching — Selling Skills, Soft Skills, Technical Skills, Product Knowledge, and Core Values.',
                Questions_JSON__c = templateJson
            );
            insert template;
        }
        result.templateId = template.Id;

        Id repId = employeeUserId;
        Id mgrId = managerUserId;

        if (repId == null || mgrId == null) {
            List<User> users = [
                SELECT Id, Username
                FROM User
                WHERE IsActive = true
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 10
            ];
            if (users.size() >= 2) {
                if (repId == null) {
                    repId = users[0].Id;
                }
                if (mgrId == null) {
                    mgrId = users[1].Id;
                }
            } else if (!users.isEmpty()) {
                if (repId == null) {
                    repId = users[0].Id;
                }
                if (mgrId == null) {
                    mgrId = users[0].Id;
                }
            }
        }

        String partialResponses =
            '{"version":"1.0","templateVersion":"1.2","answers":[' +
            '{"questionId":"q1","managerValue":5,"managerScore":5,"managerLabel":"Most of times",' +
            '"managerComments":"Solid pre-call feedback preparation",' +
            '"employeeValue":6,"employeeScore":6,"employeeLabel":"All the times",' +
            '"employeeComments":"I prepare product/competitor/prescriber feedback before each call"},' +
            '{"questionId":"q3","managerValue":5,"managerScore":5,"managerLabel":"Most of times",' +
            '"employeeValue":5,"employeeScore":5,"employeeLabel":"Most of times"}' +
            '],"computedAt":"2026-08-04T12:00:00Z"}';

        CoachingScoringService.ScoreResult scores =
            CoachingScoringService.computeScores(templateJson, partialResponses);

        Coaching_Event__c event = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = repId,
            Manager__c = mgrId,
            Status__c = 'Draft',
            Event_Start__c = System.now(),
            Event_End__c = System.now().addDays(2),
            Responses_JSON__c = partialResponses,
            Manager_Total_Score__c = scores.managerTotalScore,
            Employee_Total_Score__c = scores.employeeTotalScore,
            Section_Scores_JSON__c = scores.sectionScoresJson
        );
        insert event;
        result.eventId = event.Id;
        result.message = 'Seeded template ' + template.Id + ' and event ' + event.Id;
        return result;
    }

    /**
     * Upserts only the active MR call-skills template (no demo event).
     * Run: CoachingModuleSeed.loadTemplate();
     */
    public static Id loadTemplate() {
        String templateJson = getPharmaTemplateJson();
        List<Coaching_Template__c> existing = [
            SELECT Id
            FROM Coaching_Template__c
            WHERE Template_Title__c = 'Pharma Field Coaching — MR Call Skills'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Coaching_Template__c template;
        if (!existing.isEmpty()) {
            template = existing[0];
            template.Template_Type__c = 'Field Coaching';
            template.Is_Active__c = true;
            template.Passing_Score__c = 70;
            template.Description__c =
                'MR field coaching — Selling Skills, Soft Skills, Technical Skills, Product Knowledge, and Core Values.';
            template.Questions_JSON__c = templateJson;
            update template;
        } else {
            template = new Coaching_Template__c(
                Template_Title__c = 'Pharma Field Coaching — MR Call Skills',
                Template_Type__c = 'Field Coaching',
                Is_Active__c = true,
                Passing_Score__c = 70,
                Description__c =
                    'MR field coaching — Selling Skills, Soft Skills, Technical Skills, Product Knowledge, and Core Values.',
                Questions_JSON__c = templateJson
            );
            insert template;
        }
        return template.Id;
    }

    @TestVisible
    private static String getPharmaTemplateJson() {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'pharma_field_coaching_template'
            LIMIT 1
        ];
        if (!resources.isEmpty() && resources[0].Body != null) {
            return resources[0].Body.toString();
        }
        // Fallback if static resource is not deployed yet
        return '{"version":"1.2","totalQuestions":0,"totalPoints":0,"questions":[]}';
    }
}