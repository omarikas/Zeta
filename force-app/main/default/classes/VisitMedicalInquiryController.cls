public with sharing class VisitMedicalInquiryController {
    public class MedicalInquiryContext {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public Id defaultInquirerAccountId;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<Object> inquirerOptions;
        @AuraEnabled public List<Object> products;
        @AuraEnabled public List<Object> existingInquiries;
        @AuraEnabled public List<String> questionCategories;
    }
    public class CreateInquiryRequest {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id inquirerAccountId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String questionCategory;
        @AuraEnabled public String questionText;
    }
    public class CreateInquiryResult {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
    }

    @AuraEnabled(cacheable=true)
    public static MedicalInquiryContext getMedicalInquiryContext(Id visitId) {
        MedicalInquiryContext context = new MedicalInquiryContext();
        context.visitId = visitId;
        context.isLocked = false;
        context.inquirerOptions = new List<Object>();
        context.products = new List<Object>();
        context.existingInquiries = new List<Object>();
        context.questionCategories = new List<String>{ 'Efficacy', 'Safety', 'Dosing', 'Other' };
        if (visitId == null) {
            return context;
        }
        List<Visit__c> visits = [
            SELECT Id, Name, Status__c, Account__c, Account__r.Name, Assigned_To__r.Name
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            return context;
        }
        Visit__c visit = visits[0];
        context.visitName = visit.Name;
        context.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        context.assignedToName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
        context.defaultInquirerAccountId = visit.Account__c;
        context.isLocked = visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled';
        return context;
    }

    @AuraEnabled
    public static CreateInquiryResult createMedicalInquiry(CreateInquiryRequest request) {
        throw new AuraHandledException('Medical inquiry Case fields are not fully configured in this org yet.');
    }
}