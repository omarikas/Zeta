@IsTest
public without sharing class VisitValidationControllerTestHelper {
    public static void seedPendingUnplannedReview(Id visitId) {
        Visit__c visit = [
            SELECT Id, Visit_Type__c, Status__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH SYSTEM_MODE
        ];
        visit.Status__c = 'Completed';
        VisitStatusHelper.applyUnplannedCompletionValidation(visit);
        update as system visit;
    }

    public static String readValidationStatus(Id visitId) {
        return [
            SELECT Validation_Status__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH SYSTEM_MODE
        ]
        .Validation_Status__c;
    }
}
