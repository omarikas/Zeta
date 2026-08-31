/**
 * Official Google Places + OSM Overpass enrichment for account maps phone / photos.
 * Does not scrape Google Maps HTML.
 */
public with sharing class AccountMapsPlacesService {
  public class EnrichmentResult {
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String placeId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String provider;
  }

  public class LocationMedia {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String mapsPhone;
    @AuraEnabled
    public String placeId;
    @AuraEnabled
    public String enrichmentStatus;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String addressLine;
    @AuraEnabled
    public String streetViewUrl;
    @AuraEnabled
    public String staticMapUrl;
    @AuraEnabled
    public List<String> photoUrls;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Boolean hasGoogleKey;
  }

  public static Id runPhoneEnrichmentBatch() {
    Integer scopeSize = DistributorGeocodeService.hasGoogleApiKey() ? 10 : 5;
    return Database.executeBatch(new AccountMapsPhoneBatch(), scopeSize);
  }

  @AuraEnabled(cacheable=true)
  public static LocationMedia getLocationMedia(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }
    Account acct = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        Maps_Phone_Number__c,
        Maps_Place_Id__c,
        Maps_Enrichment_Status__c
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    LocationMedia media = new LocationMedia();
    media.accountId = acct.Id;
    media.accountName = acct.Name;
    media.mapsPhone = acct.Maps_Phone_Number__c;
    media.placeId = acct.Maps_Place_Id__c;
    media.enrichmentStatus = acct.Maps_Enrichment_Status__c;
    media.latitude = acct.BillingLatitude;
    media.longitude = acct.BillingLongitude;
    media.addressLine = buildAddress(acct.BillingStreet, acct.BillingCity, acct.BillingCountry);
    media.photoUrls = new List<String>();
    media.hasGoogleKey = DistributorGeocodeService.hasGoogleApiKey();
    media.staticMapUrl = buildStaticMapUrl(acct.BillingLatitude, acct.BillingLongitude);

    String apiKey = resolveApiKey();
    if (acct.BillingLatitude != null && acct.BillingLongitude != null && String.isNotBlank(apiKey)) {
      media.streetViewUrl =
        'https://maps.googleapis.com/maps/api/streetview?size=640x360&location=' +
        String.valueOf(acct.BillingLatitude) +
        ',' +
        String.valueOf(acct.BillingLongitude) +
        '&fov=80&pitch=0&key=' +
        EncodingUtil.urlEncode(apiKey, 'UTF-8');
    }

    if (String.isNotBlank(acct.Maps_Place_Id__c) && String.isNotBlank(apiKey)) {
      media.photoUrls.addAll(loadPlacePhotoUrls(acct.Maps_Place_Id__c, apiKey, 4));
    }

    if (
      media.streetViewUrl == null &&
      media.staticMapUrl == null &&
      (media.photoUrls == null || media.photoUrls.isEmpty())
    ) {
      media.message = media.hasGoogleKey
        ? 'No map location yet. Geocode the billing address, then enrich maps phone.'
        : 'Add a Google Places/Geocoding API key on Distributor Geocode Config to load Street View and place photos. A static OpenStreetMap preview is used when coordinates exist.';
    }
    return media;
  }

  @AuraEnabled
  public static EnrichmentResult enrichAccount(Id accountId) {
    Account acct = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        Maps_Phone_Number__c,
        Maps_Place_Id__c
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    EnrichmentResult result = enrichAccountRecord(acct);
    Account updateRow = new Account(
      Id = acct.Id,
      Maps_Enrichment_Status__c = result.status,
      Maps_Last_Enriched__c = System.now()
    );
    if (String.isNotBlank(result.phone)) {
      updateRow.Maps_Phone_Number__c = result.phone;
    }
    if (String.isNotBlank(result.placeId)) {
      updateRow.Maps_Place_Id__c = result.placeId;
    }
    Database.DmlOptions opts = new Database.DmlOptions();
    opts.duplicateRuleHeader.allowSave = true;
    opts.optAllOrNone = false;
    Database.update(new List<Account>{ updateRow }, opts);
    return result;
  }

  public static EnrichmentResult enrichAccountRecord(Account acct) {
    EnrichmentResult result = new EnrichmentResult();
    String apiKey = resolveApiKey();
    if (String.isNotBlank(apiKey)) {
      EnrichmentResult places = enrichFromGooglePlaces(acct, apiKey);
      if (places != null && String.isNotBlank(places.phone)) {
        return places;
      }
      if (places != null) {
        result = places;
      }
    } else {
      result.status = 'Needs API Key';
      result.message = 'Google Places API key is not configured on Distributor Geocode Config.';
    }

    EnrichmentResult osm = enrichFromOverpass(acct);
    if (osm != null && String.isNotBlank(osm.phone)) {
      return osm;
    }
    if (result.status == null || result.status == 'Needs API Key') {
      if (osm != null) {
        return osm;
      }
      if (String.isBlank(apiKey)) {
        result.status = 'Needs API Key';
        result.message = 'Configure Google Places API key (or wait for OSM phone tags near the location).';
        return result;
      }
    }
    if (String.isBlank(result.status)) {
      result.status = 'Not Found';
      result.message = 'No public phone found for this location.';
    }
    return result;
  }

  private static EnrichmentResult enrichFromGooglePlaces(Account acct, String apiKey) {
    EnrichmentResult result = new EnrichmentResult();
    result.provider = 'Google Places';
    String query = buildSearchQuery(acct);
    if (String.isBlank(query)) {
      result.status = 'Not Found';
      result.message = 'Account needs a name or address to search Places.';
      return result;
    }
    String findUrl =
      'callout:Google_Geocoding/maps/api/place/findplacefromtext/json?input=' +
      EncodingUtil.urlEncode(query, 'UTF-8') +
      '&inputtype=textquery&fields=place_id,name,formatted_phone_number,geometry&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    if (acct.BillingLatitude != null && acct.BillingLongitude != null) {
      findUrl +=
        '&locationbias=point:' +
        String.valueOf(acct.BillingLatitude) +
        ',' +
        String.valueOf(acct.BillingLongitude);
    }
    HttpResponse findResp = httpGet(findUrl);
    if (findResp == null || findResp.getStatusCode() >= 400) {
      result.status = 'Error';
      result.message = 'Google Places find request failed.';
      return result;
    }
    Map<String, Object> findBody = (Map<String, Object>) JSON.deserializeUntyped(findResp.getBody());
    String status = (String) findBody.get('status');
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      result.status = 'Error';
      result.message = 'Google Places status: ' + status;
      return result;
    }
    List<Object> candidates = (List<Object>) findBody.get('candidates');
    if (candidates == null || candidates.isEmpty()) {
      result.status = 'Not Found';
      result.message = 'No Places match for this account.';
      return result;
    }
    Map<String, Object> first = (Map<String, Object>) candidates[0];
    String placeId = (String) first.get('place_id');
    String phone = (String) first.get('formatted_phone_number');
    result.placeId = placeId;
    if (String.isBlank(phone) && String.isNotBlank(placeId)) {
      phone = loadPlacePhone(placeId, apiKey);
    }
    result.phone = normalizePhone(phone);
    result.status = String.isNotBlank(result.phone) ? 'Found' : 'Not Found';
    result.message = result.status == 'Found' ? null : 'Place found but no phone number published.';
    return result;
  }

  private static String loadPlacePhone(String placeId, String apiKey) {
    String detailsUrl =
      'callout:Google_Geocoding/maps/api/place/details/json?place_id=' +
      EncodingUtil.urlEncode(placeId, 'UTF-8') +
      '&fields=formatted_phone_number,international_phone_number&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    HttpResponse resp = httpGet(detailsUrl);
    if (resp == null || resp.getStatusCode() >= 400) {
      return null;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    Map<String, Object> result = (Map<String, Object>) body.get('result');
    if (result == null) {
      return null;
    }
    String international = (String) result.get('international_phone_number');
    if (String.isNotBlank(international)) {
      return international;
    }
    return (String) result.get('formatted_phone_number');
  }

  private static List<String> loadPlacePhotoUrls(String placeId, String apiKey, Integer maxPhotos) {
    List<String> urls = new List<String>();
    String detailsUrl =
      'callout:Google_Geocoding/maps/api/place/details/json?place_id=' +
      EncodingUtil.urlEncode(placeId, 'UTF-8') +
      '&fields=photos&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    HttpResponse resp = httpGet(detailsUrl);
    if (resp == null || resp.getStatusCode() >= 400) {
      return urls;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    Map<String, Object> result = (Map<String, Object>) body.get('result');
    if (result == null || result.get('photos') == null) {
      return urls;
    }
    List<Object> photos = (List<Object>) result.get('photos');
    Integer limitSize = Math.min(maxPhotos, photos.size());
    for (Integer i = 0; i < limitSize; i++) {
      Map<String, Object> photo = (Map<String, Object>) photos[i];
      String photoRef = (String) photo.get('photo_reference');
      if (String.isBlank(photoRef)) {
        continue;
      }
      urls.add(
        'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photo_reference=' +
          EncodingUtil.urlEncode(photoRef, 'UTF-8') +
          '&key=' +
          EncodingUtil.urlEncode(apiKey, 'UTF-8')
      );
    }
    return urls;
  }

  private static EnrichmentResult enrichFromOverpass(Account acct) {
    EnrichmentResult result = new EnrichmentResult();
    result.provider = 'OpenStreetMap';
    if (acct.BillingLatitude == null || acct.BillingLongitude == null) {
      result.status = 'Not Found';
      result.message = 'No coordinates for OSM phone lookup.';
      return result;
    }
    String lat = String.valueOf(acct.BillingLatitude);
    String lon = String.valueOf(acct.BillingLongitude);
    String query =
      '[out:json][timeout:25];(' +
      'node(around:80,' +
      lat +
      ',' +
      lon +
      ')[~"phone|contact:phone|contact:mobile"~"."];' +
      'way(around:80,' +
      lat +
      ',' +
      lon +
      ')[~"phone|contact:phone|contact:mobile"~"."];' +
      ');out tags center 8;';
    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://overpass-api.de/api/interpreter');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.setTimeout(20000);
    req.setBody('data=' + EncodingUtil.urlEncode(query, 'UTF-8'));
    HttpResponse resp;
    try {
      resp = new Http().send(req);
    } catch (Exception e) {
      result.status = 'Error';
      result.message = 'OSM Overpass call failed: ' + e.getMessage();
      return result;
    }
    if (resp.getStatusCode() >= 400) {
      result.status = 'Error';
      result.message = 'OSM Overpass HTTP ' + resp.getStatusCode();
      return result;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    List<Object> elements = (List<Object>) body.get('elements');
    if (elements == null || elements.isEmpty()) {
      result.status = 'Not Found';
      result.message = 'No OSM phone tags near this location.';
      return result;
    }
    for (Object elObj : elements) {
      Map<String, Object> el = (Map<String, Object>) elObj;
      Map<String, Object> tags = (Map<String, Object>) el.get('tags');
      if (tags == null) {
        continue;
      }
      for (String key : new List<String>{ 'phone', 'contact:phone', 'contact:mobile' }) {
        String phone = normalizePhone((String) tags.get(key));
        if (String.isNotBlank(phone)) {
          result.phone = phone;
          result.status = 'Found';
          return result;
        }
      }
    }
    result.status = 'Not Found';
    result.message = 'OSM features nearby had no usable phone.';
    return result;
  }

  private static String buildSearchQuery(Account acct) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(acct.Name)) {
      parts.add(acct.Name.trim());
    }
    if (String.isNotBlank(acct.BillingStreet)) {
      parts.add(acct.BillingStreet.trim());
    }
    if (String.isNotBlank(acct.BillingCity)) {
      parts.add(acct.BillingCity.trim());
    }
    if (String.isNotBlank(acct.BillingCountry)) {
      parts.add(acct.BillingCountry.trim());
    } else {
      parts.add('Egypt');
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static String buildAddress(String street, String city, String country) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(street)) {
      parts.add(street);
    }
    if (String.isNotBlank(city)) {
      parts.add(city);
    }
    if (String.isNotBlank(country)) {
      parts.add(country);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static String buildStaticMapUrl(Decimal lat, Decimal lon) {
    if (lat == null || lon == null) {
      return null;
    }
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=' +
      String.valueOf(lat) +
      ',' +
      String.valueOf(lon) +
      '&zoom=17&size=640x360&markers=' +
      String.valueOf(lat) +
      ',' +
      String.valueOf(lon) +
      ',lightblue1';
  }

  private static HttpResponse httpGet(String endpoint) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('GET');
    req.setTimeout(20000);
    try {
      return new Http().send(req);
    } catch (Exception e) {
      return null;
    }
  }

  private static String resolveApiKey() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    if (cfg != null && String.isNotBlank(cfg.Google_API_Key__c)) {
      return cfg.Google_API_Key__c;
    }
    return null;
  }

  private static String normalizePhone(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    return raw.trim().left(40);
  }
}