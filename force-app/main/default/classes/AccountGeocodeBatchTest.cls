@IsTest
private class AccountGeocodeBatchTest {
    private class NominatimMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('[{"lat":"30.0444","lon":"31.2357","display_name":"Cairo, Egypt"}]');
            return res;
        }
    }

    @IsTest
    static void batchGeocodesAccountsMissingCoords() {
        Account a = new Account(
            Name = 'Geocode Target Pharmacy',
            BillingStreet = 'Tahrir Street',
            BillingCity = 'Cairo',
            BillingCountry = 'Egypt'
        );
        insert a;

        Test.setMock(HttpCalloutMock.class, new NominatimMock());
        Test.startTest();
        Id jobId = AccountGeocodeBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Account updated = [
            SELECT BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id = :a.Id
        ];
        System.assertEquals(30.0444, updated.BillingLatitude);
        System.assertEquals(31.2357, updated.BillingLongitude);
    }
}