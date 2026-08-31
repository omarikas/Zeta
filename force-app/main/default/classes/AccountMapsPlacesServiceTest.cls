@IsTest
private class AccountMapsPlacesServiceTest {
  private class PlacesMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      String body = req.getBody() == null ? '' : req.getBody();
      if (endpoint.contains('findplacefromtext')) {
        res.setBody(
          '{"status":"OK","candidates":[{"place_id":"ChIJtest","formatted_phone_number":"+20 2 1234567","name":"Test Clinic"}]}'
        );
      } else if (endpoint.contains('place/details')) {
        res.setBody(
          '{"status":"OK","result":{"formatted_phone_number":"+20 2 1234567","international_phone_number":"+20 2 1234567","photos":[{"photo_reference":"abc123"}]}}'
        );
      } else if (endpoint.contains('overpass') || body.contains('out:json')) {
        res.setBody('{"elements":[{"type":"node","tags":{"phone":"+201111111111"}}]}');
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }

  private class PlacesNoPhoneMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('findplacefromtext')) {
        res.setBody('{"status":"ZERO_RESULTS","candidates":[]}');
      } else if (endpoint.contains('overpass') || (req.getBody() != null && req.getBody().contains('out:json'))) {
        res.setBody('{"elements":[]}');
      } else {
        res.setBody('{"status":"OK","result":{}}');
      }
      return res;
    }
  }

  @IsTest
  static void enrichesPhoneFromGooglePlaces() {
    Account clinic = new Account(
      Name = 'Maps Clinic Test',
      BillingStreet = 'Tahrir',
      BillingCity = 'Cairo',
      BillingCountry = 'Egypt',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357
    );
    insert clinic;

    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;

    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccount(
      clinic.Id
    );
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();

    System.assertEquals('Found', result.status);
    System.assert(String.isNotBlank(result.phone));
    System.assertEquals(clinic.Id, media.accountId);
    System.assertNotEquals(null, media.staticMapUrl);
    System.assertEquals(true, media.hasGoogleKey);
    System.assert(String.isNotBlank(media.streetViewUrl));
    // Place photos require a second Places Details callout; assert place id was stored.
    System.assertEquals('ChIJtest', result.placeId);
    Account refreshed = [
      SELECT Maps_Place_Id__c, Maps_Phone_Number__c
      FROM Account
      WHERE Id = :clinic.Id
    ];
    System.assertEquals('ChIJtest', refreshed.Maps_Place_Id__c);
    System.assertNotEquals(null, refreshed.Maps_Phone_Number__c);
  }

  @IsTest
  static void batchEnrichesAccounts() {
    Account clinic = new Account(
      Name = 'Batch Maps Clinic',
      BillingStreet = 'Nile',
      BillingCity = 'Giza',
      BillingCountry = 'Egypt',
      BillingLatitude = 30.01,
      BillingLongitude = 31.21
    );
    insert clinic;

    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;

    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    Id jobId = AccountMapsPhoneBatch.run();
    Test.stopTest();

    System.assertNotEquals(null, jobId);
    Account refreshed = [
      SELECT Maps_Phone_Number__c, Maps_Enrichment_Status__c, Maps_Place_Id__c
      FROM Account
      WHERE Id = :clinic.Id
    ];
    System.assertEquals('Found', refreshed.Maps_Enrichment_Status__c);
    System.assertNotEquals(null, refreshed.Maps_Phone_Number__c);
    System.assertEquals('ChIJtest', refreshed.Maps_Place_Id__c);
  }

  @IsTest
  static void osmFallbackWithoutGoogleKey() {
    Account clinic = new Account(
      Name = 'OSM Clinic',
      BillingLatitude = 30.01,
      BillingLongitude = 31.22
    );
    insert clinic;
    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccountRecord(
      clinic
    );
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();
    System.assertEquals('Found', result.status);
    System.assertEquals('OpenStreetMap', result.provider);
    System.assertNotEquals(null, media.staticMapUrl);
  }

  @IsTest
  static void loadsPlacePhotosWhenPlaceIdPresent() {
    Account clinic = new Account(
      Name = 'Photo Clinic',
      BillingLatitude = 30.04,
      BillingLongitude = 31.23,
      Maps_Place_Id__c = 'ChIJtest'
    );
    insert clinic;
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();
    System.assert(!media.photoUrls.isEmpty());
  }

  @IsTest
  static void mediaWithoutCoordinatesShowsMessage() {
    Account clinic = new Account(Name = 'No Geo Clinic');
    insert clinic;
    Test.startTest();
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();
    System.assertEquals(clinic.Id, media.accountId);
    System.assertEquals(null, media.staticMapUrl);
    System.assert(String.isNotBlank(media.message));
  }

  @IsTest
  static void notFoundWhenNoMatches() {
    Account clinic = new Account(
      Name = 'No Match Clinic',
      BillingStreet = 'Unknown',
      BillingCity = 'Nowhere',
      BillingLatitude = 29.9,
      BillingLongitude = 31.1
    );
    insert clinic;
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PlacesNoPhoneMock());
    Test.startTest();
    AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccountRecord(
      clinic
    );
    Test.stopTest();
    System.assertEquals('Not Found', result.status);
  }
}