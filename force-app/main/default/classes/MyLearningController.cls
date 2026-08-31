public with sharing class MyLearningController {
    public class CourseCard {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id materialId;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Boolean issueCertificate;
        @AuraEnabled public Boolean canShowCertificate;
    }

    public class CurriculumItem {
        @AuraEnabled public Id materialId;
        @AuraEnabled public Id instanceId;
        @AuraEnabled public String title;
        @AuraEnabled public String materialType;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String materialUrl;
        @AuraEnabled public Decimal duration;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Integer sortOrder;
    }

    public class CoursePlayerDto {
        @AuraEnabled public Id courseInstanceId;
        @AuraEnabled public Id courseMaterialId;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Boolean issueCertificate;
        @AuraEnabled public Boolean canShowCertificate;
        @AuraEnabled public List<CurriculumItem> curriculum;
        @AuraEnabled public Id selectedInstanceId;
    }

    public class QuizQuestionDto {
        @AuraEnabled public String id;
        @AuraEnabled public String question;
        @AuraEnabled public String type;
        @AuraEnabled public List<String> options;
        @AuraEnabled public Decimal points;
        @AuraEnabled public Integer scaleMin;
        @AuraEnabled public Integer scaleMax;
        @AuraEnabled public String scaleMinLabel;
        @AuraEnabled public String scaleMaxLabel;
    }

    public class QuizTakeDto {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id materialId;
        @AuraEnabled public String title;
        @AuraEnabled public Decimal passingScore;
        @AuraEnabled public Decimal timeLimitMinutes;
        @AuraEnabled public Decimal maxAttempts;
        @AuraEnabled public Decimal attemptNumber;
        @AuraEnabled public Boolean showResults;
        @AuraEnabled public Boolean canAttempt;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal lastScore;
        @AuraEnabled public List<QuizQuestionDto> questions;
    }

    public class QuizSubmitResult {
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal earnedPoints;
        @AuraEnabled public Decimal totalPoints;
        @AuraEnabled public Boolean passed;
        @AuraEnabled public Boolean showResults;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal courseProgress;
        @AuraEnabled public Boolean courseCompleted;
        @AuraEnabled public Boolean canShowCertificate;
        @AuraEnabled public Map<String, Object> questionResults;
    }

    public class CertificateDto {
        @AuraEnabled public String learnerName;
        @AuraEnabled public String courseTitle;
        @AuraEnabled public String completedOn;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String logoUrl;
        @AuraEnabled public String templateHtml;
        @AuraEnabled public String renderedHtml;
    }

    @AuraEnabled(cacheable=true)
    public static List<CourseCard> getMyCourses() {
        Id userId = UserInfo.getUserId();
        List<CourseCard> cards = new List<CourseCard>();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Score__c,
                Completed_On__c,
                Material__c,
                Material__r.Title__c,
                Material__r.Description__c,
                Material__r.Material_Type__c,
                Material__r.Issue_Certificate__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :userId AND Material__r.Material_Type__c = 'Course'
            ORDER BY Material__r.Title__c
        ]) {
            CourseCard card = new CourseCard();
            card.instanceId = inst.Id;
            card.materialId = inst.Material__c;
            card.title = inst.Material__r.Title__c;
            card.description = inst.Material__r.Description__c;
            card.status = inst.Status__c;
            card.progress = inst.Progress__c == null ? 0 : inst.Progress__c;
            card.issueCertificate = inst.Material__r.Issue_Certificate__c == true;
            card.canShowCertificate =
                card.issueCertificate && inst.Status__c == 'Completed';
            cards.add(card);
        }
        return cards;
    }

    @AuraEnabled
    public static CoursePlayerDto openCourse(Id courseInstanceId, Id selectedMaterialId) {
        Id userId = UserInfo.getUserId();
        Learning_Material_Instance__c courseInst = [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Learner__c,
                Material__c,
                Material__r.Title__c,
                Material__r.Description__c,
                Material__r.Issue_Certificate__c,
                Started_On__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId AND Learner__c = :userId
            LIMIT 1
        ];

        ensureChildInstances(userId, courseInst.Material__c);

        if (courseInst.Started_On__c == null) {
            courseInst.Started_On__c = System.now();
            if (courseInst.Status__c == null || courseInst.Status__c == 'Not Started') {
                courseInst.Status__c = 'In Progress';
            }
            update courseInst;
        }

        List<Learning_Material__c> children = [
            SELECT
                Id,
                Title__c,
                Material_Type__c,
                Material_URL__c,
                Duration__c,
                CreatedDate
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseInst.Material__c AND Active__c = true
            ORDER BY CreatedDate ASC, Title__c ASC
        ];

        Map<Id, Learning_Material_Instance__c> byMaterial = loadInstancesByMaterial(
            userId,
            collectIds(children, courseInst.Material__c)
        );

        CoursePlayerDto dto = new CoursePlayerDto();
        dto.courseInstanceId = courseInst.Id;
        dto.courseMaterialId = courseInst.Material__c;
        dto.title = courseInst.Material__r.Title__c;
        dto.description = courseInst.Material__r.Description__c;
        dto.status = courseInst.Status__c;
        dto.progress = courseInst.Progress__c == null ? 0 : courseInst.Progress__c;
        dto.issueCertificate = courseInst.Material__r.Issue_Certificate__c == true;
        dto.canShowCertificate = dto.issueCertificate && courseInst.Status__c == 'Completed';
        dto.curriculum = new List<CurriculumItem>();

        Integer order = 0;
        for (Learning_Material__c child : children) {
            Learning_Material_Instance__c childInst = byMaterial.get(child.Id);
            CurriculumItem item = new CurriculumItem();
            item.materialId = child.Id;
            item.instanceId = childInst != null ? childInst.Id : null;
            item.title = child.Title__c;
            item.materialType = child.Material_Type__c;
            item.status = childInst != null ? childInst.Status__c : 'Not Started';
            item.progress = childInst != null && childInst.Progress__c != null
                ? childInst.Progress__c
                : 0;
            item.score = childInst != null ? childInst.Score__c : null;
            item.materialUrl = child.Material_URL__c;
            item.duration = child.Duration__c;
            item.completed = item.status == 'Completed';
            item.sortOrder = order++;
            dto.curriculum.add(item);
            if (
                selectedMaterialId != null &&
                child.Id == selectedMaterialId &&
                item.instanceId != null
            ) {
                dto.selectedInstanceId = item.instanceId;
            }
        }

        if (dto.selectedInstanceId == null && !dto.curriculum.isEmpty()) {
            for (CurriculumItem item : dto.curriculum) {
                if (!item.completed && item.instanceId != null) {
                    dto.selectedInstanceId = item.instanceId;
                    break;
                }
            }
            if (dto.selectedInstanceId == null) {
                dto.selectedInstanceId = dto.curriculum[0].instanceId;
            }
        }

        dto.progress = rollupCourseProgress(courseInst.Id);
        courseInst = [
            SELECT Status__c, Progress__c, Material__r.Issue_Certificate__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInst.Id
        ];
        dto.status = courseInst.Status__c;
        dto.progress = courseInst.Progress__c == null ? 0 : courseInst.Progress__c;
        dto.canShowCertificate =
            courseInst.Material__r.Issue_Certificate__c == true &&
            courseInst.Status__c == 'Completed';
        return dto;
    }

    @AuraEnabled
    public static CurriculumItem startLesson(Id instanceId) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        if (inst.Status__c == null || inst.Status__c == 'Not Started') {
            inst.Status__c = 'In Progress';
        }
        update inst;
        rollupCourseProgress(findCourseInstanceId(inst));
        return toCurriculumItem(inst);
    }

    @AuraEnabled
    public static CoursePlayerDto markLessonComplete(Id instanceId) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Material__r.Material_Type__c == 'Quiz') {
            throw new AuraHandledException('Complete quizzes by submitting the exam.');
        }
        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        inst.Status__c = 'Completed';
        inst.Progress__c = 100;
        inst.Completed_On__c = System.now();
        update inst;

        Id courseInstanceId = findCourseInstanceId(inst);
        rollupCourseProgress(courseInstanceId);
        return openCourse(courseInstanceId, inst.Material__c);
    }

    @AuraEnabled
    public static QuizTakeDto getQuizForTake(Id instanceId) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Material__r.Material_Type__c != 'Quiz') {
            throw new AuraHandledException('Material is not a quiz.');
        }

        QuizTakeDto dto = new QuizTakeDto();
        dto.instanceId = inst.Id;
        dto.materialId = inst.Material__c;
        dto.title = inst.Material__r.Title__c;
        dto.passingScore = inst.Material__r.Passing_Score__c;
        dto.timeLimitMinutes = inst.Material__r.Quiz_Time_Limit_Minutes__c;
        dto.maxAttempts = inst.Material__r.Max_Attempts__c;
        dto.attemptNumber = inst.Attempt_Number__c == null ? 0 : inst.Attempt_Number__c;
        dto.showResults = inst.Material__r.Show_Results__c == true;
        dto.status = inst.Status__c;
        dto.lastScore = inst.Score__c;
        dto.canAttempt =
            inst.Status__c != 'Completed' &&
            (dto.maxAttempts == null || dto.attemptNumber < dto.maxAttempts);
        dto.questions = new List<QuizQuestionDto>();

        Map<String, Object> quiz = parseQuizJson(inst.Material__r.Quiz_Questions__c);
        List<Object> questions = (List<Object>) quiz.get('questions');
        if (questions == null) {
            return dto;
        }
        for (Object qObj : questions) {
            Map<String, Object> q = (Map<String, Object>) qObj;
            QuizQuestionDto qd = new QuizQuestionDto();
            qd.id = (String) q.get('id');
            qd.question = (String) q.get('question');
            qd.type = (String) q.get('type');
            qd.points = toDecimal(q.get('points'), 1);
            Object opts = q.get('options');
            qd.options = new List<String>();
            if (opts instanceof List<Object>) {
                for (Object o : (List<Object>) opts) {
                    qd.options.add(String.valueOf(o));
                }
            }
            if (qd.type == 'scale') {
                qd.scaleMin = toInteger(q.get('scaleMin'), 1);
                qd.scaleMax = toInteger(q.get('scaleMax'), 5);
                qd.scaleMinLabel = (String) q.get('scaleMinLabel');
                qd.scaleMaxLabel = (String) q.get('scaleMaxLabel');
            }
            dto.questions.add(qd);
        }

        return dto;
    }

    @AuraEnabled
    public static QuizSubmitResult submitQuiz(Id instanceId, String answersJson, Decimal timeTakenMinutes) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Material__r.Material_Type__c != 'Quiz') {
            throw new AuraHandledException('Material is not a quiz.');
        }

        Decimal attemptNumber = inst.Attempt_Number__c == null ? 0 : inst.Attempt_Number__c;
        Decimal maxAttempts = inst.Material__r.Max_Attempts__c;
        if (inst.Status__c == 'Completed') {
            throw new AuraHandledException('This quiz is already completed.');
        }
        if (maxAttempts != null && attemptNumber >= maxAttempts) {
            throw new AuraHandledException('Maximum attempts reached.');
        }

        Map<String, Object> answers = String.isBlank(answersJson)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(answersJson);
        Map<String, Object> quiz = parseQuizJson(inst.Material__r.Quiz_Questions__c);
        List<Object> questions = (List<Object>) quiz.get('questions');

        Decimal earned = 0;
        Decimal total = 0;
        Map<String, Object> questionResults = new Map<String, Object>();

        if (questions != null) {
            for (Object qObj : questions) {
                Map<String, Object> q = (Map<String, Object>) qObj;
                String qid = (String) q.get('id');
                Decimal points = toDecimal(q.get('points'), 1);
                total += points;
                Object given = answers.get(qid);
                Boolean correct = isAnswerCorrect(q, given);
                if (correct) {
                    earned += points;
                }
                questionResults.put(
                    qid,
                    new Map<String, Object>{
                        'correct' => correct,
                        'correctAnswer' => q.get('correctAnswer') != null
                            ? q.get('correctAnswer')
                            : q.get('correctAnswers'),
                        'explanation' => q.get('explanation'),
                        'points' => points,
                        'earned' => correct ? points : 0
                    }
                );
            }
        }

        Decimal scorePct = total > 0 ? ((earned / total) * 100).setScale(1) : 0;
        Decimal passing = inst.Material__r.Passing_Score__c == null
            ? 70
            : inst.Material__r.Passing_Score__c;
        Boolean passed = scorePct >= passing;

        inst.Attempt_Number__c = attemptNumber + 1;
        inst.Score__c = scorePct;
        inst.Time_Taken_Minutes__c = timeTakenMinutes;
        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        if (passed) {
            inst.Status__c = 'Completed';
            inst.Progress__c = 100;
            inst.Completed_On__c = System.now();
        } else {
            inst.Status__c = 'In Progress';
            inst.Progress__c = scorePct;
        }
        update inst;

        Id courseInstanceId = findCourseInstanceId(inst);
        Decimal courseProgress = rollupCourseProgress(courseInstanceId);
        Learning_Material_Instance__c courseInst = [
            SELECT Status__c, Material__r.Issue_Certificate__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId
        ];

        QuizSubmitResult result = new QuizSubmitResult();
        result.score = scorePct;
        result.earnedPoints = earned;
        result.totalPoints = total;
        result.passed = passed;
        result.showResults = inst.Material__r.Show_Results__c == true;
        result.status = inst.Status__c;
        result.courseProgress = courseProgress;
        result.courseCompleted = courseInst.Status__c == 'Completed';
        result.canShowCertificate =
            courseInst.Material__r.Issue_Certificate__c == true &&
            courseInst.Status__c == 'Completed';
        result.questionResults = result.showResults ? questionResults : null;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static CertificateDto getCertificate(Id courseInstanceId) {
        Id userId = UserInfo.getUserId();
        Learning_Material_Instance__c courseInst = [
            SELECT
                Id,
                Status__c,
                Score__c,
                Completed_On__c,
                Material__r.Title__c,
                Material__r.Issue_Certificate__c,
                Material__r.Certificate_Logo_URL__c,
                Material__r.Certificate_Template__c,
                Learner__r.Name
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId AND Learner__c = :userId
            LIMIT 1
        ];
        if (
            courseInst.Status__c != 'Completed' ||
            courseInst.Material__r.Issue_Certificate__c != true
        ) {
            throw new AuraHandledException('Certificate is not available yet.');
        }

        CertificateDto dto = new CertificateDto();
        dto.learnerName = courseInst.Learner__r.Name;
        dto.courseTitle = courseInst.Material__r.Title__c;
        dto.completedOn = courseInst.Completed_On__c == null
            ? ''
            : courseInst.Completed_On__c.format();
        dto.score = courseInst.Score__c;
        dto.logoUrl = courseInst.Material__r.Certificate_Logo_URL__c;
        dto.templateHtml = courseInst.Material__r.Certificate_Template__c;
        dto.renderedHtml = renderCertificate(dto);
        return dto;
    }

    @TestVisible
    static String renderCertificate(CertificateDto dto) {
        String html = dto.templateHtml;
        if (String.isBlank(html)) {
            String logo = String.isBlank(dto.logoUrl)
                ? ''
                : '<img src="' +
                  escapeHtml(dto.logoUrl) +
                  '" alt="Logo" style="max-height:72px;margin-bottom:16px;" />';
            html =
                '<div style="border:8px solid #0b3d5c;padding:40px;text-align:center;font-family:Georgia,serif;color:#0b3d5c;">' +
                logo +
                '<div style="font-size:14px;letter-spacing:3px;text-transform:uppercase;">Certificate of Completion</div>' +
                '<div style="font-size:28px;margin:18px 0 8px;font-weight:700;">{{LearnerName}}</div>' +
                '<div style="font-size:16px;margin-bottom:12px;">has successfully completed</div>' +
                '<div style="font-size:22px;font-weight:600;margin-bottom:18px;">{{CourseTitle}}</div>' +
                '<div style="font-size:14px;">Completed on {{CompletedOn}}</div>' +
                '</div>';
        }
        html = html.replace('{{LearnerName}}', escapeHtml(nullToEmpty(dto.learnerName)));
        html = html.replace('{{CourseTitle}}', escapeHtml(nullToEmpty(dto.courseTitle)));
        html = html.replace('{{CompletedOn}}', escapeHtml(nullToEmpty(dto.completedOn)));
        html = html.replace(
            '{{Score}}',
            dto.score == null ? '' : String.valueOf(dto.score)
        );
        html = html.replace('{{LogoUrl}}', escapeHtml(nullToEmpty(dto.logoUrl)));
        return html;
    }

    static void ensureChildInstances(Id userId, Id courseMaterialId) {
        List<Learning_Material__c> children = [
            SELECT Id
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseMaterialId AND Active__c = true
        ];
        if (children.isEmpty()) {
            return;
        }
        Set<Id> childIds = new Set<Id>();
        for (Learning_Material__c c : children) {
            childIds.add(c.Id);
        }
        Set<Id> existing = new Set<Id>();
        for (Learning_Material_Instance__c inst : [
            SELECT Material__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :userId AND Material__c IN :childIds
        ]) {
            existing.add(inst.Material__c);
        }
        List<Learning_Material_Instance__c> toInsert = new List<Learning_Material_Instance__c>();
        for (Id childId : childIds) {
            if (!existing.contains(childId)) {
                toInsert.add(
                    new Learning_Material_Instance__c(
                        Learner__c = userId,
                        Material__c = childId,
                        Status__c = 'Not Started',
                        Progress__c = 0,
                        Attempt_Number__c = 0
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    static Decimal rollupCourseProgress(Id courseInstanceId) {
        if (courseInstanceId == null) {
            return 0;
        }
        Learning_Material_Instance__c courseInst = [
            SELECT Id, Material__c, Learner__c, Status__c, Progress__c, Started_On__c, Completed_On__c, Score__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId
            LIMIT 1
        ];
        List<Learning_Material__c> children = [
            SELECT Id
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseInst.Material__c AND Active__c = true
        ];
        if (children.isEmpty()) {
            return courseInst.Progress__c == null ? 0 : courseInst.Progress__c;
        }
        Set<Id> childIds = new Set<Id>();
        for (Learning_Material__c c : children) {
            childIds.add(c.Id);
        }
        Integer completed = 0;
        Decimal quizScoreSum = 0;
        Integer quizScoreCount = 0;
        for (Learning_Material_Instance__c childInst : [
            SELECT Status__c, Score__c, Material__r.Material_Type__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :courseInst.Learner__c AND Material__c IN :childIds
        ]) {
            if (childInst.Status__c == 'Completed') {
                completed++;
            }
            if (
                childInst.Material__r.Material_Type__c == 'Quiz' &&
                childInst.Score__c != null
            ) {
                quizScoreSum += childInst.Score__c;
                quizScoreCount++;
            }
        }
        Decimal progress = ((Decimal) completed / (Decimal) children.size() * 100)
            .setScale(0);
        courseInst.Progress__c = progress;
        if (progress >= 100) {
            courseInst.Status__c = 'Completed';
            if (courseInst.Completed_On__c == null) {
                courseInst.Completed_On__c = System.now();
            }
        } else if (courseInst.Status__c == 'Not Started' || courseInst.Status__c == null) {
            courseInst.Status__c = 'In Progress';
        } else if (courseInst.Status__c == 'Completed' && progress < 100) {
            courseInst.Status__c = 'In Progress';
            courseInst.Completed_On__c = null;
        }
        if (quizScoreCount > 0) {
            courseInst.Score__c = (quizScoreSum / quizScoreCount).setScale(1);
        }
        if (courseInst.Started_On__c == null) {
            courseInst.Started_On__c = System.now();
        }
        update courseInst;
        return progress;
    }

    static Learning_Material_Instance__c requireOwnInstance(Id instanceId) {
        Id userId = UserInfo.getUserId();
        List<Learning_Material_Instance__c> rows = [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Score__c,
                Started_On__c,
                Completed_On__c,
                Attempt_Number__c,
                Time_Taken_Minutes__c,
                Learner__c,
                Material__c,
                Material__r.Title__c,
                Material__r.Material_Type__c,
                Material__r.Material_URL__c,
                Material__r.Duration__c,
                Material__r.Parent_Material__c,
                Material__r.Passing_Score__c,
                Material__r.Quiz_Time_Limit_Minutes__c,
                Material__r.Max_Attempts__c,
                Material__r.Show_Results__c,
                Material__r.Randomize_Questions__c,
                Material__r.Quiz_Questions__c,
                Material__r.Issue_Certificate__c
            FROM Learning_Material_Instance__c
            WHERE Id = :instanceId AND Learner__c = :userId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Learning assignment not found.');
        }
        return rows[0];
    }

    static Id findCourseInstanceId(Learning_Material_Instance__c inst) {
        Id courseMaterialId = inst.Material__r.Material_Type__c == 'Course'
            ? inst.Material__c
            : inst.Material__r.Parent_Material__c;
        if (courseMaterialId == null) {
            return inst.Id;
        }
        List<Learning_Material_Instance__c> courseRows = [
            SELECT Id
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :inst.Learner__c AND Material__c = :courseMaterialId
            LIMIT 1
        ];
        return courseRows.isEmpty() ? inst.Id : courseRows[0].Id;
    }

    static Map<Id, Learning_Material_Instance__c> loadInstancesByMaterial(
        Id userId,
        Set<Id> materialIds
    ) {
        Map<Id, Learning_Material_Instance__c> byMaterial = new Map<Id, Learning_Material_Instance__c>();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Material__c,
                Status__c,
                Progress__c,
                Score__c,
                Material__r.Title__c,
                Material__r.Material_Type__c,
                Material__r.Material_URL__c,
                Material__r.Duration__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :userId AND Material__c IN :materialIds
        ]) {
            byMaterial.put(inst.Material__c, inst);
        }
        return byMaterial;
    }

    static Set<Id> collectIds(List<Learning_Material__c> children, Id courseId) {
        Set<Id> ids = new Set<Id>{ courseId };
        for (Learning_Material__c c : children) {
            ids.add(c.Id);
        }
        return ids;
    }

    static CurriculumItem toCurriculumItem(Learning_Material_Instance__c inst) {
        CurriculumItem item = new CurriculumItem();
        item.materialId = inst.Material__c;
        item.instanceId = inst.Id;
        item.title = inst.Material__r.Title__c;
        item.materialType = inst.Material__r.Material_Type__c;
        item.status = inst.Status__c;
        item.progress = inst.Progress__c;
        item.score = inst.Score__c;
        item.materialUrl = inst.Material__r.Material_URL__c;
        item.duration = inst.Material__r.Duration__c;
        item.completed = inst.Status__c == 'Completed';
        return item;
    }

    static Map<String, Object> parseQuizJson(String raw) {
        if (String.isBlank(raw)) {
            return new Map<String, Object>{ 'questions' => new List<Object>() };
        }
        Object parsed = JSON.deserializeUntyped(raw);
        if (parsed instanceof Map<String, Object>) {
            return (Map<String, Object>) parsed;
        }
        throw new AuraHandledException('Invalid quiz JSON.');
    }

    static Boolean isAnswerCorrect(Map<String, Object> question, Object given) {
        String type = (String) question.get('type');
        if (type == 'multiple-choice') {
            Set<Integer> expected = new Set<Integer>();
            Object ca = question.get('correctAnswers');
            if (ca instanceof List<Object>) {
                for (Object o : (List<Object>) ca) {
                    expected.add(toInteger(o, -1));
                }
            }
            Set<Integer> actual = new Set<Integer>();
            if (given instanceof List<Object>) {
                for (Object o : (List<Object>) given) {
                    actual.add(toInteger(o, -2));
                }
            } else if (given != null) {
                actual.add(toInteger(given, -2));
            }
            return expected.equals(actual);
        }
        if (type == 'scale') {
            // Scale questions are reflective Â always credit full points when answered.
            return given != null;
        }
        Integer expected = toInteger(question.get('correctAnswer'), -1);
        Integer actual = toInteger(given, -2);
        return expected == actual;
    }

    static Decimal toDecimal(Object value, Decimal fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    static Integer toInteger(Object value, Integer fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    static String nullToEmpty(String value) {
        return value == null ? '' : value;
    }

    static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }
}