@IsTest
private class S_AccountActivityEinsteinClientTest {
    @IsTest
    static void smokeAndEnhance() {
        System.assertEquals(null, AccountActivityEinsteinClient.generate('x'));

        AccountActivityInsightsTypes.AccountVisitInsights base = new AccountActivityInsightsTypes.AccountVisitInsights();
        base.headline = 'Base';
        base.summary = 'Summary';
        base.productsDiscussed = new List<String>{ 'P1' };
        base.painPoints = new List<String>();
        base.visitCount = 2;
        base.presentationCount = 1;

        AccountActivityEinsteinClient.testForceFailure = true;
        AccountActivityEinsteinClient.GenerationResult failed = AccountActivityEinsteinClient.tryEnhance(null, base);
        System.assertEquals(false, failed.success);

        AccountActivityEinsteinClient.testForceFailure = false;
        AccountActivityEinsteinClient.GenerationResult empty = AccountActivityEinsteinClient.tryEnhance(null, base);
        System.assertEquals(false, empty.success);

        AccountActivityEinsteinClient.testResponseJson = 'not-json';
        AccountActivityEinsteinClient.tryEnhance(null, base);

        AccountActivityEinsteinClient.testResponseJson =
            '{"headline":"Enhanced","summary":"Better","productsDiscussed":["X"],"painPoints":["Y"],"positiveSignals":["Z"],"customerFeedback":["F"],"suggestedTalkingPoints":["T"]}';
        AccountActivityEinsteinClient.GenerationResult ok = AccountActivityEinsteinClient.tryEnhance(null, base);
        System.assertEquals(true, ok.success);
        System.assertEquals('Enhanced', ok.insights.headline);

        AccountActivityEinsteinClient.testResponseJson = '```json\n{"headline":"Fenced"}\n```';
        AccountActivityEinsteinClient.GenerationResult fenced = AccountActivityEinsteinClient.tryEnhance(null, base);
        System.assertEquals(true, fenced.success);
    }
}
