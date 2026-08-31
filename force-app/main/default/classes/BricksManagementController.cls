public with sharing class BricksManagementController {
    public class BrickUpsertInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
    }

    @AuraEnabled
    public static List<Object> listBricks() {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> listPharmacies(Id brickId) {
        return getBrickPharmacies(brickId);
    }
    @AuraEnabled
    public static List<Object> getBricksByTerritory(Id territory2Id) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> getBrickPharmacies(Id brickId) {
        return new List<Object>();
    }
    @AuraEnabled
    public static List<Object> searchPharmacyOptions(String searchTerm) {
        return new List<Object>();
    }
    @AuraEnabled
    public static Id upsertBrick(Object input) {
        return null;
    }
    @AuraEnabled
    public static void assignBrickToTerritory(Id brickId, Id territory2Id) {
    }
    @AuraEnabled
    public static void deleteBrick(Id brickId) {
    }
    @AuraEnabled
    public static Id addPharmacyToBrick(Id brickId, Id pharmacyId) {
        return null;
    }
    @AuraEnabled
    public static void removePharmacyFromBrick(Id membershipId) {
    }
    @AuraEnabled
    public static Object seedBrickDemoData() {
        return null;
    }
}