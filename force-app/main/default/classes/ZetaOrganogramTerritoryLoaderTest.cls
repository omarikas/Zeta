@IsTest
private class ZetaOrganogramTerritoryLoaderTest {
    private static String miniPayloadJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'headOffice' => new Map<String, Object>{
                    'externalId' => 'TERR_HEAD_OFFICE',
                    'name' => 'Head Office',
                    'developerName' => 'Head_Office',
                    'parentExternalId' => null,
                    'territoryType' => 'Head_Office'
                },
                'businessUnits' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_BU_TEST_1',
                        'name' => 'TEST-BU',
                        'developerName' => 'BU_TEST_1',
                        'parentExternalId' => 'TERR_HEAD_OFFICE',
                        'territoryType' => 'Business_Unit'
                    }
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_LINE_TEST_1',
                        'name' => 'TEST-LINE',
                        'developerName' => 'LINE_TEST_1',
                        'parentExternalId' => 'TERR_BU_TEST_1',
                        'territoryType' => 'Line'
                    }
                },
                'districts' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_DM_TEST_1',
                        'name' => 'TEST DISTRICT',
                        'developerName' => 'DM_TEST_1',
                        'parentExternalId' => 'TERR_LINE_TEST_1',
                        'territoryType' => 'District'
                    }
                },
                'positions' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_POS_TEST_1',
                        'name' => 'TEST POSITION',
                        'developerName' => 'POS_TEST_1',
                        'parentExternalId' => 'TERR_DM_TEST_1',
                        'territoryType' => 'Position'
                    }
                },
                'bricks' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'BRICK_TEST_ORG_1',
                        'name' => 'Test Brick Org 1',
                        'dataSource' => 'IQVIA IMS',
                        'isActive' => true
                    }
                }
            }
        );
    }

    @IsTest
    static void alignmentResourceNames_areConfigured() {
        List<String> names = ZetaOrganogramTerritoryLoader.alignmentResourceNames();
        System.assertEquals(6, names.size());
        System.assert(names[0].startsWith('ZetaOrganogramAlignments'));
    }

    @IsTest
    static void loadTerritoriesAndBricks_withInjectedPayload() {
        ZetaOrganogramTerritoryLoader.testTerritoriesJson = miniPayloadJson();
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = true;

        ZetaOrganogramTerritoryLoader.LoadResult terrResult =
            ZetaOrganogramTerritoryLoader.loadTerritoriesOnly();
        System.assertNotEquals(null, terrResult.headOfficeId, terrResult.message);
        System.assertEquals(1, terrResult.businessUnitsUpserted, terrResult.message);
        System.assertEquals(1, terrResult.linesUpserted, terrResult.message);
        System.assertEquals(1, terrResult.districtsUpserted, terrResult.message);
        System.assertEquals(1, terrResult.positionsUpserted, terrResult.message);

        ZetaOrganogramTerritoryLoader.LoadResult brickResult =
            ZetaOrganogramTerritoryLoader.loadBricksAndQueueAlignments();
        System.assertEquals(1, brickResult.bricksUpserted, brickResult.message);

        ZetaOrganogramAlignmentBatch.testAlignmentsJson = JSON.serialize(
            new Map<String, Object>{
                'alignments' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'BRICK_TEST_ORG_1|TERR_POS_TEST_1',
                        'brickExternalId' => 'BRICK_TEST_ORG_1',
                        'territoryExternalId' => 'TERR_POS_TEST_1',
                        'share' => 1,
                        'isActive' => true
                    },
                    new Map<String, Object>{
                        'externalId' => 'BRICK_MISSING|TERR_POS_TEST_1',
                        'brickExternalId' => 'BRICK_DOES_NOT_EXIST',
                        'territoryExternalId' => 'TERR_POS_TEST_1',
                        'share' => 0.5,
                        'isActive' => true
                    }
                }
            }
        );

        Test.startTest();
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = false;
        ZetaOrganogramTerritoryLoader.LoadResult queued =
            ZetaOrganogramTerritoryLoader.loadTerritoriesAndQueueAlignments();
        Database.executeBatch(new ZetaOrganogramAlignmentBatch('ZetaOrganogramAlignments01'), 50);
        Test.stopTest();

        System.assertNotEquals(null, queued.message);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Brick_Territory_Alignment__c
                WHERE External_ID__c = 'BRICK_TEST_ORG_1|TERR_POS_TEST_1'
            ]
        );
    }
}