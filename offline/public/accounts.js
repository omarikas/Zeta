const REST_BASE = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
const API_TOKEN = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
const SF_INSTANCE = (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || '';

const PAGE_SIZE = 10;
const SEARCH_DEBOUNCE_MS = 350;
const SCOPE_BOTH = 'both';
const SCOPE_IN = 'in';
const SCOPE_OUT = 'out';
const SORT_BY_NAME = 'name';
const SORT_BY_SCORE = 'agentforceScore';
const SORT_BY_CLASS = 'classification';
const SORT_DIR_DESC = 'desc';

let state = {
    rows: [],
    viewMode: 'list',
    scope: SCOPE_BOTH,
    searchTerm: '',
    recordType: 'All',
    classification: 'All',
    sortBy: SORT_BY_SCORE,
    sortDirection: SORT_DIR_DESC,
    currentPage: 1,
    totalCount: 0,
    inPlanCount: 0,
    outPlanCount: 0,
    behindPaceCount: 0,
    recordTypeCounts: [],
    isLoading: false,
    errorMessage: '',
    hasCachedData: false,
    syncStatus: 'idle',
    mapEligibleCount: 0,
    mapRows: [],
    mapCurrentPage: 1,
    selectedAccountId: null,
    collections: []
};

let searchDebounce = null;

function getCacheKey() {
    return `accounts.${state.scope}.${state.searchTerm}.${state.recordType}.${state.classification}.${state.sortBy}.${state.sortDirection}.${state.currentPage}`;
}

function getMapCacheKey() {
    return `accounts.map.${state.scope}.${state.searchTerm}.${state.recordType}.${state.classification}.${state.sortBy}.${state.sortDirection}.${state.mapCurrentPage}`;
}

function el(id) { return document.getElementById(id); }

function showSyncChip(status, label) {
    const chip = el('sync-chip');
    if (!chip) return;
    if (status === 'idle') { chip.style.display = 'none'; return; }
    chip.style.display = 'inline-flex';
    chip.className = `sync-chip sync-chip-${status}`;
    chip.textContent = label;
}

function showError(msg) {
    const bar = el('error-banner');
    if (!bar) return;
    if (msg) { bar.textContent = msg; bar.style.display = 'block'; }
    else { bar.style.display = 'none'; }
}

async function readCache(key) {
    try {
        const raw = localStorage.getItem('pwa_cache_' + key);
        if (raw) return JSON.parse(raw);
    } catch (_) { /* no cache */ }
    return null;
}

async function writeCache(key, data) {
    try {
        localStorage.setItem('pwa_cache_' + key, JSON.stringify(data));
    } catch (_) { /* storage full */ }
}

async function fetchAccounts(params, isMap = false) {
    const path = '/services/apexrest/planner/v1/accounts-tab/page';
    const body = {
        scope: params.scope,
        searchTerm: params.searchTerm || null,
        recordTypeDeveloperName: params.recordType !== 'All' ? params.recordType : null,
        classification: params.classification !== 'All' ? params.classification : null,
        sortBy: params.sortBy,
        sortDirection: params.sortDirection,
        offset: (params.page - 1) * (isMap ? 5 : PAGE_SIZE),
        pageSize: isMap ? 5 : PAGE_SIZE,
        monthStart: null,
        contextUserId: null,
        accountIds: null
    };
    const headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const url = REST_BASE ? `${REST_BASE.replace(/\/$/, '')}${path}` : path;
    const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
}

async function fetchMapPoints(params) {
    const path = '/services/apexrest/planner/v1/accounts-tab/map-points';
    const body = {
        scope: params.scope,
        searchTerm: params.searchTerm || null,
        recordTypeDeveloperName: params.recordType !== 'All' ? params.recordType : null,
        classification: params.classification !== 'All' ? params.classification : null,
        sortBy: params.sortBy,
        sortDirection: params.sortDirection,
        offset: (params.page - 1) * 5,
        pageSize: 5,
        monthStart: null,
        contextUserId: null,
        accountIds: null
    };
    const headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const url = REST_BASE ? `${REST_BASE.replace(/\/$/, '')}${path}` : path;
    const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
}

async function loadPage() {
    state.isLoading = true;
    showError('');
    state.rows = [];
    renderList();

    const cacheKey = getCacheKey();
    const cached = await readCache(cacheKey);
    if (cached) {
        applyPageData(cached);
        state.hasCachedData = true;
        state.syncStatus = 'cached';
        showSyncChip('cached', 'Cached');
    }

    if (!navigator.onLine) {
        state.isLoading = false;
        if (!state.hasCachedData) showError('You are offline. Connect to load accounts.');
        state.syncStatus = 'offline';
        showSyncChip('offline', 'Offline');
        return;
    }

    state.syncStatus = 'updating';
    showSyncChip('updating', 'Updating…');
    try {
        const result = await fetchAccounts({
            scope: state.scope,
            searchTerm: state.searchTerm,
            recordType: state.recordType,
            classification: state.classification,
            sortBy: state.sortBy,
            sortDirection: state.sortDirection,
            page: state.currentPage
        });
        state.rows = (result?.rows || []).map(r => mapRow(r));
        state.totalCount = result?.totalCount || 0;
        state.inPlanCount = result?.inPlanCount || 0;
        state.outPlanCount = result?.outPlanCount || 0;
        state.behindPaceCount = result?.behindPaceCount || 0;
        state.recordTypeCounts = result?.recordTypeCounts || [];
        state.mapEligibleCount = result?.mapEligibleCount || 0;
        state.currentPage = result?.currentPage || state.currentPage;
        await writeCache(cacheKey, { rows: state.rows, totalCount: state.totalCount, inPlanCount: state.inPlanCount, outPlanCount: state.outPlanCount, behindPaceCount: state.behindPaceCount, recordTypeCounts: state.recordTypeCounts, mapEligibleCount: state.mapEligibleCount });
        state.hasCachedData = true;
        state.errorMessage = '';
        state.syncStatus = 'idle';
        showSyncChip('cached', 'Cached');
    } catch (err) {
        if (!state.hasCachedData) {
            showError(err?.message || 'Unable to load accounts.');
            state.syncStatus = 'offline';
            showSyncChip('offline', 'Offline');
        }
    }
    state.isLoading = false;
    renderSummary();
    renderList();
    renderPagination();
}

async function loadMapPage() {
    state.isLoading = true;
    showError('');
    state.mapRows = [];
    renderMapList();

    if (!navigator.onLine) {
        state.isLoading = false;
        if (!state.hasCachedData) showError('You are offline.');
        return;
    }

    try {
        const [pageResult, mapResult] = await Promise.all([
            fetchAccounts({ scope: state.scope, searchTerm: state.searchTerm, recordType: state.recordType, classification: state.classification, sortBy: state.sortBy, sortDirection: state.sortDirection, page: 1 }, false),
            fetchMapPoints({ scope: state.scope, searchTerm: state.searchTerm, recordType: state.recordType, classification: state.classification, sortBy: state.sortBy, sortDirection: state.sortDirection, page: state.mapCurrentPage })
        ]);
        state.totalCount = pageResult?.totalCount || 0;
        state.inPlanCount = pageResult?.inPlanCount || 0;
        state.outPlanCount = pageResult?.outPlanCount || 0;
        state.behindPaceCount = pageResult?.behindPaceCount || 0;
        state.recordTypeCounts = pageResult?.recordTypeCounts || [];
        state.mapEligibleCount = mapResult?.mapEligibleCount || 0;
        state.mapRows = (mapResult?.rows || []).map(r => mapRow(r));
        state.syncStatus = 'idle';
        showSyncChip('cached', 'Cached');
    } catch (err) {
        if (!state.hasCachedData) showError(err?.message || 'Unable to load accounts.');
        state.syncStatus = 'offline';
    }
    state.isLoading = false;
    renderSummary();
    renderMapList();
    renderMapPagination();
}

function mapRow(row) {
    const target = row.targetVisits;
    const actual = row.actualVisits || 0;
    const planned = row.plannedVisits || 0;
    return {
        ...row,
        reachPercentDisplay: row.reachPercent != null ? `${Math.round(Number(row.reachPercent))}%` : '—',
        callPlanLabel: target != null ? `${actual}/${target}` : '—',
        paceStatusLabel: row.paceStatusLabel || '—',
        agentforceScoreDisplay: row.agentforceScore != null ? Number(row.agentforceScore).toFixed(1) : '—',
        riskDotClass: `risk-dot-${(row.agentforceRisk || 'Low').toLowerCase()}`
    };
}

function applyPageData(data) {
    state.rows = (data.rows || []).map(r => mapRow(r));
    state.totalCount = data.totalCount || 0;
    state.inPlanCount = data.inPlanCount || 0;
    state.outPlanCount = data.outPlanCount || 0;
    state.behindPaceCount = data.behindPaceCount || 0;
    state.recordTypeCounts = data.recordTypeCounts || [];
    state.mapEligibleCount = data.mapEligibleCount || 0;
}

function renderSummary() {
    const ids = ['total-count', 'in-plan-count', 'out-plan-count', 'behind-count'];
    const vals = [state.totalCount, state.inPlanCount, state.outPlanCount, state.behindPaceCount];
    ids.forEach((id, i) => { const e = el(id); if (e) e.textContent = vals[i]; });
}

function navigateToAccount(accountId) {
    if (accountId) {
        window.location.href = `/visits.html?accountId=${accountId}`;
    }
}

function renderList() {
    const list = el('account-list');
    if (!list) return;
    if (state.rows.length === 0 && !state.isLoading) {
        list.innerHTML = '<p class="empty-state">No accounts match the current filters.</p>';
        return;
    }
    list.innerHTML = state.rows.map(r => `
        <div class="account-row" data-id="${r.accountId || ''}" onclick="navigateToAccount('${r.accountId || ''}')">
            <div class="account-row-top">
                <span class="account-name">${escHtml(r.accountName)}</span>
                <span class="account-classification">${escHtml(r.classification || '—')}</span>
            </div>
            <div class="account-row-sub">
                <span>${escHtml(r.recordTypeName || '')}</span>
                <span>${escHtml(r.city || '')}</span>
                <span>${r.callPlanLabel}</span>
                <span class="${r.riskDotClass}"></span>
            </div>
        </div>
    `).join('');
}

function renderMapList() {
    const list = el('map-account-list');
    if (!list) return;
    if (state.mapRows.length === 0 && !state.isLoading) {
        list.innerHTML = '<li class="map-empty">No accounts match the current filters.</li>';
        return;
    }
    const countLabel = state.mapRows.length > 0 ? `${state.mapRows.length} of ${state.mapEligibleCount} on map` : '0 on map';
    const countEl = el('map-count');
    if (countEl) countEl.textContent = countLabel;
    list.innerHTML = state.mapRows.map(r => `
        <li class="map-account-item" data-id="${r.accountId || ''}" onclick="navigateToAccount('${r.accountId || ''}')">
            <div class="map-account-item-top">
                <span class="map-account-type">${r.riskDotClass === 'risk-dot-high' ? 'HCO' : 'HCP'}</span>
                <span class="map-account-badge">${escHtml(r.classification || '—')}</span>
            </div>
            <p class="map-account-name">${escHtml(r.accountName)}</p>
            <p class="map-account-subtitle">${escHtml(r.subtitle || '')}</p>
        </li>
    `).join('');
}

function renderPagination() {
    const totalPages = Math.max(1, Math.ceil(state.totalCount / PAGE_SIZE));
    const nav = el('pagination');
    if (!nav) return;
    nav.style.display = totalPages > 1 ? 'flex' : 'none';
    const label = el('page-label');
    if (label) label.textContent = `Page ${state.currentPage} of ${totalPages}`;
    const prev = el('btn-prev');
    const next = el('btn-next');
    if (prev) prev.disabled = state.currentPage <= 1;
    if (next) next.disabled = state.currentPage >= totalPages;
}

function renderMapPagination() {
    const totalPages = Math.max(1, Math.ceil(state.mapEligibleCount / 5));
    const nav = el('map-pagination');
    if (!nav) return;
    nav.style.display = totalPages > 1 ? 'flex' : 'none';
    const label = el('map-page-label');
    if (label) label.textContent = `Page ${state.mapCurrentPage} of ${totalPages}`;
    const prev = el('btn-map-prev');
    const next = el('btn-map-next');
    if (prev) prev.disabled = state.mapCurrentPage <= 1;
    if (next) next.disabled = state.mapCurrentPage >= totalPages;
}

function escHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
}

function debounce(fn, ms) {
    return function(...args) {
        clearTimeout(searchDebounce);
        searchDebounce = setTimeout(() => fn.apply(this, args), ms);
    };
}

function init() {
    const searchInput = el('search-input');
    if (searchInput) {
        searchInput.addEventListener('input', debounce(() => {
            state.searchTerm = searchInput.value;
            state.currentPage = 1;
            loadPage();
        }, SEARCH_DEBOUNCE_MS));
    }

    const refreshBtn = el('btn-refresh');
    if (refreshBtn) refreshBtn.addEventListener('click', () => loadPage());

    const toggleBtn = el('btn-toggle-view');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => {
            state.viewMode = state.viewMode === 'list' ? 'map' : 'list';
            toggleBtn.textContent = state.viewMode === 'list' ? 'Map' : 'List';
            el('list-view').style.display = state.viewMode === 'list' ? 'block' : 'none';
            el('map-view').style.display = state.viewMode === 'map' ? 'flex' : 'none';
            if (state.viewMode === 'map') loadMapPage();
        });
    }

    const prevBtn = el('btn-prev');
    if (prevBtn) prevBtn.addEventListener('click', () => { if (state.currentPage > 1) { state.currentPage--; loadPage(); } });

    const nextBtn = el('btn-next');
    if (nextBtn) nextBtn.addEventListener('click', () => { const tp = Math.ceil(state.totalCount / PAGE_SIZE); if (state.currentPage < tp) { state.currentPage++; loadPage(); } });

    const mapPrevBtn = el('btn-map-prev');
    if (mapPrevBtn) mapPrevBtn.addEventListener('click', () => { if (state.mapCurrentPage > 1) { state.mapCurrentPage--; loadMapPage(); } });

    const mapNextBtn = el('btn-map-next');
    if (mapNextBtn) mapNextBtn.addEventListener('click', () => { const tp = Math.ceil(state.mapEligibleCount / 5); if (state.mapCurrentPage < tp) { state.mapCurrentPage++; loadMapPage(); } });

    loadPage();

    window.addEventListener('online', () => { loadPage(); loadMapPage(); });
    window.addEventListener('offline', () => { showSyncChip('offline', 'Offline'); showError('You are offline.'); });
}

document.addEventListener('DOMContentLoaded', init);