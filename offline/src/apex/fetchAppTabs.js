// Fetch the org's "Pharma Field" app tabs from the standard REST UI API.
// Tab list is cached in localStorage (stale-while-revalidate) so the sidebar
// works offline and only re-syncs when a network call succeeds.

const APP_TABS_CACHE_KEY = 'zeta.pwa.appTabs';
const APPS_CACHE_KEY = 'zeta.pwa.apps';
const TABS_CACHE_KEY = 'zeta.pwa.allTabs';
const DEFAULT_API_VERSION = 'v62.0';

// The offline PWA ships full renderers only for the Pharma Field app. Its tabs
// are the local defaults and it is always surfaced in the launcher even when
// the org's default app differs. Keys map to the view mount functions in main.js.
const FALLBACK_TABS = [
    { key: 'Field_Rep_Home_App', label: 'Home', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Field_Rep_Planner', label: 'Field Rep Planner', type: 'TabAura', iconUrl: null },
    { key: 'Accounts_Tab', label: 'Accounts', type: 'TabFlexiPage', iconUrl: null },
    { key: 'CLM_Presentations', label: 'CLM Presentations', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Visit__c', label: 'Visits', type: 'Entity', iconUrl: null }
];

export const PHARMA_APP = {
    developerName: 'PharmaField',
    label: 'Pharma Field',
    iconUrl: null,
    description: 'Home, planner, accounts, CLM & time off — full offline support.',
    fullOffline: true,
    tabs: FALLBACK_TABS
};

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
    const apps = await fetchAppsFromOrg();
    const selected = apps.find((app) => app && app.selected === true)
        || apps.find((app) => app && app.developerName === 'LightningSales')
        || apps[0];
    return (selected && selected.tabs) || [];
}

// ---- App launcher -------------------------------------------------------
// The launcher lists every Lightning app the user can open. Pharma Field is
// always merged in first (full offline renderers); other org apps render the
// tabs the PWA supports (entity list views) and show a "not available" panel
// for the rest.

function writeAppsCache(data) {
    try {
        localStorage.setItem(APPS_CACHE_KEY, JSON.stringify({ savedAt: Date.now(), payload: data }));
    } catch (_err) { /* storage full */ }
}

function readAppsCache() {
    try {
        const raw = localStorage.getItem(APPS_CACHE_KEY);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        return parsed && Array.isArray(parsed.payload) && parsed.payload.length ? parsed.payload : null;
    } catch (_err) { /* corrupt or unavailable */ }
    return null;
}

// The offline PWA fully renders whichever app hosts the field-rep home page.
// Tag that app "offline ready" (keeping its real icon + navItems) and sort it
// first. Tabs come straight from the org app's nav — nothing hard-coded.
const OFFLINE_HOME_TAB = 'Field_Rep_Home_App';

function markOfflineFirst(apps) {
    const list = (apps || []).map((app) => {
        const isFieldApp = (app.tabs || []).some((t) => t.key === OFFLINE_HOME_TAB)
            || app.developerName === 'LightningSales';
        if (!isFieldApp) {
            return app;
        }
        return {
            ...app,
            fullOffline: true,
            description: app.description || PHARMA_APP.description
        };
    });
    // Offline-ready app first, then the rest.
    list.sort((a, b) => (b.fullOffline === true) - (a.fullOffline === true));
    // Guarantee the field app is present even if the org didn't return one.
    if (!list.some((a) => a.fullOffline)) {
        list.unshift(PHARMA_APP);
    }
    return list;
}

async function fetchAppsFromOrg() {
    const token = apiToken();
    if (!token) {
        throw new Error('Not signed in.');
    }
    const base = `${String(sfInstance()).replace(/\/$/, '')}/services/data/${DEFAULT_API_VERSION}/ui-api/apps?formFactor=Small`;
    // Bounded so the launcher can never hang on a stalled connection.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    let resp;
    try {
        resp = await fetch(base, {
            method: 'GET',
            headers: { Accept: 'application/json', Authorization: `Bearer ${token}` },
            signal: controller.signal
        });
    } finally {
        clearTimeout(timer);
    }
    if (resp.status === 401) {
        throw new Error('Session expired.');
    }
    if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}`);
    }
    const data = await resp.json();
    const apps = Array.isArray(data.apps) ? data.apps : [];
    return apps.map((app) => ({
        developerName: app.developerName || app.label,
        label: app.label || app.developerName,
        iconUrl: app.iconUrl || (app.icon && app.icon.iconUrl) || null,
        description: app.description || '',
        selected: app.selected === true,
        fullOffline: false,
        tabs: normalizeTabs(app)
    }));
}

// Returns the launcher app list (Pharma Field first). Stale-while-revalidate:
// serves cache immediately then refreshes; falls back to Pharma-only offline.
export async function fetchApps({ forceRefresh = false } = {}) {
    const cached = readAppsCache();
    if (cached && !forceRefresh) {
        refreshApps().catch(() => {});
        return markOfflineFirst(cached);
    }
    try {
        const apps = await fetchAppsFromOrg();
        if (apps.length) {
            writeAppsCache(apps);
            return markOfflineFirst(apps);
        }
    } catch (_err) {
        // Fall through to cache / Pharma-only.
    }
    if (cached) return markOfflineFirst(cached);
    return [PHARMA_APP];
}

async function refreshApps() {
    const apps = await fetchAppsFromOrg();
    if (apps.length) {
        writeAppsCache(apps);
    }
    return apps;
}

// ---- All Items ----------------------------------------------------------
// The ui-api/apps endpoint only returns navItems for the *selected* app, so
// other apps come back tab-less. The REST /tabs resource lists every tab the
// user can access (objects + flexipages, with icons) regardless of app — the
// launcher's "All Items" section, and the way to open an object directly.

// 15/18-char Salesforce ids (flexipage/web tabs) vs real object api names.
function isSalesforceId(v) {
    return typeof v === 'string' && v[0] === '0' && /^[0-9A-Za-z]{15}([0-9A-Za-z]{3})?$/.test(v);
}

function tabsCacheGet() {
    try {
        const raw = localStorage.getItem(TABS_CACHE_KEY);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        return parsed && Array.isArray(parsed.payload) && parsed.payload.length ? parsed.payload : null;
    } catch (_err) { /* corrupt */ }
    return null;
}

function tabsCacheSet(data) {
    try {
        localStorage.setItem(TABS_CACHE_KEY, JSON.stringify({ savedAt: Date.now(), payload: data }));
    } catch (_err) { /* full */ }
}

async function fetchTabsFromOrg() {
    const token = apiToken();
    if (!token) {
        throw new Error('Not signed in.');
    }
    const url = `${String(sfInstance()).replace(/\/$/, '')}/services/data/${DEFAULT_API_VERSION}/tabs`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    let resp;
    try {
        resp = await fetch(url, {
            method: 'GET',
            headers: { Accept: 'application/json', Authorization: `Bearer ${token}` },
            signal: controller.signal
        });
    } finally {
        clearTimeout(timer);
    }
    if (!resp.ok) {
        throw new Error(`HTTP ${resp.status}`);
    }
    const data = await resp.json();
    const rows = Array.isArray(data) ? data : [];
    return rows
        .filter((t) => t && t.name && t.label)
        .map((t) => {
            const isObject = t.sobjectName && !isSalesforceId(t.sobjectName);
            return {
                key: t.name,
                label: t.label,
                type: isObject ? 'Entity' : 'TabFlexiPage',
                iconUrl: t.iconUrl || t.miniIconUrl || null,
                objectApiName: isObject ? t.sobjectName : null
            };
        })
        .sort((a, b) => (a.label || '').localeCompare(b.label || ''));
}

// All accessible tabs (items). Stale-while-revalidate; empty on failure.
export async function fetchTabs({ forceRefresh = false } = {}) {
    const cached = tabsCacheGet();
    if (cached && !forceRefresh) {
        fetchTabsFromOrg().then(tabsCacheSet).catch(() => {});
        return cached;
    }
    try {
        const tabs = await fetchTabsFromOrg();
        if (tabs.length) {
            tabsCacheSet(tabs);
            return tabs;
        }
    } catch (_err) {
        // Fall through to cache / empty.
    }
    return cached || [];
}