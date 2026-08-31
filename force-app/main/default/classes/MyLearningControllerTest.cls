@IsTest
private class MyLearningControllerTest {
    @IsTest
    static void courseProgressQuizAndCertificate() {
        Id courseId = LearningAdminController.createMaterial(
            'Cert Course',
            'Course',
            null,
            true
        );
        update new Learning_Material__c(
            Id = courseId,
            Issue_Certificate__c = true,
            Description__c = 'Course description'
        );
        Id videoId = LearningAdminController.createMaterial(
            'Cert Video',
            'Video',
            courseId,
            true
        );
        update new Learning_Material__c(
            Id = videoId,
            Material_URL__c = 'https://www.youtube.com/watch?v=soH2Siy_ho4'
        );
        Id quizId = LearningAdminController.createMaterial(
            'Cert Quiz',
            'Quiz',
            courseId,
            true
        );
        update new Learning_Material__c(
            Id = quizId,
            Passing_Score__c = 50,
            Quiz_Questions__c = JSON.serialize(
                new Map<String, Object>{
                    'version' => '1.1',
                    'totalQuestions' => 1,
                    'totalPoints' => 1,
                    'questions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'q1',
                            'question' => '2+2?',
                            'type' => 'single-choice',
                            'options' => new List<String>{ '3', '4', '5' },
                            'correctAnswer' => 1,
                            'points' => 1,
                            'explanation' => 'Four'
                        }
                    }
                }
            )
        );

        LearningAdminController.AssignResult assignResult = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            courseId
        );

        List<MyLearningController.CourseCard> courses = MyLearningController.getMyCourses();
        System.assertEquals(1, courses.size());

        MyLearningController.CoursePlayerDto player = MyLearningController.openCourse(
            assignResult.courseInstanceId,
            null
        );
        System.assertEquals(2, player.curriculum.size());
        System.assertNotEquals(null, player.selectedInstanceId);

        Id videoInstanceId;
        Id quizInstanceId;
        for (MyLearningController.CurriculumItem item : player.curriculum) {
            if (item.materialType == 'Video') {
                videoInstanceId = item.instanceId;
            }
            if (item.materialType == 'Quiz') {
                quizInstanceId = item.instanceId;
            }
        }
        System.assertNotEquals(null, videoInstanceId);
        System.assertNotEquals(null, quizInstanceId);

        MyLearningController.startLesson(videoInstanceId);
        player = MyLearningController.markLessonComplete(videoInstanceId);
        System.assert(player.progress >= 50);

        MyLearningController.QuizTakeDto quiz = MyLearningController.getQuizForTake(quizInstanceId);
        System.assertEquals(1, quiz.questions.size());
        System.assertEquals(true, quiz.canAttempt);

        MyLearningController.QuizSubmitResult submit = MyLearningController.submitQuiz(
            quizInstanceId,
            JSON.serialize(new Map<String, Object>{ 'q1' => 1 }),
            5
        );
        System.assertEquals(true, submit.passed);
        System.assertEquals(true, submit.courseCompleted);
        System.assertEquals(true, submit.canShowCertificate);

        MyLearningController.CertificateDto cert = MyLearningController.getCertificate(
            assignResult.courseInstanceId
        );
        System.assert(cert.renderedHtml.contains('Cert Course'));
        System.assert(cert.renderedHtml.contains(UserInfo.getName()));
    }
}