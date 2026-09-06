import '@lwc/synthetic-shadow';
import { createElement } from 'lwc';
import FieldRepHomeMetrics from 'c/fieldRepHomeMetrics';
import FieldRepHomeMonthlyTimecard from 'c/fieldRepHomeMonthlyTimecard';
import FieldRepHomeTodayPlan from 'c/fieldRepHomeTodayPlan';
import FieldRepHomeNextBestCustomer from 'c/fieldRepHomeNextBestCustomer';
import HomeOfficeMessages from 'c/homeOfficeMessages';
import FieldRepHomeClmPrefetch from 'c/fieldRepHomeClmPrefetch';
import ReportsHub from 'c/reportsHub';
import FieldRepPlanner from 'c/fieldRepPlanner';
import AccountsTab from 'c/accountsTab';
import TimeOffSubmission from 'c/timeOffSubmission';
import ClmPresentationsHub from 'c/clmPresentationsHub';
import VisitCallShell from 'c/visitCallShell';
import { startSyncService, registerOfflineListener, setForceOfflineAndSync, getForceOffline } from 'c/clmOfflineSync';
import { fetchApps, fetchTabs, PHARMA_APP } from './apex/fetchAppTabs';
import { setupToastListener } from './toastManager';
import './slds-shim.css';
import './shell.css';

const TOKEN_KEY = 'zeta.pwa.sfAccessToken';
const REFRESH_TOKEN_KEY = 'zeta.pwa.sfRefreshToken';
const INSTANCE_URL_KEY = 'zeta.pwa.sfInstanceUrl';
const HOME_TAB_KEY = 'Field_Rep_Home_App';
const VISIT_CALL_TAB_KEY = 'Visit_Call';
const ACTIVE_VISIT_KEY = 'zeta.pwa.activeVisitId';
let currentTab = HOME_TAB_KEY;
let appTabs = [];

// Capacitor plugin references (lazy loaded)
let capacitorApp = null;
let capacitorBrowser = null;

// Detect if running in Capacitor native app
function isCapacitor() {
    if (typeof window === 'undefined') return false;

    // Manual override via URL parameter or localStorage (for testing)
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('capacitor') === 'true' || localStorage.getItem('forceCapacitor') === 'true') {
        console.log('[Capacitor] Forced via URL parameter or localStorage');
        return true;
    }

    // Check for Capacitor object
    if (window.Capacitor && window.Capacitor.isNativePlatform) {
        return window.Capacitor.isNativePlatform();
    }

    // Fallback: Check if running in Android WebView with Capacitor
    const ua = navigator.userAgent;
    console.log('[Capacitor] User Agent:', ua);
    if (/android/i.test(ua) && /Capacitor/i.test(ua)) {
        console.log('[Capacitor] Detected via User Agent');
        return true;
    }

    // Fallback: Check for Capacitor-specific flags
    if (window.CapacitorCookies || window.CapacitorHttp || window.CapacitorWebView) {
        console.log('[Capacitor] Detected via global flags');
        return true;
    }

    return false;
}

// Wait for Capacitor to be ready (for remote URL loading)
function waitForCapacitor(timeout = 5000) {
    return new Promise((resolve) => {
        if (isCapacitor()) {
            resolve(true);
            return;
        }

        const startTime = Date.now();
        const checkInterval = setInterval(() => {
            if (isCapacitor()) {
                clearInterval(checkInterval);
                resolve(true);
                return;
            }

            if (Date.now() - startTime > timeout) {
                clearInterval(checkInterval);
                resolve(false);
            }
        }, 100);
    });
}

// Detect if Capacitor plugins are available
async function initCapacitorPlugins() {
    if (!isCapacitor()) return false;

    try {
        const { App } = await import('@capacitor/app');
        const { Browser } = await import('@capacitor/browser');
        capacitorApp = App;
        capacitorBrowser = Browser;
        console.log('[Capacitor] Plugins initialized');
        return true;
    } catch (error) {
        console.warn('[Capacitor] Failed to load plugins:', error);
        return false;
    }
}

// OAuth Configuration
const APP_SCHEME = 'com.zetapharma.fieldpwa';
const WEB_CALLBACK_URL = 'https://omarikas.github.io/Zeta';

const OAUTH_CONFIG = {
    clientId: '3MVG9U65ySgtae71Qj6sHa91riS85fiD5Ndf7MVHpJQwOPlo1bAScoaXG28Yvfwx05xwl.R8NaGGLPFUDSj_y',
    loginUrl: 'https://zetapharma.my.salesforce.com',
    scopes: 'api refresh_token',
    // Dynamic callback URL based on platform
    get callbackUrl() {
        if (isCapacitor()) return `${APP_SCHEME}://oauth/callback`;
        // Local Vite dev: redirect back to localhost so sign-in completes here
        // instead of bouncing to the GitHub Pages production URL.
        if (typeof window !== 'undefined' &&
            (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')) {
            return window.location.origin;
        }
        return WEB_CALLBACK_URL;
    }
};

function readToken() {
    return (
        import.meta.env.VITE_SF_ACCESS_TOKEN ||
        window.localStorage.getItem(TOKEN_KEY) ||
        ''
    ).trim();
}

function readRefreshToken() {
    return window.localStorage.getItem(REFRESH_TOKEN_KEY) || '';
}

function readInstanceUrl() {
    return window.localStorage.getItem(INSTANCE_URL_KEY) || 'https://zetapharma.my.salesforce.com';
}

function configureRuntime(token, refreshToken = null, instanceUrl = null) {
    const sfInstance = instanceUrl || readInstanceUrl();
    // In Capacitor, always call Salesforce directly (WebView loads from localhost but API calls go to SF)
    // In local browser dev, use Vite proxy (window.location.origin → /services proxied to SF)
    // In production (GitHub Pages), call Salesforce directly with the instance URL
    const isCapacitorApp = isCapacitor();
    const isLocalDev = !isCapacitorApp && (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1');
    globalThis.PLANNER_REST_BASE = isLocalDev ? window.location.origin : sfInstance;
    globalThis.PLANNER_ACCESS_TOKEN = token;
    globalThis.PLANNER_SF_INSTANCE = sfInstance;

    console.log('[configureRuntime] isCapacitorApp:', isCapacitorApp);
    console.log('[configureRuntime] isLocalDev:', isLocalDev);
    console.log('[configureRuntime] sfInstance:', sfInstance);
    console.log('[configureRuntime] PLANNER_REST_BASE:', globalThis.PLANNER_REST_BASE);

    if (refreshToken) {
        window.localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
    }
    if (instanceUrl) {
        window.localStorage.setItem(INSTANCE_URL_KEY, instanceUrl);
    }
}

// OAuth Functions with PKCE
function generateCodeVerifier() {
    const array = new Uint8Array(32);
    crypto.getRandomValues(array);
    return base64UrlEncode(array);
}

function base64UrlEncode(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function generateCodeChallenge(verifier) {
    const encoder = new TextEncoder();
    const data = encoder.encode(verifier);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return base64UrlEncode(digest);
}

async function generateAuthUrl() {
    const codeVerifier = generateCodeVerifier();
    const codeChallenge = await generateCodeChallenge(codeVerifier);
    window.localStorage.setItem('oauth_code_verifier', codeVerifier);

    const params = new URLSearchParams({
        response_type: 'code',
        client_id: OAUTH_CONFIG.clientId,
        redirect_uri: OAUTH_CONFIG.callbackUrl,
        scope: OAUTH_CONFIG.scopes,
        state: generateState(),
        code_challenge: codeChallenge,
        code_challenge_method: 'S256'
    });
    return `${OAUTH_CONFIG.loginUrl}/services/oauth2/authorize?${params.toString()}`;
}

function generateState() {
    const state = Math.random().toString(36).substring(2, 15);
    window.localStorage.setItem('oauth_state', state);
    return state;
}

// Vercel function URL for token proxy (avoids CORS)
const TOKEN_PROXY_URL = 'https://zeta-pwa.vercel.app/api/sf-token';

async function exchangeCodeForToken(code) {
    const codeVerifier = window.localStorage.getItem('oauth_code_verifier');
    window.localStorage.removeItem('oauth_code_verifier');

    const response = await fetch(TOKEN_PROXY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            grant_type: 'authorization_code',
            client_id: OAUTH_CONFIG.clientId,
            client_secret: '4514D82B1A25A3682B8E22DAC87885B29521CBFEDE2382682F5E356933C9B473',
            redirect_uri: OAUTH_CONFIG.callbackUrl,
            code: code,
            code_verifier: codeVerifier
        })
    });

    if (!response.ok) {
        const text = await response.text();
        console.error('Token exchange failed:', response.status, text);
        throw new Error('Failed to exchange code for token: ' + response.status);
    }

    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('Non-JSON response:', text.substring(0, 500));
        throw new Error('Invalid response from token proxy');
    }

    return response.json();
}

async function refreshAccessToken() {
    const refreshToken = readRefreshToken();
    if (!refreshToken) {
        throw new Error('No refresh token available');
    }

    const response = await fetch(TOKEN_PROXY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            grant_type: 'refresh_token',
            client_id: OAUTH_CONFIG.clientId,
            client_secret: '4514D82B1A25A3682B8E22DAC87885B29521CBFEDE2382682F5E356933C9B473',
            refresh_token: refreshToken
        })
    });

    if (!response.ok) {
        const text = await response.text();
        console.error('Token refresh failed:', response.status, text);
        throw new Error('Failed to refresh token: ' + response.status);
    }

    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('Non-JSON response:', text.substring(0, 500));
        throw new Error('Invalid response from token proxy');
    }

    return response.json();
}

function handleOAuthCallback() {
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get('code');
    const state = urlParams.get('state');
    const savedState = window.localStorage.getItem('oauth_state');

    if (code && state === savedState) {
        window.localStorage.removeItem('oauth_state');
        return code;
    }
    return null;
}

async function login() {
    const authUrl = await generateAuthUrl();

    // Initialize Capacitor plugins if needed
    if (isCapacitor() && !capacitorBrowser) {
        await initCapacitorPlugins();
    }

    if (isCapacitor() && capacitorBrowser) {
        // Use native browser for OAuth in Capacitor
        try {
            console.log('[OAuth] Opening native browser for Capacitor');
            // Use Chrome Custom Tabs (Android) or SFSafariViewController (iOS)
            await capacitorBrowser.open({
                url: authUrl,
                presentationStyle: 'fullscreen',
                toolbarColor: '#0176d3'
            });
        } catch (error) {
            console.error('[OAuth] Failed to open browser:', error);
            // Fallback to web flow
            window.location.href = authUrl;
        }
    } else {
        // Web flow
        console.log('[OAuth] Using web flow');
        window.location.href = authUrl;
    }
}

// Handle OAuth callback from native browser
async function handleCapacitorCallback(url) {
    if (!url) return;

    // Parse the callback URL
    const urlObj = new URL(url);
    const code = urlObj.searchParams.get('code');
    const state = urlObj.searchParams.get('state');
    const savedState = window.localStorage.getItem('oauth_state');

    if (code && state === savedState) {
        window.localStorage.removeItem('oauth_state');
        try {
            const tokenData = await exchangeCodeForToken(code);
            const { access_token, refresh_token, instance_url } = tokenData;
            window.localStorage.setItem(TOKEN_KEY, access_token);
            configureRuntime(access_token, refresh_token, instance_url);
            // Close the browser and return to app
            if (capacitorBrowser) {
                await capacitorBrowser.close();
            }
            // Initialize app with new token
            initializeApp();
        } catch (error) {
            console.error('[OAuth] Callback error:', error);
        }
    }
}

// Initialize Capacitor App listener for deep links
let deepLinkListenerAdded = false;
async function initCapacitorListener() {
    if (!isCapacitor()) return;

    // Initialize plugins if not already done
    if (!capacitorApp) {
        await initCapacitorPlugins();
    }

    if (capacitorApp && !deepLinkListenerAdded) {
        deepLinkListenerAdded = true;
        capacitorApp.addListener('appUrlOpen', (data) => {
            const url = data.url;
            console.log('[Capacitor] Deep link received:', url);
            if (url && url.includes(`${APP_SCHEME}://oauth/callback`)) {
                handleCapacitorCallback(url);
            }
        });
    }
}

function logout() {
    window.localStorage.removeItem(TOKEN_KEY);
    window.localStorage.removeItem(REFRESH_TOKEN_KEY);
    window.localStorage.removeItem(INSTANCE_URL_KEY);
    configureRuntime('');
    unmountApp();
    showScreen('login');
}

function mountHomeView() {
    const homeRoot = document.getElementById('view-home');
    if (!homeRoot) {
        return;
    }
    if (!homeRoot.querySelector('c-home-office-messages')) {
        homeRoot.appendChild(createElement('c-home-office-messages', { is: HomeOfficeMessages }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-metrics')) {
        homeRoot.appendChild(createElement('c-field-rep-home-metrics', { is: FieldRepHomeMetrics }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-monthly-timecard')) {
        homeRoot.appendChild(createElement('c-field-rep-home-monthly-timecard', { is: FieldRepHomeMonthlyTimecard }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-today-plan')) {
        homeRoot.appendChild(createElement('c-field-rep-home-today-plan', { is: FieldRepHomeTodayPlan }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-next-best-customer')) {
        homeRoot.appendChild(createElement('c-field-rep-home-next-best-customer', { is: FieldRepHomeNextBestCustomer }));
    }
    if (!homeRoot.querySelector('c-reports-hub')) {
        homeRoot.appendChild(createElement('c-reports-hub', { is: ReportsHub }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-clm-prefetch')) {
        homeRoot.appendChild(createElement('c-field-rep-home-clm-prefetch', { is: FieldRepHomeClmPrefetch }));
    }
}

function mountPlannerView() {
    const plannerRoot = document.getElementById('view-planner');
    if (!plannerRoot) {
        return;
    }
    if (!plannerRoot.querySelector('c-field-rep-planner')) {
        plannerRoot.appendChild(createElement('c-field-rep-planner', { is: FieldRepPlanner }));
    }
}

function mountAccountsView() {
    const accountsRoot = document.getElementById('view-accounts');
    if (!accountsRoot) {
        return;
    }
    if (!accountsRoot.querySelector('c-accounts-tab')) {
        accountsRoot.appendChild(createElement('c-accounts-tab', { is: AccountsTab }));
    }
}

function mountTimeOffView() {
    const timeOffRoot = document.getElementById('view-timeoff');
    if (!timeOffRoot) {
        return;
    }
    if (!timeOffRoot.querySelector('c-time-off-submission')) {
        timeOffRoot.appendChild(createElement('c-time-off-submission', { is: TimeOffSubmission }));
    }
}

function mountClmPresentationsView() {
    const clmRoot = document.getElementById('view-clm');
    if (!clmRoot) {
        return;
    }
    if (!clmRoot.querySelector('c-clm-presentations-hub')) {
        clmRoot.appendChild(createElement('c-clm-presentations-hub', { is: ClmPresentationsHub }));
    }
}

// Map app tab keys (UI API developerName) to their PWA view panel + renderer.
// Entity tabs (object list views) use the generic list page via mountListView.
// Tabs not handled render the "not available" in-panel message.
// Mount the Visit Call Shell (ported LWC). It is a Visit-record component: the
// active Visit id comes from ?visit=, localStorage (set when opening a visit
// from the planner), or — as a fallback so the tab is never empty — the user's
// most recent visit.
async function resolveActiveVisitId() {
    const urlVisit = new URLSearchParams(window.location.search).get('visit');
    if (urlVisit) {
        return urlVisit;
    }
    const stored = window.localStorage.getItem(ACTIVE_VISIT_KEY);
    if (stored) {
        return stored;
    }
    try {
        const base = String(globalThis.PLANNER_SF_INSTANCE || '').replace(/\/$/, '');
        const token = globalThis.PLANNER_ACCESS_TOKEN || '';
        if (!base || !token) {
            return null;
        }
        const q = encodeURIComponent(
            'SELECT Id FROM Visit__c ORDER BY Start_Date__c DESC NULLS LAST LIMIT 1'
        );
        const resp = await fetch(`${base}/services/data/v62.0/query?q=${q}`, {
            headers: { Accept: 'application/json', Authorization: `Bearer ${token}` }
        });
        if (resp.ok) {
            const data = await resp.json();
            const id = data.records && data.records.length ? data.records[0].Id : null;
            if (id) {
                window.localStorage.setItem(ACTIVE_VISIT_KEY, id);
                return id;
            }
        }
    } catch (_err) {
        // Offline / no access — shell shows its empty state.
    }
    return null;
}

function mountVisitCallView() {
    const root = document.getElementById('view-visitcall');
    if (!root) {
        return;
    }
    let el = root.querySelector('c-visit-call-shell');
    if (!el) {
        el = createElement('c-visit-call-shell', { is: VisitCallShell });
        root.appendChild(el);
    }
    resolveActiveVisitId().then((visitId) => {
        if (visitId) {
            el.recordId = visitId;
        }
    });
}

// Open a specific Visit in the Visit Call Shell (replaces the generic record
// page for Visit__c). Called when a Visit row is opened from the entity list.
function openVisitCall(recordId) {
    if (recordId) {
        window.localStorage.setItem(ACTIVE_VISIT_KEY, recordId);
    }
    const root = document.getElementById('view-visitcall');
    const el = root && root.querySelector('c-visit-call-shell');
    if (el && recordId) {
        el.recordId = recordId;
    }
    currentTab = VISIT_CALL_TAB_KEY;
    switchTab(VISIT_CALL_TAB_KEY);
}

// The entity list runs in an iframe; it posts here to open Visit records.
window.addEventListener('message', (event) => {
    const data = event && event.data;
    if (data && data.type === 'open-visit-call' && data.recordId) {
        openVisitCall(data.recordId);
    }
});

const APP_TAB_VIEWS = {
    Field_Rep_Home_App: { panel: 'view-home', mount: mountHomeView },
    Field_Rep_Planner: { panel: 'view-planner', mount: mountPlannerView },
    Accounts_Tab: { panel: 'view-accounts', mount: mountAccountsView },
    Request_Time_Off: { panel: 'view-timeoff', mount: mountTimeOffView },
    CLM_Presentations: { panel: 'view-clm', mount: mountClmPresentationsView },
    Visit_Call: { panel: 'view-visitcall', mount: mountVisitCallView }
};

function isEntityTab(tab) {
    return appTabs.some((t) => t.key === tab && t.type === 'Entity');
}

// A tab is "supported" if it has an offline renderer or is an object list view.
function isSupportedTab(tab) {
    if (!tab) return false;
    if (APP_TAB_VIEWS[tab.key]) return true;
    return tab.type === 'Entity';
}

function switchTab(tab) {
    if (!tab) return;
    currentTab = tab;

    // Update sidebar nav tab active state
    document.querySelectorAll('#app-tabs .nav-tab').forEach(btn => {
        const active = btn.dataset.tab === tab;
        btn.classList.toggle('nav-tab-active', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });

    // Hide all view panels
    document.querySelectorAll('.view-panel').forEach(panel => {
        panel.classList.remove('active');
    });

    if (isEntityTab(tab)) {
        mountListView();
        return;
    }

    const view = APP_TAB_VIEWS[tab];
    if (view) {
        const panel = document.getElementById(view.panel);
        panel?.classList.add('active');
        view.mount();
        return;
    }

    showUnsupportedTab(tab);
}

function showUnsupportedTab(key) {
    const panel = document.getElementById('view-unsupported');
    if (!panel) return;
    const tab = appTabs.find((t) => t.key === key);
    const label = tab ? tab.label : key;
    panel.innerHTML = `
        <div class="unsupported-message">
            <h2>${label}</h2>
            <p>This tab isn't available offline. Open it in Salesforce, or pick another tab from the sidebar.</p>
        </div>
    `;
    panel.classList.add('active');
}

function mountListView() {
    const tabDef = appTabs.find((t) => t.key === currentTab);
    const object = (tabDef && tabDef.objectApiName) || (tabDef && tabDef.key) || '';
    const entityRoot = document.getElementById('view-entity');
    if (!entityRoot) return;
    let iframe = entityRoot.querySelector('iframe');
    if (!iframe) {
        iframe = document.createElement('iframe');
        iframe.style.border = 'none';
        iframe.style.width = '100%';
        iframe.style.height = '100%';
        entityRoot.appendChild(iframe);
    }
    // BASE_URL respects the deploy base (e.g. "/Zeta/" on GitHub Pages, "/" on
    // localhost/Netlify) so the iframe resolves under a subpath, not the domain root.
    const src = `${import.meta.env.BASE_URL}list.html?object=${encodeURIComponent(object)}`;
    if (iframe.dataset.src !== src) {
        iframe.dataset.src = src;
        iframe.src = src;
    }
    entityRoot.classList.add('active');
}

function unmountApp() {
    const homeRoot = document.getElementById('view-home');
    const accountsRoot = document.getElementById('view-accounts');
    const plannerRoot = document.getElementById('view-planner');
    const entityRoot = document.getElementById('view-entity');
    const unsupportedRoot = document.getElementById('view-unsupported');
    if (homeRoot) homeRoot.innerHTML = '';
    if (accountsRoot) accountsRoot.innerHTML = '';
    if (plannerRoot) plannerRoot.innerHTML = '';
    if (entityRoot) entityRoot.innerHTML = '';
    if (unsupportedRoot) unsupportedRoot.innerHTML = '';
    currentTab = HOME_TAB_KEY;
}

function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) {
        return;
    }
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').catch((error) => {
            console.warn('Service worker registration failed', error);
        });
    });
}

// Show exactly one top-level screen: 'login' | 'chooser' | 'app'.
function showScreen(name) {
    const login = document.getElementById('session-bar');
    const chooser = document.getElementById('app-chooser');
    const nav = document.getElementById('app-nav');
    const shell = document.getElementById('app');
    // Toggle inline display, not the [hidden] attribute: .app-nav / .session-bar
    // set `display` in CSS, which would otherwise override [hidden].
    if (login) login.style.display = name === 'login' ? 'flex' : 'none';
    if (chooser) chooser.style.display = name === 'chooser' ? 'block' : 'none';
    if (nav) nav.style.display = name === 'app' ? 'flex' : 'none';
    if (shell) shell.style.display = name === 'app' ? '' : 'none';
}

// Salesforce-style App Launcher: search across apps + items, open an app or
// jump straight to a single object/tab. Renders Pharma immediately (local,
// always tappable), then augments with the org's apps once fetchApps resolves.
let chooserApps = [];
let chooserItems = [];
let chooserSearchWired = false;

function buildAppChooser() {
    showScreen('chooser');
    const grid = document.getElementById('app-chooser-grid');
    if (!grid) return;

    // Seed instantly with the local Pharma app so the launcher is never blank.
    chooserApps = [PHARMA_APP];
    chooserItems = buildItemsFromApps(chooserApps);
    renderChooser();
    wireChooserSearch();

    fetchApps()
        .then((apps) => {
            if (apps && apps.length) {
                chooserApps = apps;
                renderChooser();
            }
        })
        .catch((error) => {
            console.warn('[AppChooser] Failed to load org apps:', error);
        });

    // "All Items" comes from the org-wide /tabs list (every object + flexipage
    // the user can open), not just the selected app's navItems.
    fetchTabs()
        .then((tabs) => {
            if (tabs && tabs.length) {
                chooserItems = tabs;
                renderChooser();
            }
        })
        .catch((error) => {
            console.warn('[AppChooser] Failed to load org tabs:', error);
        });
}

// Flatten every app's tabs into a de-duped, sorted item list (the "All Items"
// section — objects, record pages and flexipage tabs the user can open).
function buildItemsFromApps(apps) {
    const seen = new Map();
    (apps || []).forEach((app) => {
        (app.tabs || []).forEach((tab) => {
            if (tab && tab.key && !seen.has(tab.key)) {
                seen.set(tab.key, tab);
            }
        });
    });
    return Array.from(seen.values()).sort((a, b) =>
        (a.label || '').localeCompare(b.label || '')
    );
}

function wireChooserSearch() {
    if (chooserSearchWired) return;
    const input = document.getElementById('chooser-search');
    if (!input) return;
    chooserSearchWired = true;
    input.addEventListener('input', renderChooser);
}

function renderChooser() {
    const term = (document.getElementById('chooser-search')?.value || '').trim().toLowerCase();
    const match = (label) => !term || (label || '').toLowerCase().includes(term);
    renderAppCards(chooserApps.filter((a) => match(a.label)));
    renderItemCards(chooserItems.filter((i) => match(i.label)));
}

// Build an icon element: real image when a URL loads, else a letter tile.
// A broken/blocked icon URL falls back to the letter instead of a blank gap.
function buildIconEl(url, label, baseCls) {
    const letter = (label || '?').charAt(0);
    const fallback = document.createElement('span');
    fallback.className = `${baseCls} ${baseCls}-fallback`;
    fallback.textContent = letter;
    if (!url) return fallback;

    const img = document.createElement('img');
    img.className = baseCls;
    img.src = url;
    img.alt = '';
    img.loading = 'lazy';
    img.addEventListener('error', () => {
        if (img.parentNode) img.parentNode.replaceChild(fallback, img);
    });
    return img;
}

function renderAppCards(apps) {
    const grid = document.getElementById('app-chooser-grid');
    if (!grid) return;
    grid.innerHTML = '';
    if (!apps.length) {
        grid.innerHTML = '<p class="chooser-empty">No matching apps.</p>';
        return;
    }
    apps.forEach((app) => {
        const card = document.createElement('button');
        card.className = 'chooser-card' + (app.fullOffline ? ' chooser-card-offline' : '');
        card.type = 'button';
        card.title = app.label;

        const tabCount = (app.tabs && app.tabs.length) || 0;
        const desc = app.description || `${tabCount} tab${tabCount === 1 ? '' : 's'}`;
        const body = document.createElement('span');
        body.className = 'chooser-card-body';
        body.innerHTML =
            `<span class="chooser-card-title">${app.label}</span>` +
            `<span class="chooser-card-desc">${desc}</span>`;

        card.appendChild(buildIconEl(app.iconUrl, app.label, 'chooser-card-icon'));
        card.appendChild(body);
        if (app.fullOffline) {
            const badge = document.createElement('span');
            badge.className = 'chooser-card-badge';
            badge.textContent = 'Offline ready';
            card.appendChild(badge);
        }
        card.addEventListener('click', () => openApp(app));
        grid.appendChild(card);
    });
}

function renderItemCards(items) {
    const grid = document.getElementById('item-chooser-grid');
    if (!grid) return;
    grid.innerHTML = '';
    if (!items.length) {
        grid.innerHTML = '<p class="chooser-empty">No matching items.</p>';
        return;
    }
    items.forEach((item) => {
        const chip = document.createElement('button');
        chip.className = 'chooser-item';
        chip.type = 'button';
        chip.title = item.label;

        const label = document.createElement('span');
        label.className = 'chooser-item-label';
        label.textContent = item.label;

        chip.appendChild(buildIconEl(item.iconUrl, item.label, 'chooser-item-icon'));
        chip.appendChild(label);
        chip.addEventListener('click', () => openItem(item));
        grid.appendChild(chip);
    });
}

// Open a single object/tab directly (the "All Items" behaviour), so the shell
// shows just that item. switchTab handles entity list views, known offline
// views and the "not available" fallback.
function openItem(item) {
    if (!item || !item.key) return;
    const tabs = [item];
    appTabs = tabs;
    const titleEl = document.getElementById('nav-title');
    if (titleEl) titleEl.textContent = item.label || 'Item';
    renderTabButtons(tabs);
    currentTab = item.key;
    showScreen('app');
    switchTab(item.key);
}

// Open the chosen app: load its tabs, render the sidebar, show the app screen.
function openApp(app) {
    const tabs = app && Array.isArray(app.tabs) ? app.tabs.slice() : [];
    appTabs = tabs;
    const titleEl = document.getElementById('nav-title');
    if (titleEl) titleEl.textContent = (app && app.label) || 'App';

    renderTabButtons(tabs);
    showScreen('app');

    // Land on the first tab that actually renders (Home preferred), so the app
    // never opens on a blank "not available" panel. All tabs stay in the nav.
    const homeTab = tabs.find((t) => t.key === HOME_TAB_KEY && isSupportedTab(t));
    const firstSupported = tabs.find(isSupportedTab);
    currentTab = (homeTab || firstSupported || tabs[0] || {}).key || null;

    if (currentTab) {
        switchTab(currentTab);
    } else {
        // App returned no tabs (only the org's *selected* app exposes navItems).
        // Clear any stale panel and show a clean empty state.
        showEmptyApp(app);
    }
}

function showEmptyApp(app) {
    document.querySelectorAll('.view-panel').forEach((p) => p.classList.remove('active'));
    const panel = document.getElementById('view-unsupported');
    if (!panel) return;
    const label = (app && app.label) || 'This app';
    panel.innerHTML = `
        <div class="unsupported-message">
            <h2>${label}</h2>
            <p>No offline-available tabs for this app. Use <strong>All Items</strong> in the launcher to open an object, or open the app in Salesforce.</p>
        </div>
    `;
    panel.classList.add('active');
}

function renderTabButtons(tabs) {
    const tabsContainer = document.getElementById('app-tabs');
    if (!tabsContainer) return;
    tabsContainer.innerHTML = '';
    tabs.forEach((tab) => {
        const btn = document.createElement('button');
        btn.className = 'nav-tab';
        btn.type = 'button';
        btn.role = 'tab';
        btn.dataset.tab = tab.key;
        btn.setAttribute('aria-selected', 'false');
        btn.title = tab.label;

        const icon = tab.iconUrl
            ? `<img class="nav-icon" src="${tab.iconUrl}" alt="" loading="lazy" onerror="this.style.display='none'" />`
            : defaultTabIcon();
        btn.innerHTML = `${icon}<span>${tab.label}</span>`;
        btn.addEventListener('click', () => switchTab(tab.key));
        tabsContainer.appendChild(btn);
    });
}

function defaultTabIcon() {
    return `<svg class="nav-icon" viewBox="0 0 520 520" fill="currentColor" aria-hidden="true">
        <path d="M490 270h-50v220c0 6-4 10-10 10H330c-6 0-10-4-10-10V320H200v170c0 6-4 10-10 10H90c-6 0-10-4-10-10V270H30c-4 0-8-2-9-6-2-4-1-8 2-11L253 23c4-4 11-4 14 0l230 230c3 3 3 7 2 11s-5 6-9 6z"/>
    </svg>`;
}

function setupNavigation() {
    // Sidebar nav tabs are rendered per-app by openApp() after the launcher.
    // Mode toggle switch
    setupModeToggle();
}

function setupModeToggle() {
    const navActions = document.querySelector('.nav-actions');
    if (!navActions) return;

    // Create mode toggle container
    const modeToggle = document.createElement('div');
    modeToggle.className = 'mode-toggle';

    // Create label
    const label = document.createElement('span');
    label.className = 'mode-toggle-label';
    label.textContent = 'Mode';

    // Create switch container
    const switchContainer = document.createElement('label');
    switchContainer.className = 'mode-toggle-switch';

    // Create checkbox input
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.id = 'mode-toggle-checkbox';

    // Create slider
    const slider = document.createElement('span');
    slider.className = 'mode-toggle-slider';

    // Create icons inside slider
    const offlineIcon = document.createElement('span');
    offlineIcon.className = 'mode-toggle-icon offline';
    offlineIcon.textContent = '✕';

    const onlineIcon = document.createElement('span');
    onlineIcon.className = 'mode-toggle-icon online';
    onlineIcon.textContent = '✓';

    // Create status badge
    const statusBadge = document.createElement('span');
    statusBadge.className = 'mode-toggle-status';
    statusBadge.id = 'mode-toggle-status';

    // Assemble the switch
    slider.appendChild(offlineIcon);
    slider.appendChild(onlineIcon);
    switchContainer.appendChild(checkbox);
    switchContainer.appendChild(slider);

    // Assemble the toggle
    modeToggle.appendChild(label);
    modeToggle.appendChild(switchContainer);
    modeToggle.appendChild(statusBadge);

    // Insert before logout button
    const logoutBtn = navActions.querySelector('.nav-btn-logout');
    navActions.insertBefore(modeToggle, logoutBtn);

    // Update UI based on current state
    function updateToggleUI() {
        const isForcedOffline = getForceOffline();
        checkbox.checked = !isForcedOffline;
        if (isForcedOffline) {
            statusBadge.textContent = 'Offline';
            statusBadge.classList.remove('online');
            statusBadge.classList.add('offline');
        } else {
            statusBadge.textContent = 'Online';
            statusBadge.classList.remove('offline');
            statusBadge.classList.add('online');
        }
    }

    // Initialize UI
    updateToggleUI();

    // Handle toggle change
    checkbox.addEventListener('change', () => {
        const goOffline = !checkbox.checked;
        setForceOfflineAndSync(goOffline);
        updateToggleUI();

        // Show toast notification
        const toastEvent = new CustomEvent('lightning__showtoast', {
            detail: {
                title: goOffline ? 'Offline Mode' : 'Online Mode',
                message: goOffline
                    ? 'Working offline. Changes will sync when you go back online.'
                    : 'Back online. Syncing pending changes...',
                variant: goOffline ? 'warning' : 'success'
            }
        });
        window.dispatchEvent(toastEvent);
    });
}

// Debug function to test the endpoint
window.testAccountsEndpoint = async function() {
    const restBase = globalThis.PLANNER_REST_BASE || '(not set)';
    const token = globalThis.PLANNER_ACCESS_TOKEN || '(not set)';
    const endpoint = '/services/apexrest/planner/v1/accounts-tab/page?pageSize=1';
    const fullUrl = `${restBase}${endpoint}`;

    console.log('=== DEBUG: Testing Accounts Endpoint ===');
    console.log('Base URL:', restBase);
    console.log('Token present:', !!token);
    console.log('Token (first 20 chars):', token ? token.substring(0, 20) + '...' : 'none');
    console.log('Endpoint:', endpoint);
    console.log('Full URL:', fullUrl);

    try {
        const response = await fetch(fullUrl, {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
                'Authorization': `Bearer ${token}`
            }
        });
        console.log('Response status:', response.status);
        console.log('Response status text:', response.statusText);
        const text = await response.text();
        console.log('Response body (first 500 chars):', text.substring(0, 500));
        return { status: response.status, body: text };
    } catch (error) {
        console.error('Fetch error:', error.message);
        return { error: error.message };
    }
};

function setupSessionBar(token) {
    const loginBtn = document.getElementById('login-btn');
    const logoutBtn = document.getElementById('logout-btn');

    if (logoutBtn) {
        logoutBtn.addEventListener('click', logout);
    }

    const chooserLogoutBtn = document.getElementById('chooser-logout-btn');
    if (chooserLogoutBtn) {
        chooserLogoutBtn.addEventListener('click', logout);
    }

    // "Switch app" returns to the launcher without dropping the session.
    const switchAppBtn = document.getElementById('switch-app-btn');
    if (switchAppBtn) {
        switchAppBtn.addEventListener('click', buildAppChooser);
    }

    if (loginBtn) {
        loginBtn.addEventListener('click', login);
    }
    // Screen visibility is owned by showScreen(); this only wires buttons.
}

async function initializeApp() {
    // Debug: Log platform detection
    console.log('[App] Initializing...');
    console.log('[App] User Agent:', navigator.userAgent);
    console.log('[App] Initial window.Capacitor:', typeof window.Capacitor);

    // Wait for Capacitor to be ready (important for remote URL loading)
    const capacitorReady = await waitForCapacitor(3000);
    console.log('[App] Capacitor ready:', capacitorReady);
    console.log('[App] After wait window.Capacitor:', typeof window.Capacitor);
    console.log('[App] isNativePlatform:', window.Capacitor?.isNativePlatform?.());
    console.log('[App] isCapacitor():', isCapacitor());
    console.log('[App] callbackUrl:', OAUTH_CONFIG.callbackUrl);

    // Initialize Capacitor listener for deep links
    await initCapacitorListener();

    // Handle OAuth callback (web flow)
    const code = handleOAuthCallback();
    if (code) {
        try {
            const tokenData = await exchangeCodeForToken(code);
            const { access_token, refresh_token, instance_url } = tokenData;
            console.log('[OAuth] Token exchange successful');
            console.log('[OAuth] Instance URL:', instance_url);
            console.log('[OAuth] Access token (first 20 chars):', access_token?.substring(0, 20) + '...');
            window.localStorage.setItem(TOKEN_KEY, access_token);
            configureRuntime(access_token, refresh_token, instance_url);
            // Clean URL
            window.history.replaceState({}, document.title, window.location.pathname);
        } catch (error) {
            console.error('OAuth callback error:', error);
        }
    } else {
        // Try to refresh token if we have one
        const refreshToken = readRefreshToken();
        if (refreshToken && !readToken()) {
            try {
                const tokenData = await refreshAccessToken();
                const { access_token, instance_url } = tokenData;
                console.log('[OAuth] Token refresh successful');
                console.log('[OAuth] Instance URL:', instance_url);
                window.localStorage.setItem(TOKEN_KEY, access_token);
                configureRuntime(access_token, null, instance_url);
            } catch (error) {
                console.error('Token refresh error:', error);
                logout();
                return;
            }
        }
    }

    const token = readToken();
    configureRuntime(token);
    console.log('[App] PLANNER_REST_BASE:', globalThis.PLANNER_REST_BASE);
    console.log('[App] PLANNER_ACCESS_TOKEN present:', !!globalThis.PLANNER_ACCESS_TOKEN);
    console.log('[App] PLANNER_SF_INSTANCE:', globalThis.PLANNER_SF_INSTANCE);
    setupNavigation();
    setupSessionBar(token);
    setupToastListener();
    if (token) {
        // Signed in → app launcher (pick which app to open).
        buildAppChooser();
    } else {
        showScreen('login');
    }
    registerServiceWorker();

    registerOfflineListener((status) => {
        console.log('[OfflineSyncListener] Sync phase changed:', status);
    });
    startSyncService();
}

initializeApp();
