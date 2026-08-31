/** Shared route clustering helpers for Field Rep Planner and Today's Plan. */

export const OUTLIER_MIN_DISTANCE_KM = 30;
export const OUTLIER_CLUSTER_MEDIAN_KM = 15;
export const OUTLIER_RATIO = 2.5;
export const OUTLIER_NEIGHBOR_RADIUS_KM = 25;

export function haversineKm(lat1, lng1, lat2, lng2) {
    const toRad = (v) => (v * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function normalizeSalesforceId(id) {
    if (!id) {
        return id;
    }
    return String(id).substring(0, 15);
}

function formatDistanceKm(km) {
    if (km >= 100) {
        return String(Math.round(km));
    }
    return km.toFixed(1);
}

function median(values) {
    if (!values.length) {
        return 0;
    }
    const sorted = [...values].sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 0) {
        return (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return sorted[mid];
}

function normalizeGeoStop(stop) {
    const latitude = Number(stop?.latitude);
    const longitude = Number(stop?.longitude);
    if (!stop?.id || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        return null;
    }
    return {
        visitId: stop.id,
        clusterId: normalizeSalesforceId(stop.id),
        accountName: stop.accountName || stop.name || 'Visit',
        latitude,
        longitude
    };
}

function buildOutlierReason(distanceKm, medianDistKm) {
    const distLabel = formatDistanceKm(distanceKm);
    const medianLabel = formatDistanceKm(medianDistKm);
    return `~${distLabel} km from other stops (cluster median ~${medianLabel} km from center)`;
}

function buildOutlierAwayLabel(distanceLabel) {
    return `~${distanceLabel} km away`;
}

/** One-line summary for the Distant stops panel header. */
export function formatDistantStopsSummary(outliers) {
    if (!outliers?.length) {
        return '';
    }
    const count = outliers.length;
    const medianLabel = formatDistanceKm(outliers[0].medianDistKm);
    const stopWord = count === 1 ? 'stop is' : 'stops are';
    return `${count} ${stopWord} far from your main cluster (median ~${medianLabel} km)`;
}

function findMainCluster(geoStops) {
    let seed = geoStops[0];
    let seedNeighborCount = -1;

    for (const stop of geoStops) {
        const neighborCount = geoStops.filter(
            (other) =>
                other.clusterId !== stop.clusterId &&
                haversineKm(stop.latitude, stop.longitude, other.latitude, other.longitude) <=
                    OUTLIER_NEIGHBOR_RADIUS_KM
        ).length;
        if (neighborCount > seedNeighborCount) {
            seedNeighborCount = neighborCount;
            seed = stop;
        }
    }

    const mainCluster = geoStops.filter(
        (stop) =>
            haversineKm(stop.latitude, stop.longitude, seed.latitude, seed.longitude) <=
            OUTLIER_NEIGHBOR_RADIUS_KM
    );
    const mainClusterIds = new Set(mainCluster.map((stop) => stop.clusterId));
    const centroidLat =
        mainCluster.reduce((sum, stop) => sum + stop.latitude, 0) / mainCluster.length;
    const centroidLng =
        mainCluster.reduce((sum, stop) => sum + stop.longitude, 0) / mainCluster.length;
    const medianInClusterKm = median(
        mainCluster.map((stop) =>
            haversineKm(stop.latitude, stop.longitude, centroidLat, centroidLng)
        )
    );

    return { mainClusterIds, centroidLat, centroidLng, medianInClusterKm };
}

function isDistanceOutlier(distanceKm, medianDistKm, inMainCluster) {
    if (distanceKm < OUTLIER_MIN_DISTANCE_KM) {
        return false;
    }
    if (!inMainCluster) {
        return true;
    }
    if (medianDistKm <= OUTLIER_CLUSTER_MEDIAN_KM) {
        return distanceKm > Math.max(OUTLIER_MIN_DISTANCE_KM, medianDistKm * OUTLIER_RATIO);
    }
    return distanceKm > Math.max(OUTLIER_MIN_DISTANCE_KM, medianDistKm * OUTLIER_RATIO);
}

/**
 * Flag geocoded stops that sit far from the main geographic cluster.
 * Uses the densest local cluster (not the global centroid) so multi-city routes
 * like Cairo + Alexandria still surface distant stops. Coordinates are coerced
 * to numbers because Apex decimals may arrive as strings in LWC.
 */
export function detectRouteOutliers(stops) {
    const geoStops = (stops || []).map(normalizeGeoStop).filter(Boolean);
    if (geoStops.length < 3) {
        return [];
    }

    const { mainClusterIds, centroidLat, centroidLng, medianInClusterKm } =
        findMainCluster(geoStops);

    return geoStops
        .map((stop) => {
            const distanceKm = haversineKm(
                stop.latitude,
                stop.longitude,
                centroidLat,
                centroidLng
            );
            return {
                visitId: stop.visitId,
                accountName: stop.accountName,
                distanceKm,
                distanceLabel: formatDistanceKm(distanceKm),
                inMainCluster: mainClusterIds.has(stop.clusterId)
            };
        })
        .filter((item) =>
            isDistanceOutlier(item.distanceKm, medianInClusterKm, item.inMainCluster)
        )
        .map((item) => ({
            visitId: item.visitId,
            accountName: item.accountName,
            distanceKm: item.distanceKm,
            distanceLabel: item.distanceLabel,
            medianDistKm: medianInClusterKm,
            reason: buildOutlierReason(item.distanceKm, medianInClusterKm),
            awayLabel: buildOutlierAwayLabel(item.distanceLabel)
        }));
}