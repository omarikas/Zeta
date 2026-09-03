// Fetch the org's "Pharma Field" app tabs from the standard REST UI API.
// Tab list is cached in localStorage (stale-while-revalidate) so the sidebar
// works offline and only re-syncs when a network call succeeds.

const APP_TABS_CACHE_KEY = 'zeta.pwa.appTabs';
const DEFAULT_API_VERSION = 'v62.0';

// Fallback used only when there is no cache AND the network request fails.
// Keys map to the PWA view mount functions in main.js.
const FALLBACK_TABS = [
    { key: 'Field_Rep_Home_App', label: 'Home', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Field_Rep_Planner', label: 'Field Rep Planner', type: 'TabAura', iconUrl: null },
    { key: 'Accounts_Tab', label: 'Accounts', type: 'TabFlexiPage', iconUrl: null },
    { key: 'CLM_Presentations', label: 'CLM Presentations', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Visit__c', label: 'Visits', type: 'Entity', iconUrl: null }
];

function sfInstance() {
    return (
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
        (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
        'https://zetapharma.my.salesforce.com'
    );
}

function apiToken() {
    return (
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
        (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
        ''
    );
}

function writeCache(data) {
    try {
        localStorage.setItem(APP_TABS_CACHE_KEY, JSON.stringify({
            savedAt: Date.now(),
            payload: data
        }));
    } catch (_err) { /* storage full */ }
}

function readCache() {
    try {
        const raw = localStorage.getItem(APP_TABS_CACHE_KEY);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (_err) { /* corrupt or unavailable */ }
    return null;
}

// Normalize a UI API app's navItems into the shape the shell expects.
function normalizeTabs(app) {
    const navItems = (app && Array.isArray(app.navItems)) ? app.navItems : [];
    return navItems
        .filter((item) => item && item.label && item.developerName)
        .map((item) => ({
            key: item.developerName,
            label: item.label,
            type: item.itemType || item.type || 'TabFlexiPage',
            iconUrl: item.iconUrl || null,
            objectApiName: item.objectApiName || null
        }));
}

// Fetch tab definitions for the current user's "Pharma Field" app.
// Returns the cached list immediately when available, then refreshes in the
// background. On failure it falls back to cache, then to local defaults.
export async function fetchAppTabs({ forceRefresh = false } = {}) {
    const cached = readCache();
    const fromCache = cached && Array.isArray(cached.payload) && cached.payload.length ? cached.payload : null;

    if (fromCache && !forceRefresh) {
        // Background refresh so the sidebar stays current without blocking boot.
        refreshAppTabs().catch(() => {});
        return fromCache;
    }

    try {
        const tabs = await fetchAppTabsFromOrg();
        if (tabs.length) {
            writeCache(tabs);
            return tabs;
        }
    } catch (_err) {
        // Fall through to cache / defaults.
    }

    if (fromCache) return fromCache;
    return FALLBACK_TABS;
}

async function refreshAppTabs() {
    const tabs = await fetchAppTabsFromOrg();
    if (tabs.length) {
        writeCache(tabs);
        return tabs;
    }
    return null;
}

async function fetchAppTabsFromOrg() {
    const token = apiToken();
    if (!token) {
        throw new Error('Not signed in.');
    }
    const base = `${String(sfInstance()).replace(/\/$/, '')}/services/data/${DEFAULT_API_VERSION}/ui-api/apps?formFactor=Small`;
    const resp = await fetch(base, {
        method: 'GET',
        headers: { Accept: 'application/json', Authorization: `Bearer ${token}` }
    });
    if (resp.status === 401) {
        throw new Error('Session expired.');
    }
    if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}`);
    }
    const data = await resp.json();
    const apps = Array.isArray(data.apps) ? data.apps : [];
    const selected = apps.find((app) => app && app.selected === true)
        || apps.find((app) => app && app.developerName === 'LightningSales')
        || apps[0];
    return normalizeTabs(selected || {});
}