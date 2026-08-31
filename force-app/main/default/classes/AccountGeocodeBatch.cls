/**
 * Backfills Account BillingLatitude / BillingLongitude from street + city
 * using DistributorGeocodeService (Google when configured, else Nominatim).
 * Caches results by city (and street+city) across execute scopes to minimize callouts.
 */
public without sharing class AccountGeocodeBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private Map<String, List<Decimal>> geoCache = new Map<String, List<Decimal>>();
    private Set<String> failedKeys = new Set<String>();
    private Integer updatedCount = 0;
    private Integer failedCount = 0;
    private Integer skippedCount = 0;

    public static Id run() {
        Integer scopeSize = DistributorGeocodeService.hasGoogleApiKey() ? 20 : 5;
        return Database.executeBatch(new AccountGeocodeBatch(), scopeSize);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingCountry
                FROM Account
                WHERE
                    BillingLatitude = NULL
                    AND (BillingCity != NULL OR BillingStreet != NULL)
                WITH SYSTEM_MODE
                ORDER BY BillingCity ASC NULLS LAST, BillingStreet ASC NULLS LAST
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Account> updates = new List<Account>();
        Integer calloutsUsed = 0;
        Integer calloutBudget = DistributorGeocodeService.hasGoogleApiKey() ? 20 : 5;

        for (Account acct : (List<Account>) scope) {
            String city = clean(acct.BillingCity);
            String street = clean(acct.BillingStreet);
            if (city == null && street == null) {
                skippedCount++;
                continue;
            }

            String cityKey = city != null ? ('city|' + city.toLowerCase()) : null;
            String streetKey =
                (street != null && city != null && street.toLowerCase() != city.toLowerCase())
                    ? ('st|' + street.toLowerCase() + '|' + city.toLowerCase())
                    : null;

            List<Decimal> coords = cachedCoords(streetKey, cityKey);
            if (coords == null && isHardFailed(streetKey, cityKey)) {
                failedCount++;
                continue;
            }

            if (coords == null && calloutsUsed < calloutBudget) {
                if (streetKey != null && !failedKeys.contains(streetKey) && calloutsUsed < calloutBudget) {
                    calloutsUsed++;
                    coords = callGeocode(acct.Name, street, city, streetKey, cityKey);
                }
                if (coords == null && cityKey != null && !failedKeys.contains(cityKey) && calloutsUsed < calloutBudget) {
                    calloutsUsed++;
                    coords = callGeocode(null, null, city, null, cityKey);
                }
            }

            if (coords == null) {
                // Budget exhausted or provider miss � leave for a later run.
                skippedCount++;
                continue;
            }

            updates.add(
                new Account(
                    Id = acct.Id,
                    BillingLatitude = coords[0],
                    BillingLongitude = coords[1],
                    BillingCountry = String.isBlank(acct.BillingCountry) ? 'Egypt' : acct.BillingCountry
                )
            );
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    updatedCount++;
                } else {
                    failedCount++;
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'AccountGeocodeBatch done. updated=' +
                updatedCount +
                ' failed=' +
                failedCount +
                ' skipped=' +
                skippedCount +
                ' cachedKeys=' +
                geoCache.size()
        );
    }

    private List<Decimal> cachedCoords(String streetKey, String cityKey) {
        if (streetKey != null && geoCache.containsKey(streetKey)) {
            return geoCache.get(streetKey);
        }
        if (cityKey != null && geoCache.containsKey(cityKey)) {
            return geoCache.get(cityKey);
        }
        return null;
    }

    private Boolean isHardFailed(String streetKey, String cityKey) {
        Boolean streetFailed = streetKey == null || failedKeys.contains(streetKey);
        Boolean cityFailed = cityKey == null || failedKeys.contains(cityKey);
        return streetFailed && cityFailed;
    }

    private List<Decimal> callGeocode(
        String name,
        String street,
        String city,
        String streetKey,
        String cityKey
    ) {
        DistributorGeocodeService.GeoResult geo = DistributorGeocodeService.geocode(name, street, city);
        if (geo != null && geo.status == 'Geocoded' && geo.latitude != null && geo.longitude != null) {
            List<Decimal> coords = new List<Decimal>{ geo.latitude, geo.longitude };
            if (streetKey != null) {
                geoCache.put(streetKey, coords);
            }
            if (cityKey != null && !geoCache.containsKey(cityKey)) {
                geoCache.put(cityKey, coords);
            }
            return coords;
        }
        if (streetKey != null) {
            failedKeys.add(streetKey);
        } else if (cityKey != null) {
            failedKeys.add(cityKey);
        }
        return null;
    }

    private static String clean(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String s = raw.trim();
        if (s == '0' || s == '-' || s == 'null' || s == 'NULL' || s == 'N/A') {
            return null;
        }
        return s;
    }
}