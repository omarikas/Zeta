@IsTest
private class LearningAdminControllerTest {
    @IsTest
    static void createAssignAndListMaterials() {
        Id courseId = LearningAdminController.createMaterial(
            'Test Course',
            'Course',
            null,
            true
        );
        Id videoId = LearningAdminController.createMaterial(
            'Test Video',
            'Video',
            courseId,
            true
        );
        Id quizId = LearningAdminController.createMaterial(
            'Test Quiz',
            'Quiz',
            courseId,
            true
        );
        System.assertNotEquals(null, courseId);
        System.assertNotEquals(null, videoId);
        System.assertNotEquals(null, quizId);

        LearningAdminController.AssignResult assignResult = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            courseId
        );
        System.assertNotEquals(null, assignResult.courseInstanceId);
        System.assert(assignResult.instanceCount >= 3);

        List<LearningAdminController.MaterialSummary> rows = LearningAdminController.getMaterialSummaries(
            'Test',
            'All',
            'Active'
        );
        System.assert(rows.size() >= 3);

        List<LearningAdminController.MaterialSummary> quizzes = LearningAdminController.getMaterialSummaries(
            null,
            'Quiz',
            'All'
        );
        Boolean foundQuiz = false;
        for (LearningAdminController.MaterialSummary row : quizzes) {
            if (row.id == quizId) {
                foundQuiz = true;
            }
        }
        System.assert(foundQuiz);

        List<LearningAdminController.AssignmentRow> assignees = LearningAdminController.getAssignments(
            courseId
        );
        System.assertEquals(1, assignees.size());
        System.assertEquals(UserInfo.getUserId(), assignees[0].userId);

        LearningAdminController.updateMaterial(
            courseId,
            'Test Course Updated',
            'Updated description',
            true,
            45,
            'Course',
            null
        );
        Learning_Material__c updated = [
            SELECT Title__c, Description__c, Duration__c
            FROM Learning_Material__c
            WHERE Id = :courseId
        ];
        System.assertEquals('Test Course Updated', updated.Title__c);
        System.assertEquals(45, updated.Duration__c);
    }
}