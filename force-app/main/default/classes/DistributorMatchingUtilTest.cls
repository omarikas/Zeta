@IsTest
private class DistributorMatchingUtilTest {
    @IsTest
    static void normalizeAndSimilarity() {
        System.assertEquals('IBNSINA', DistributorMatchingUtil.normalizeDistributorCode('ibn sina'));
        System.assertEquals('Elezaby', DistributorMatchingUtil.normalizeDistributorCode('ezzabi'));
        System.assertEquals('Egydrug', DistributorMatchingUtil.normalizeDistributorCode('Egydurg'));
        System.assertEquals('IbnSina', DistributorMatchingUtil.toDataSource('IBNSINA'));
        System.assertEquals(
            'IBNSINA|123',
            DistributorMatchingUtil.buildProductUniqueKey('IBNSINA', '123')
        );
        System.assertEquals(
            100,
            DistributorMatchingUtil.nameSimilarity('EMPACOZA PLUS 30 TAB', 'EMPACOZA PLUS 30 TAB')
        );
        Decimal sim = DistributorMatchingUtil.nameSimilarity(
            'EMPACOZA PLUS 25/5 MG 30 TAB',
            'EMPACOZA PLUS 25/5 MG 30 TABLET'
        );
        System.assert(sim > 50, 'Expected fuzzy match, got ' + sim);
        Decimal meters = DistributorMatchingUtil.haversineMeters(30.0, 31.0, 30.001, 31.001);
        System.assert(meters != null && meters > 0);
        System.assertEquals(85, DistributorMatchingUtil.autoConfirmThreshold());
        System.assertEquals(250, DistributorMatchingUtil.proximityMeters());
    }

    @IsTest
    static void extraCoverageHelpers() {
        System.assertEquals('', DistributorMatchingUtil.normalizeName(null));
        System.assertEquals('', DistributorMatchingUtil.normalizeCode(null));
        System.assertEquals('', DistributorMatchingUtil.normalizeDistributorCode(null));
        System.assertEquals(0, DistributorMatchingUtil.nameSimilarity('', 'x'));
        System.assertEquals(null, DistributorMatchingUtil.haversineMeters(null, 1, 2, 3));
        System.assert(
            DistributorMatchingUtil.nameSimilarity('ALPHA BETA', 'ALPHA BETA GAMMA') > 50
        );
        System.assertEquals('Sofico', DistributorMatchingUtil.normalizeDistributorCode('sofico'));
        System.assertEquals('POS', DistributorMatchingUtil.normalizeDistributorCode('pos'));
        System.assertEquals('EPDA', DistributorMatchingUtil.normalizeDistributorCode('ebda'));
        System.assertEquals('EPDA', DistributorMatchingUtil.normalizeDistributorCode('EPDA'));
        System.assertEquals('EPDA', DistributorMatchingUtil.normalizeDistributorCode('Ebda'));
        System.assertEquals(
            'Pharmaoverseas',
            DistributorMatchingUtil.normalizeDistributorCode('pharmaoverseas')
        );
        System.assertEquals('EPDA Cust', DistributorMatchingUtil.normalizeDistributorCode('EBDA_CUST'));
        System.assertEquals('EPDA Cust', DistributorMatchingUtil.normalizeDistributorCode('epda cust'));
        System.assertEquals('Ebda', DistributorMatchingUtil.toDataSource('EPDA'));
        System.assertEquals(
            new List<String>{ 'EPDA', 'Ebda', 'EBDA' },
            DistributorMatchingUtil.distributorCodeVariants('ebda')
        );
        System.assertEquals('DRUG', DistributorMatchingUtil.normalizeName('DR DRUG'));
        System.assertEquals(
            'IBNSINA|C1',
            DistributorMatchingUtil.buildSelloutUniqueKey('IBNSINA', 'C1')
        );
    }
}