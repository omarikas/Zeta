@IsTest
private class VisitOpenMapPharmacyServiceTest {
  @IsTest
  static void searchNearby_returnsExternalPharmaciesAndSkipsDuplicates() {
    Test.startTest();
    List<VisitContextInsightsController.PharmacyRow> rows = VisitOpenMapPharmacyService.searchNearby(
      30.0444,
      31.2357,
      25,
      '[]'
    );
    Test.stopTest();

    System.assertEquals(1, rows.size(), 'Expected one external pharmacy from mock');
    System.assertEquals(false, rows[0].inAccountList);
    System.assertEquals('openmap', rows[0].source);
    System.assertEquals('Open Maps Pharmacy', rows[0].name);
    System.assertEquals('12 Nile Corniche', rows[0].street);
    System.assertEquals('Cairo', rows[0].city);
    System.assertEquals('Cairo Governorate', rows[0].state);
    System.assertEquals('11511', rows[0].postalCode);
    System.assertEquals('Egypt', rows[0].country);
    System.assert(rows[0].mapsUrl.contains('openstreetmap.org'));
  }

  @IsTest
  static void searchNearby_skipsPharmacyMatchingAccountAnchor() {
    String anchorsJson =
      '[{"latitude":30.0455,"longitude":31.2365,"name":"Open Maps Pharmacy"}]';

    Test.startTest();
    List<VisitContextInsightsController.PharmacyRow> rows = VisitOpenMapPharmacyService.searchNearby(
      30.0444,
      31.2357,
      25,
      anchorsJson
    );
    Test.stopTest();

    System.assertEquals(0, rows.size(), 'Duplicate OSM result should be skipped');
  }

  @IsTest
  static void searchNearby_returnsEmptyWhenServiceUnavailable() {
    VisitOpenMapPharmacyService.forceLiveHttpInTest = true;
    VisitOpenMapPharmacyService.overpassEndpoints = new List<String>{
      'https://example.invalid/overpass'
    };

    Test.startTest();
    List<VisitContextInsightsController.PharmacyRow> rows = VisitOpenMapPharmacyService.searchNearby(
      30.0444,
      31.2357,
      25,
      '[]'
    );
    Test.stopTest();

    System.assertEquals(0, rows.size(), 'Expected graceful empty result when service is unavailable');
    VisitOpenMapPharmacyService.overpassEndpoints = null;
    VisitOpenMapPharmacyService.forceLiveHttpInTest = false;
  }
}