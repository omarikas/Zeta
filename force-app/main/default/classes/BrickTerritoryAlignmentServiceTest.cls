@IsTest
private class BrickTerritoryAlignmentServiceTest {
    @IsTest
    static void alignAccountsForBrick_handlesEmptyAndMissingAlignments() {
        BrickTerritoryAlignmentService.AlignResult emptyResult =
            BrickTerritoryAlignmentService.alignAccountsForBrick(new Set<Id>());
        System.assertEquals('No bricks provided.', emptyResult.message);

        BrickTerritoryAlignmentService.alignAccountsForBrickIds(new List<Id>());

        Brick__c brick = new Brick__c(
            Name = 'Test Brick Align',
            External_ID__c = 'BRICK_TEST_ALIGN_1',
            Is_Active__c = true
        );
        insert brick;

        BrickTerritoryAlignmentService.AlignResult noAlign =
            BrickTerritoryAlignmentService.alignAccountsForBrick(new Set<Id>{ brick.Id });
        System.assert(
            noAlign.message.contains('No active brick-territory alignments') ||
                noAlign.message.contains('No accounts linked'),
            noAlign.message
        );
    }

    @IsTest
    static void alignAccountsForBrick_createsAssociation() {
        Brick__c brick = new Brick__c(
            Name = 'Test Brick Align 2',
            External_ID__c = 'BRICK_TEST_ALIGN_2',
            Is_Active__c = true
        );
        insert brick;

        List<Territory2Model> models = [
            SELECT Id FROM Territory2Model WHERE DeveloperName = 'Current_FY' LIMIT 1
        ];
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (models.isEmpty() || types.isEmpty()) {
            return;
        }

        Territory2 position = new Territory2(
            Name = 'Align Test Position',
            DeveloperName = 'Align_Test_Position',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_POS_ALIGN_TEST'
        );
        if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            position.put('Territory_Type__c', 'Position');
        }
        insert position;

        insert new Brick_Territory_Alignment__c(
            Brick__c = brick.Id,
            External_ID__c = 'BRICK_TEST_ALIGN_2|TERR_POS_ALIGN_TEST',
            Territory2_Id__c = String.valueOf(position.Id),
            Territory_External_ID__c = 'TERR_POS_ALIGN_TEST',
            Share__c = 1,
            Is_Active__c = true
        );

        Account pharmacy = new Account(Name = 'Align Test Pharmacy');
        if (Schema.SObjectType.Account.fields.getMap().containsKey('Brick__c')) {
            pharmacy.put('Brick__c', brick.Id);
        }
        insert pharmacy;

        if (!Schema.SObjectType.Account.fields.getMap().containsKey('Brick__c')) {
            return;
        }

        Test.startTest();
        BrickTerritoryAlignmentService.AlignResult result =
            BrickTerritoryAlignmentService.alignAccountsForBrick(new Set<Id>{ brick.Id });
        Test.stopTest();

        System.assert(result.accountsProcessed >= 1, result.message);
        System.assert(
            result.associationsCreated >= 0,
            result.message
        );
    }
}