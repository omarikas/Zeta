public with sharing class VisitOpenMapPharmacyService {
  private static final Integer MAX_RESULTS = 25;
  private static final Decimal DUPLICATE_RADIUS_KM = 0.2;
  private static final Integer MAX_ATTEMPTS_PER_ENDPOINT = 2;

  @TestVisible
  private static Boolean forceLiveHttpInTest = false;

  @TestVisible
  private static List<String> overpassEndpoints = new List<String>{
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter'
  };

  public class AccountPharmacyAnchor {
    public Decimal latitude;
    public Decimal longitude;
    public String name;
  }

  public static List<VisitContextInsightsController.PharmacyRow> searchNearby(
    Decimal centerLat,
    Decimal centerLng,
    Decimal radiusKm,
    String accountPharmacyAnchorsJson
  ) {
    if (centerLat == null || centerLng == null) {
      return new List<VisitContextInsightsController.PharmacyRow>();
    }

    Decimal effectiveRadius = radiusKm == null ? 25 : radiusKm;
    Integer radiusMeters = Integer.valueOf(
      Math.min(50000, Math.max(500, effectiveRadius * 1000))
    );
    List<AccountPharmacyAnchor> anchors = parseAnchors(accountPharmacyAnchorsJson);

    String query =
      '[out:json][timeout:15];' +
      'node["amenity"="pharmacy"](around:' +
      radiusMeters +
      ',' +
      centerLat +
      ',' +
      centerLng +
      ');' +
      'out ' +
      MAX_RESULTS +
      ';';

    String responseBody = executeOverpassQuery(query);
    if (String.isBlank(responseBody)) {
      return new List<VisitContextInsightsController.PharmacyRow>();
    }

    return parseOverpassResponse(
      responseBody,
      centerLat,
      centerLng,
      effectiveRadius,
      anchors
    );
  }

  @TestVisible
  private static List<AccountPharmacyAnchor> parseAnchors(String jsonPayload) {
    List<AccountPharmacyAnchor> anchors = new List<AccountPharmacyAnchor>();
    if (String.isBlank(jsonPayload)) {
      return anchors;
    }
    try {
      List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(jsonPayload);
      for (Object rawRow : rawRows) {
        Map<String, Object> row = (Map<String, Object>) rawRow;
        AccountPharmacyAnchor anchor = new AccountPharmacyAnchor();
        anchor.latitude = toDecimal(row.get('latitude'));
        anchor.longitude = toDecimal(row.get('longitude'));
        anchor.name = row.get('name') != null ? String.valueOf(row.get('name')) : null;
        if (anchor.latitude != null && anchor.longitude != null) {
          anchors.add(anchor);
        }
      }
    } catch (Exception e) {
      return anchors;
    }
    return anchors;
  }

  @TestVisible
  private static String executeOverpassQuery(String query) {
    if (Test.isRunningTest() && forceLiveHttpInTest != true) {
      return getTestResponse();
    }

    List<String> endpoints = overpassEndpoints == null || overpassEndpoints.isEmpty()
      ? new List<String>{ 'https://overpass-api.de/api/interpreter' }
      : overpassEndpoints;

    for (String endpoint : endpoints) {
      for (Integer attempt = 0; attempt < MAX_ATTEMPTS_PER_ENDPOINT; attempt++) {
        HttpResponse response = sendOverpassRequest(endpoint, query);
        if (response == null) {
          continue;
        }
        Integer statusCode = response.getStatusCode();
        if (statusCode >= 200 && statusCode < 300) {
          return response.getBody();
        }
        if (statusCode == 429 || statusCode >= 500) {
          continue;
        }
        break;
      }
    }
    return null;
  }

  @TestVisible
  private static HttpResponse sendOverpassRequest(String endpoint, String query) {
    try {
      HttpRequest request = new HttpRequest();
      request.setEndpoint(endpoint);
      request.setMethod('POST');
      request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
      request.setBody('data=' + EncodingUtil.urlEncode(query, 'UTF-8'));
      request.setTimeout(60000);
      return new Http().send(request);
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static List<VisitContextInsightsController.PharmacyRow> parseOverpassResponse(
    String responseBody,
    Decimal centerLat,
    Decimal centerLng,
    Decimal radiusKm,
    List<AccountPharmacyAnchor> anchors
  ) {
    List<VisitContextInsightsController.PharmacyRow> rows = new List<VisitContextInsightsController.PharmacyRow>();
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );
    List<Object> elements = (List<Object>) parsed.get('elements');
    if (elements == null) {
      return rows;
    }

    for (Object rawElement : elements) {
      Map<String, Object> element = (Map<String, Object>) rawElement;
      Map<String, Object> tags = (Map<String, Object>) element.get('tags');
      if (tags == null || !tags.containsKey('amenity')) {
        continue;
      }

      Decimal latitude = toDecimal(element.get('lat'));
      Decimal longitude = toDecimal(element.get('lon'));
      if (latitude == null || longitude == null) {
        Map<String, Object> center = (Map<String, Object>) element.get('center');
        if (center != null) {
          latitude = toDecimal(center.get('lat'));
          longitude = toDecimal(center.get('lon'));
        }
      }
      if (latitude == null || longitude == null) {
        continue;
      }

      String name = resolveName(tags);
      if (matchesAccountPharmacy(latitude, longitude, name, anchors)) {
        continue;
      }

      Decimal distanceKm = VisitContextInsightsController.distanceKm(
        centerLat,
        centerLng,
        latitude,
        longitude
      );
      if (distanceKm > radiusKm) {
        continue;
      }

      String elementType = String.valueOf(element.get('type'));
      String elementId = String.valueOf(element.get('id'));
      String osmPath = elementType + '/' + elementId;

      VisitContextInsightsController.PharmacyRow row = new VisitContextInsightsController.PharmacyRow();
      row.name = name;
      row.street = resolveStreet(tags);
      row.city = resolveCity(tags);
      row.state = resolveState(tags);
      row.postalCode = resolvePostalCode(tags);
      row.country = resolveCountry(tags);
      row.phone = tags.containsKey('phone')
        ? String.valueOf(tags.get('phone'))
        : null;
      row.distanceKm = distanceKm.setScale(1);
      row.latitude = latitude;
      row.longitude = longitude;
      row.inAccountList = false;
      row.source = 'openmap';
      row.externalId = osmPath;
      row.mapsUrl = 'https://www.openstreetmap.org/' + osmPath;
      rows.add(row);
    }

    rows.sort(new VisitContextInsightsController.PharmacyDistanceComparator());
    if (rows.size() > MAX_RESULTS) {
      List<VisitContextInsightsController.PharmacyRow> trimmed = new List<VisitContextInsightsController.PharmacyRow>();
      for (Integer i = 0; i < MAX_RESULTS; i++) {
        trimmed.add(rows[i]);
      }
      return trimmed;
    }
    return rows;
  }

  @TestVisible
  private static Boolean matchesAccountPharmacy(
    Decimal latitude,
    Decimal longitude,
    String name,
    List<AccountPharmacyAnchor> anchors
  ) {
    for (AccountPharmacyAnchor anchor : anchors) {
      Decimal distanceKm = VisitContextInsightsController.distanceKm(
        latitude,
        longitude,
        anchor.latitude,
        anchor.longitude
      );
      if (distanceKm <= DUPLICATE_RADIUS_KM) {
        return true;
      }
      if (
        distanceKm <= 0.5 &&
        namesLikelyMatch(name, anchor.name)
      ) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static Boolean namesLikelyMatch(String left, String right) {
    String a = normalizeName(left);
    String b = normalizeName(right);
    if (String.isBlank(a) || String.isBlank(b)) {
      return false;
    }
    return a == b || a.contains(b) || b.contains(a);
  }

  @TestVisible
  private static String normalizeName(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    return value.trim().toLowerCase().replaceAll('[^a-z0-9\\s]', '');
  }

  @TestVisible
  private static String resolveName(Map<String, Object> tags) {
    if (tags.containsKey('name')) {
      return String.valueOf(tags.get('name'));
    }
    if (tags.containsKey('brand')) {
      return String.valueOf(tags.get('brand')) + ' Pharmacy';
    }
    return 'Pharmacy';
  }

  @TestVisible
  private static String resolveStreet(Map<String, Object> tags) {
    if (tags.containsKey('addr:full')) {
      return String.valueOf(tags.get('addr:full'));
    }
    String houseNumber = tags.containsKey('addr:housenumber')
      ? String.valueOf(tags.get('addr:housenumber')).trim()
      : null;
    String street = firstTagValue(
      tags,
      new List<String>{ 'addr:street', 'addr:place', 'addr:road' }
    );
    if (String.isBlank(street)) {
      return null;
    }
    return String.isBlank(houseNumber) ? street : houseNumber + ' ' + street;
  }

  @TestVisible
  private static String resolveState(Map<String, Object> tags) {
    return firstTagValue(
      tags,
      new List<String>{ 'addr:state', 'addr:province', 'addr:region' }
    );
  }

  @TestVisible
  private static String resolvePostalCode(Map<String, Object> tags) {
    return firstTagValue(tags, new List<String>{ 'addr:postcode' });
  }

  @TestVisible
  private static String resolveCountry(Map<String, Object> tags) {
    return firstTagValue(tags, new List<String>{ 'addr:country' });
  }

  @TestVisible
  private static String firstTagValue(
    Map<String, Object> tags,
    List<String> keys
  ) {
    for (String key : keys) {
      if (tags.containsKey(key) && tags.get(key) != null) {
        String value = String.valueOf(tags.get(key)).trim();
        if (String.isNotBlank(value)) {
          return value;
        }
      }
    }
    return null;
  }

  @TestVisible
  private static String resolveCity(Map<String, Object> tags) {
    return firstTagValue(
      tags,
      new List<String>{
        'addr:city',
        'addr:suburb',
        'addr:town',
        'addr:village'
      }
    );
  }

  @TestVisible
  private static Decimal toDecimal(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Decimal) {
      return (Decimal) value;
    }
    if (value instanceof Integer) {
      return Decimal.valueOf((Integer) value);
    }
    if (value instanceof Long) {
      return Decimal.valueOf((Long) value);
    }
    if (value instanceof Double) {
      return Decimal.valueOf((Double) value);
    }
    return Decimal.valueOf(String.valueOf(value));
  }

  @TestVisible
  private static String getTestResponse() {
    return '{"elements":[{"type":"node","id":999001,"lat":30.0455,"lon":31.2365,"tags":{"name":"Open Maps Pharmacy","amenity":"pharmacy","addr:street":"12 Nile Corniche","addr:city":"Cairo","addr:state":"Cairo Governorate","addr:postcode":"11511","addr:country":"Egypt"}}]}';
  }
}