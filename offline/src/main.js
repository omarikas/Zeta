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
let currentTab = 'home';

function readToken() {
    return (
        import.meta.env.VITE_SF_ACCESS_TOKEN ||
        window.localStorage.getItem(TOKEN_KEY) ||
        ''
    ).trim();
}

function configureRuntime(token) {
    globalThis.PLANNER_REST_BASE = window.location.origin;
    globalThis.PLANNER_ACCESS_TOKEN = token;
    globalThis.PLANNER_SF_INSTANCE =
        import.meta.env.VITE_SF_INSTANCE_URL || 'https://zetapharma.my.salesforce.com';
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
    const form = document.getElementById('session-form');
    const input = document.getElementById('token-input');
    const nav = document.getElementById('app-nav');
    const logoutBtn = document.getElementById('logout-btn');

    if (logoutBtn) {
        logoutBtn.addEventListener('click', () => {
            window.localStorage.removeItem(TOKEN_KEY);
            configureRuntime('');
            unmountApp();
            if (nav) {
                nav.hidden = true;
            }
            if (bar) {
                bar.hidden = false;
            }
            if (input) {
                input.value = '';
            }
        });
    }

    if (!bar || !form || !input) {
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

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        const next = (input.value || '').trim();
        if (!next) {
            return;
        }
        window.localStorage.setItem(TOKEN_KEY, next);
        configureRuntime(next);
        bar.hidden = true;
        if (nav) {
            nav.hidden = false;
        }
        mountApp();
    });
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
