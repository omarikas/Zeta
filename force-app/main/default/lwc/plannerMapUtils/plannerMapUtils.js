const OSRM_BASE = 'https://router.project-osrm.org';

const GEO_OPTIONS = { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 };
const WATCH_OPTIONS = { enableHighAccuracy: true, timeout: 20000, maximumAge: 30000 };

let activeWatchId = null;

function mapGeolocationError(error) {
    const messages = {
        1: 'Location permission denied. Allow location access to route from your position.',
        2: 'Unable to determine your location.',
        3: 'Location request timed out.'
    };
    return new Error(messages[error.code] || 'Unable to get your current location.');
}

function mapPosition(position) {
    return {
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        accuracy: position.coords.accuracy
    };
}

export function getCurrentPosition() {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject(new Error('Geolocation is not supported in this browser.'));
            return;
        }
        navigator.geolocation.getCurrentPosition(
            (position) => resolve(mapPosition(position)),
            (error) => reject(mapGeolocationError(error)),
            GEO_OPTIONS
        );
    });
}

export function watchPosition(onUpdate, onError) {
    if (!navigator.geolocation) {
        onError?.(new Error('Geolocation is not supported in this browser.'));
        return null;
    }
    clearWatch();
    activeWatchId = navigator.geolocation.watchPosition(
        (position) => onUpdate?.(mapPosition(position)),
        (error) => onError?.(mapGeolocationError(error)),
        WATCH_OPTIONS
    );
    return activeWatchId;
}

export function clearWatch(watchId = activeWatchId) {
    if (watchId != null && navigator.geolocation) {
        navigator.geolocation.clearWatch(watchId);
        if (watchId === activeWatchId) {
            activeWatchId = null;
        }
    }
}

export function fetchOsrmRoute(coordPath, alternatives = false) {
    const altParam = alternatives ? '&alternatives=true&continue_straight=false' : '';
    const url = `${OSRM_BASE}/route/v1/driving/${coordPath}?overview=full&geometries=geojson${altParam}`;
    return fetch(url)
        .then((response) => response.json())
        .then((data) => {
            if (data.code !== 'Ok' || !data.routes?.length) {
                throw new Error('No route returned from routing service.');
            }
            if (alternatives) {
                return data.routes;
            }
            return data.routes[0];
        });
}

export function haversineKm(lat1, lng1, lat2, lng2) {
    const toRad = (v) => (v * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function parseOptimizedVisitOrder(tripResponse, visitIds) {
    const waypoints = tripResponse.waypoints || [];
    const visitIndices = waypoints
        .map((waypoint, inputIndex) => ({ inputIndex, tripIndex: waypoint.waypoint_index }))
        .filter((item) => item.inputIndex > 0)
        .sort((a, b) => a.tripIndex - b.tripIndex)
        .map((item) => item.inputIndex - 1);
    return visitIndices.map((index) => visitIds[index]).filter(Boolean);
}

export function buildSwapHints(currentOrder, suggestedOrder, stopsById) {
    const hints = [];
    const currentPositions = new Map(currentOrder.map((id, index) => [id, index]));
    suggestedOrder.forEach((visitId, newIndex) => {
        const oldIndex = currentPositions.get(visitId);
        if (oldIndex !== undefined && oldIndex !== newIndex) {
            const stop = stopsById.get(visitId);
            hints.push(
                `Move ${stop?.accountName || 'visit'} to stop ${newIndex + 1} (was stop ${oldIndex + 1})`
            );
        }
    });
    return hints;
}

export function buildCoordPath(points) {
    return points.map((point) => `${point.longitude},${point.latitude}`).join(';');
}