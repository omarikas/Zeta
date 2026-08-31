import '@lwc/synthetic-shadow';
import { createElement } from 'lwc';
import FieldRepHomeMetrics from 'c/fieldRepHomeMetrics';
import FieldRepHomeTodayPlan from 'c/fieldRepHomeTodayPlan';
import FieldRepHomeNextBestCustomer from 'c/fieldRepHomeNextBestCustomer';
import FieldRepPlanner from 'c/fieldRepPlanner';
import AccountsTab from 'c/accountsTab';
import { startSyncService, registerOfflineListener } from 'c/clmOfflineSync';
import { setupToastListener } from './toastManager';
import './slds-shim.css';
import './shell.css';

const TOKEN_KEY = 'zeta.pwa.sfAccessToken';
const REFRESH_TOKEN_KEY = 'zeta.pwa.sfRefreshToken';
const INSTANCE_URL_KEY = 'zeta.pwa.sfInstanceUrl';
let currentTab = 'home';

// OAuth Configuration
const OAUTH_CONFIG = {
    clientId: '3MVG9U65ySgtae71Qj6sHa91riS85fiD5Ndf7MVHpJQwOPlo1bAScoaXG28Yvfwx05xwl.R8NaGGLPFUDSj_y',
    loginUrl: 'https://zetapharma.my.salesforce.com',
    callbackUrl: 'https://omarikas.github.io/Zeta',
    scopes: 'api refresh_token'
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
    const isLocalDev = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
    // In local dev, use Vite proxy (window.location.origin → /services proxied to SF)
    // In production (GitHub Pages), call Salesforce directly with the instance URL
    globalThis.PLANNER_REST_BASE = isLocalDev ? window.location.origin : sfInstance;
    globalThis.PLANNER_ACCESS_TOKEN = token;
    globalThis.PLANNER_SF_INSTANCE = sfInstance;

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
// After deploying to Vercel, replace with your actual URL
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
        throw new Error('Failed to exchange code for token');
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
        throw new Error('Failed to refresh token');
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
    window.location.href = await generateAuthUrl();
}

function logout() {
    window.localStorage.removeItem(TOKEN_KEY);
    window.localStorage.removeItem(REFRESH_TOKEN_KEY);
    window.localStorage.removeItem(INSTANCE_URL_KEY);
    configureRuntime('');
    unmountApp();
    const nav = document.getElementById('app-nav');
    const bar = document.getElementById('session-bar');
    if (nav) nav.hidden = true;
    if (bar) bar.hidden = false;
}

function mountHomeView() {
    const homeRoot = document.getElementById('view-home');
    if (!homeRoot) {
        return;
    }
    if (!homeRoot.querySelector('c-field-rep-home-metrics')) {
        homeRoot.appendChild(createElement('c-field-rep-home-metrics', { is: FieldRepHomeMetrics }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-today-plan')) {
        homeRoot.appendChild(createElement('c-field-rep-home-today-plan', { is: FieldRepHomeTodayPlan }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-next-best-customer')) {
        homeRoot.appendChild(createElement('c-field-rep-home-next-best-customer', { is: FieldRepHomeNextBestCustomer }));
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

function switchTab(tab) {
    currentTab = tab;
    const homeBtn = document.getElementById('tab-btn-home');
    const accountsBtn = document.getElementById('tab-btn-accounts');
    const plannerBtn = document.getElementById('tab-btn-planner');
    const visitsBtn = document.getElementById('tab-btn-visits');
    const homePanel = document.getElementById('view-home');
    const accountsPanel = document.getElementById('view-accounts');
    const plannerPanel = document.getElementById('view-planner');
    const visitsPanel = document.getElementById('view-visits');

    homeBtn?.classList.remove('nav-tab-active');
    homeBtn?.setAttribute('aria-selected', 'false');
    accountsBtn?.classList.remove('nav-tab-active');
    accountsBtn?.setAttribute('aria-selected', 'false');
    plannerBtn?.classList.remove('nav-tab-active');
    plannerBtn?.setAttribute('aria-selected', 'false');
    visitsBtn?.classList.remove('nav-tab-active');
    visitsBtn?.setAttribute('aria-selected', 'false');

    homePanel?.classList.remove('active');
    accountsPanel?.classList.remove('active');
    plannerPanel?.classList.remove('active');
    visitsPanel?.classList.remove('active');

    if (tab === 'planner') {
        plannerBtn?.classList.add('nav-tab-active');
        plannerBtn?.setAttribute('aria-selected', 'true');
        plannerPanel?.classList.add('active');
        mountPlannerView();
    } else if (tab === 'accounts') {
        accountsBtn?.classList.add('nav-tab-active');
        accountsBtn?.setAttribute('aria-selected', 'true');
        accountsPanel?.classList.add('active');
        mountAccountsView();
    } else if (tab === 'visits') {
        visitsBtn?.classList.add('nav-tab-active');
        visitsBtn?.setAttribute('aria-selected', 'true');
        visitsPanel?.classList.add('active');
        mountVisitsView();
    } else {
        homeBtn?.classList.add('nav-tab-active');
        homeBtn?.setAttribute('aria-selected', 'true');
        homePanel?.classList.add('active');
        mountHomeView();
    }
}

function mountVisitsView() {
    const visitsRoot = document.getElementById('view-visits');
    if (!visitsRoot) return;
    if (!visitsRoot.querySelector('iframe')) {
        const iframe = document.createElement('iframe');
        iframe.src = '/visits.html';
        iframe.style.border = 'none';
        iframe.style.width = '100%';
        iframe.style.height = '100%';
        visitsRoot.appendChild(iframe);
    }
}

function mountApp() {
    if (currentTab === 'planner') {
        mountPlannerView();
    } else if (currentTab === 'accounts') {
        mountAccountsView();
    } else if (currentTab === 'visits') {
        mountVisitsView();
    } else {
        mountHomeView();
    }
}

function unmountApp() {
    const homeRoot = document.getElementById('view-home');
    const accountsRoot = document.getElementById('view-accounts');
    const plannerRoot = document.getElementById('view-planner');
    const visitsRoot = document.getElementById('view-visits');
    if (homeRoot) homeRoot.innerHTML = '';
    if (accountsRoot) accountsRoot.innerHTML = '';
    if (plannerRoot) plannerRoot.innerHTML = '';
    if (visitsRoot) visitsRoot.innerHTML = '';
    switchTab('home');
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

function setupNavigation() {
    const homeBtn = document.getElementById('tab-btn-home');
    const accountsBtn = document.getElementById('tab-btn-accounts');
    const plannerBtn = document.getElementById('tab-btn-planner');
    const visitsBtn = document.getElementById('tab-btn-visits');

    homeBtn?.addEventListener('click', () => switchTab('home'));
    accountsBtn?.addEventListener('click', () => switchTab('accounts'));
    plannerBtn?.addEventListener('click', () => switchTab('planner'));
    visitsBtn?.addEventListener('click', () => switchTab('visits'));
}

function setupSessionBar(token) {
    const bar = document.getElementById('session-bar');
    const loginBtn = document.getElementById('login-btn');
    const nav = document.getElementById('app-nav');
    const logoutBtn = document.getElementById('logout-btn');

    if (logoutBtn) {
        logoutBtn.addEventListener('click', logout);
    }

    if (loginBtn) {
        loginBtn.addEventListener('click', login);
    }

    if (!bar) {
        return;
    }

    if (!token) {
        bar.hidden = false;
        if (nav) {
            nav.hidden = true;
        }
    } else if (nav) {
        nav.hidden = false;
    }
}

async function initializeApp() {
    // Handle OAuth callback
    const code = handleOAuthCallback();
    if (code) {
        try {
            const tokenData = await exchangeCodeForToken(code);
            const { access_token, refresh_token, instance_url } = tokenData;
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
    setupNavigation();
    setupSessionBar(token);
    setupToastListener();
    if (token) {
        mountApp();
    }
    registerServiceWorker();

    registerOfflineListener((status) => {
        console.log('[OfflineSyncListener] Sync phase changed:', status);
    });
    startSyncService();
}

initializeApp();
