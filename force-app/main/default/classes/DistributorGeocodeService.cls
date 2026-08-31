/**
 * Geocoding for distributor sellout aliases.
 * Prefers Google Geocoding (Named Credential) when API key is set;
 * falls back to OpenStreetMap Nominatim so pilot imports can still map coordinates.
 */
public with sharing class DistributorGeocodeService {
    public class GeoResult {
        public Decimal latitude;
        public Decimal longitude;
        public String status;
        public String formattedAddress;
        public String provider;
        public String message;
        public String recommendation;
    }

    public static GeoResult geocode(String name, String address, String governorate) {
        GeoResult result = new GeoResult();
        String cleanGov = cleanPlace(governorate);
        String cleanAddr = cleanPlace(address);
        String cleanName = cleanPlace(name);

        if (String.isBlank(cleanAddr) && String.isBlank(cleanGov) && String.isBlank(cleanName)) {
            result.status = 'Skipped';
            result.message = 'No pharmacy name, address, or governorate to geocode.';
            result.recommendation =
                'Add an address on this sellout alias, or link a pharmacy Account manually.';
            return result;
        }
        if (String.isBlank(cleanAddr) && String.isBlank(cleanGov)) {
            result.status = 'Skipped';
            result.message = 'Only a client name was available — street/area is required to geocode.';
            result.recommendation =
                'Add address or governorate on the alias, or link a pharmacy Account manually.';
            return result;
        }

        List<String> queryCandidates = buildQueryCandidates(cleanName, cleanAddr, cleanGov);
        String apiKey = resolveApiKey();
        Boolean usedGoogle = String.isNotBlank(apiKey);
        for (String query : queryCandidates) {
            GeoResult attempt = usedGoogle ? geocodeGoogle(query, apiKey) : geocodeNominatim(query);
            if (attempt != null && attempt.status == 'Geocoded') {
                return attempt;
            }
            if (attempt != null) {
                result = attempt;
            }
        }
        if (result.status == null || result.status == 'Failed') {
            result.status = 'Failed';
            if (String.isBlank(result.message)) {
                result.message = usedGoogle
                    ? 'Google Geocoding returned no usable coordinates for this address (tried street, locality, and governorate).'
                    : 'OpenStreetMap Nominatim returned no usable coordinates for this address (tried street, locality, and governorate).';
            }
            if (String.isBlank(result.recommendation)) {
                result.recommendation = defaultFailureRecommendation(usedGoogle);
            }
        }
        return result;
    }

    public static String defaultFailureRecommendation(Boolean usedGoogle) {
        if (usedGoogle != true) {
            return 'Add a Google Geocoding API key on the Import tab for better Egypt street matching, ' +
                'or search and link an existing pharmacy Account manually.';
        }
        return 'Improve the address (neighborhood / street), then re-run geocode from Batches, ' +
            'or search and link an existing pharmacy Account manually.';
    }

    public static String recommendationForStatus(String status, String storedMessage) {
        if (status == 'Geocoded') {
            return null;
        }
        if (status == 'Pending') {
            return 'Wait for the import batch to finish geocoding, or re-queue from Batches.';
        }
        if (status == 'Skipped') {
            return 'Add address/governorate on the alias, or link a pharmacy Account manually.';
        }
        if (status == 'Failed') {
            return defaultFailureRecommendation(hasGoogleApiKey());
        }
        return null;
    }

    private static List<String> buildQueryCandidates(String name, String address, String governorate) {
        List<String> queries = new List<String>();
        List<String> parts = new List<String>();
        if (String.isNotBlank(name)) {
            parts.add(name);
        }
        if (String.isNotBlank(address)) {
            parts.add(address);
        }
        if (String.isNotBlank(governorate)) {
            parts.add(governorate);
        }
        parts.add('Egypt');
        queries.add(String.join(parts, ', '));

        // Informal Egypt addresses often encode locality after '/' — try locality + governorate
        if (String.isNotBlank(address)) {
            List<String> localityBits = new List<String>();
            for (String chunk : address.split('[/|,|-]')) {
                String c = cleanPlace(chunk);
                if (String.isNotBlank(c) && c.length() >= 3) {
                    localityBits.add(c);
                }
            }
            if (!localityBits.isEmpty()) {
                String locality = localityBits[localityBits.size() - 1];
                List<String> locParts = new List<String>{ locality };
                if (String.isNotBlank(governorate)) {
                    locParts.add(governorate);
                }
                locParts.add('Egypt');
                String locQuery = String.join(locParts, ', ');
                if (!queries.contains(locQuery)) {
                    queries.add(locQuery);
                }
                String longest = locality;
                for (String c : localityBits) {
                    if (c.length() > longest.length()) {
                        longest = c;
                    }
                }
                if (longest != locality) {
                    List<String> longParts = new List<String>{ longest };
                    if (String.isNotBlank(governorate)) {
                        longParts.add(governorate);
                    }
                    longParts.add('Egypt');
                    String longQuery = String.join(longParts, ', ');
                    if (!queries.contains(longQuery)) {
                        queries.add(longQuery);
                    }
                }
            }
        }

        if (String.isNotBlank(governorate)) {
            String govOnly = governorate + ', Egypt';
            if (!queries.contains(govOnly)) {
                queries.add(govOnly);
            }
        }
        return queries;
    }

    private static GeoResult geocodeGoogle(String query, String apiKey) {
        GeoResult result = new GeoResult();
        result.provider = 'Google';
        String endpoint =
            'callout:Google_Geocoding/maps/api/geocode/json?address=' +
            EncodingUtil.urlEncode(query, 'UTF-8') +
            '&region=eg&language=ar&key=' +
            EncodingUtil.urlEncode(apiKey, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(12000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            result.status = 'Failed';
            result.message = 'Google Geocoding HTTP ' + res.getStatusCode() + '.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String apiStatus = (String) body.get('status');
        if (apiStatus != 'OK') {
            result.status = 'Failed';
            result.message = 'Google Geocoding status: ' + apiStatus + '.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        List<Object> results = (List<Object>) body.get('results');
        if (results == null || results.isEmpty()) {
            result.status = 'Failed';
            result.message = 'Google Geocoding returned zero results.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        Map<String, Object> first = (Map<String, Object>) results[0];
        Map<String, Object> geometry = (Map<String, Object>) first.get('geometry');
        Map<String, Object> location = (Map<String, Object>) geometry.get('location');
        result.latitude = toDec(location.get('lat'));
        result.longitude = toDec(location.get('lng'));
        result.formattedAddress = (String) first.get('formatted_address');
        result.status = 'Geocoded';
        result.message = null;
        result.recommendation = null;
        return result;
    }

    private static GeoResult geocodeNominatim(String query) {
        GeoResult result = new GeoResult();
        result.provider = 'Nominatim';
        String endpoint =
            'callout:OpenStreetMap_Nominatim/search?q=' +
            EncodingUtil.urlEncode(query, 'UTF-8') +
            '&format=json&limit=1&countrycodes=eg';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(12000);
        req.setHeader('User-Agent', 'ZetaPharma-DistributorsManagement/1.0');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 429 || res.getStatusCode() == 502 || res.getStatusCode() == 503) {
            result.status = 'Failed';
            result.message = 'Nominatim temporarily unavailable (HTTP ' + res.getStatusCode() + ').';
            result.recommendation =
                'Re-queue the batch later, or add a Google Geocoding API key on the Import tab.';
            return result;
        }
        if (res.getStatusCode() != 200) {
            result.status = 'Failed';
            result.message = 'Nominatim HTTP ' + res.getStatusCode() + '.';
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        String bodyText = res.getBody();
        if (String.isBlank(bodyText) || !bodyText.trim().startsWith('[')) {
            result.status = 'Failed';
            result.message = 'Nominatim returned an unexpected response.';
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        Object parsed = JSON.deserializeUntyped(bodyText);
        if (!(parsed instanceof List<Object>) || ((List<Object>) parsed).isEmpty()) {
            result.status = 'Failed';
            result.message = 'Nominatim found no match for query: ' + query.left(180);
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) parsed)[0];
        result.latitude = toDec(first.get('lat'));
        result.longitude = toDec(first.get('lon'));
        result.formattedAddress = (String) first.get('display_name');
        if (result.latitude == null || result.longitude == null) {
            result.status = 'Failed';
            result.message = 'Nominatim result was missing coordinates.';
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        result.status = 'Geocoded';
        result.message = null;
        result.recommendation = null;
        return result;
    }

    public static Boolean hasGoogleApiKey() {
        return String.isNotBlank(resolveApiKey());
    }

    private static String resolveApiKey() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        if (cfg != null && String.isNotBlank(cfg.Google_API_Key__c)) {
            return cfg.Google_API_Key__c;
        }
        return null;
    }

    private static String cleanPlace(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String s = raw.trim();
        if (s == '0' || s == '-' || s == 'null' || s == 'NULL' || s == 'N/A') {
            return null;
        }
        return s;
    }

    private static Decimal toDec(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        try {
            return Decimal.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return null;
        }
    }
}