import { loadScript, loadStyle } from 'lightning/platformResourceLoader';

export const HCP_RECORD_TYPES = new Set([
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
]);

export const HCO_RECORD_TYPES = new Set(['Institution_HCO', 'Pharmacy']);

export const PIN_COLORS = {
    hcp: '#0176d3',
    hco: '#6a1b9a'
};

export function getPinColor(pinKind) {
    return pinKind === 'hco' ? PIN_COLORS.hco : PIN_COLORS.hcp;
}

export const HCP_PIN_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 12c2.2 0 4-1.8 4-4s-1.8-4-4-4-4 1.8-4 4 1.8 4 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z"/></svg>';

export const HCO_PIN_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 7V3H2v18h20V7H12zm-2 12H6v-2h4v2zm0-4H6v-2h4v2zm0-4H6V9h4v2zm0-4H6V5h4v2zm6 12h-4v-2h4v2zm0-4h-4v-2h4v2zm0-4h-4V9h4v2zm0-4h-4V5h4v2zm8 12h-6v-2h2v-2h-2v-2h2v-2h-2V9h6v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>';

export const OSM_TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
export const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';

const pinIconCache = new Map();

export function resolveAccountPinKind(recordTypeDeveloperName, recordTypeName) {
    const developerName = recordTypeDeveloperName || '';
    if (HCP_RECORD_TYPES.has(developerName)) {
        return 'hcp';
    }
    if (HCO_RECORD_TYPES.has(developerName)) {
        return 'hco';
    }
    const label = (recordTypeName || '').toLowerCase();
    if (label.includes('hcp') || label.includes('professional') || label.includes('person')) {
        return 'hcp';
    }
    if (
        label.includes('hco') ||
        label.includes('institution') ||
        label.includes('pharmacy') ||
        label.includes('clinic')
    ) {
        return 'hco';
    }
    return 'hcp';
}

export function resolveAccountTypeLabel(pinKind, recordTypeName) {
    if (recordTypeName) {
        return recordTypeName;
    }
    return pinKind === 'hco' ? 'Healthcare organization' : 'Healthcare professional';
}

export function createVisitPinIcon(pinKind, leaflet, isOutlier = false) {
    const cacheKey = `${pinKind}${isOutlier ? '-outlier' : ''}`;
    if (pinIconCache.has(cacheKey)) {
        return pinIconCache.get(cacheKey);
    }

    let icon;
    if (pinKind === 'unplanned') {
        icon = leaflet.divIcon({
            className: 'map-pin-icon-shell',
            html: '<div class="map-pin-marker map-pin-marker-unplanned" title="No visit planned"></div>',
            iconSize: [14, 14],
            iconAnchor: [7, 7],
            popupAnchor: [0, -8]
        });
    } else {
        const svg = pinKind === 'hco' ? HCO_PIN_SVG : HCP_PIN_SVG;
        const outlierClass = isOutlier ? ' map-pin-marker-outlier' : '';
        const title = isOutlier
            ? 'Route outlier — far from other stops'
            : pinKind === 'hco'
              ? 'HCO'
              : 'HCP';
        icon = leaflet.divIcon({
            className: 'map-pin-icon-shell',
            html: `<div class="map-pin-marker map-pin-marker-${pinKind}${outlierClass}" title="${title}">${svg}</div>`,
            iconSize: [30, 30],
            iconAnchor: [15, 15],
            popupAnchor: [0, -16]
        });
    }

    pinIconCache.set(cacheKey, icon);
    return icon;
}

export async function ensureLeaflet(component, leafletResourceUrl) {
    if (window.L) {
        return window.L;
    }
    await loadStyle(component, `${leafletResourceUrl}/leaflet.css`);
    await loadScript(component, `${leafletResourceUrl}/leaflet.js`);
    delete window.L.Icon.Default.prototype._getIconUrl;
    window.L.Icon.Default.mergeOptions({
        iconRetinaUrl: `${leafletResourceUrl}/marker-icon-2x.png`,
        iconUrl: `${leafletResourceUrl}/marker-icon.png`,
        shadowUrl: `${leafletResourceUrl}/marker-shadow.png`
    });
    return window.L;
}

export function addOsmTileLayer(mapInstance, leaflet) {
    return leaflet.tileLayer(OSM_TILE_URL, {
        maxZoom: 19,
        attribution: OSM_ATTRIBUTION
    }).addTo(mapInstance);
}