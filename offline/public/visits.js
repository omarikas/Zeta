const REST_BASE = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
const API_TOKEN = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
const SF_INSTANCE = (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || '';

const HCP_RECORD_TYPES = new Set(['SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount', 'Business_Contact']);

let state = {
    visits: [],
    currentVisitId: null,
    visit: null,
    activeTab: 'details',
    isLoading: true,
    errorMessage: '',
    statusValue: 'Draft',
    isSaving: false,
    visitObjective: '',
    visitNotes: '',
    selectedProducts: [],
    nextVisitDate: '',
    cancellationReason: '',
    statusFilter: 'All',
    accountIdFilter: null
};

function el(id) { return document.getElementById(id); }

function escHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
}

function formatDateTime(value) {
    if (!value) return '—';
    try { return new Date(value).toLocaleString([], { weekday: 'short', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); }
    catch (_) { return '—'; }
}

function formatDate(value) {
    if (!value) return '';
    try { return new Date(value).toISOString().slice(0, 10); }
    catch (_) { return ''; }
}

function isHCP(recordTypeDeveloperName) {
    return HCP_RECORD_TYPES.has(recordTypeDeveloperName);
}

function getAccountBadgeLabel(visit) {
    const devName = visit?.accountRecordTypeDeveloperName || '';
    if (isHCP(devName)) return 'HCP';
    if (devName === 'Institution_HCO' || (visit?.accountRecordTypeName || '').toLowerCase().includes('hco')) return 'HCO';
    return visit?.accountRecordTypeName || 'Account';
}

function getAccountBadgeClass(visit) {
    return isHCP(visit?.accountRecordTypeDeveloperName || '') ? 'account-badge account-badge-hcp' : 'account-badge account-badge-hco';
}

function getStatusBadgeClass(status) {
    return `status-badge status-badge-${(status || 'Draft').toLowerCase()}`;
}

function getPathSteps(visit) {
    const current = visit?.status || 'Draft';
    const isUnplanned = (visit?.visitType || '') === 'Unplanned';
    const steps = isUnplanned
        ? [{ key: 'Scheduled', label: 'Scheduled' }, { key: 'Completed', label: 'Completed' }]
        : [{ key: 'Draft', label: 'Draft' }, { key: 'Submitted', label: 'Submitted' }, { key: 'Scheduled', label: 'Scheduled' }, { key: 'Completed', label: 'Completed' }];
    if (current === 'Cancelled') {
        return steps.map(s => ({ ...s, stepClass: 'path-step path-step-cancelled', isCurrent: false, isComplete: false }))
            .concat({ key: 'Cancelled', label: 'Cancelled', stepClass: 'path-step path-step-current path-step-cancelled', isCurrent: true, isComplete: false });
    }
    const order = steps.map(s => s.key);
    const currentIndex = order.indexOf(current);
    return steps.map((step, index) => {
        const isCurrent = step.key === current;
        const isComplete = currentIndex > index;
        let stepClass = 'path-step';
        if (isCurrent) stepClass += ' path-step-current';
        else if (isComplete) stepClass += ' path-step-complete';
        return { ...step, stepClass, isCurrent, isComplete };
    });
}

async function fetchVisits() {
    const path = '/services/apexrest/planner/v1/week';
    const today = new Date().toISOString().slice(0, 10);
    const weekStart = new Date();
    weekStart.setDate(weekStart.getDate() - weekStart.getDay());
    const weekStartStr = weekStart.toISOString().slice(0, 10);
    const url = `${REST_BASE ? REST_BASE.replace(/\/$/, '') : ''}${path}?weekStart=${weekStartStr}&weekEnd=${today}&contextUserId=`;
    const headers = { 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const resp = await fetch(url, { headers });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = await resp.json();
    const visits = (data?.visits || []).map(v => ({
        ...v,
        accountName: v?.accountName || v?.name || '—',
        status: v?.status || 'Draft',
        accountRecordTypeDeveloperName: v?.accountRecordTypeDeveloperName || '',
        accountRecordTypeName: v?.accountRecordTypeName || '',
        startDateTime: v?.startDateTime,
        endDateTime: v?.endDateTime,
        assignedToName: v?.assignedToName || v?.assignedTo || '—',
        visitType: v?.visitType || 'Scheduled',
        planRejectionReason: v?.planRejectionReason || ''
    }));
    return visits;
}

async function fetchVisitDetail(visitId) {
    const path = `/services/apexrest/planner/v1/visits/${visitId}`;
    const headers = { 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const url = `${REST_BASE ? REST_BASE.replace(/\/$/, '') : ''}${path}`;
    const resp = await fetch(url, { headers });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
}

function applyVisit(data) {
    state.visit = data;
    state.statusValue = data.status || 'Draft';
    state.visitObjective = data.visitObjective || '';
    state.visitNotes = data.visitNotes || '';
    state.selectedProducts = data.productsDiscussed || [];
    state.nextVisitDate = formatDate(data.nextVisitDate);
    state.cancellationReason = data.cancellationReason || '';
    el('vd-status').value = state.statusValue;
    el('vd-objective').value = state.visitObjective;
    el('vd-notes').value = state.visitNotes;
    el('vd-next-visit').value = state.nextVisitDate;
    el('vd-cancellation').value = state.cancellationReason;
    el('vd-cancellation-field').style.display = state.statusValue === 'Cancelled' ? 'block' : 'none';
    const pendingEl = el('vd-pending-approval');
    if (pendingEl) pendingEl.style.display = state.statusValue === 'Submitted' ? 'block' : 'none';
}

 function renderVisitList() {
    const list = el('visit-list');
    if (!list) return;
    const filtered = state.visits.filter(v => {
        if (state.statusFilter !== 'All' && v.status !== state.statusFilter) return false;
        if (state.searchTerm && !v.accountName?.toLowerCase().includes(state.searchTerm.toLowerCase())) return false;
        if (state.accountIdFilter && v.accountId !== state.accountIdFilter) return false;
        return true;
    });
    if (filtered.length === 0) {
        list.innerHTML = '';
        el('visit-list-loading').style.display = 'none';
        el('visit-list-empty').style.display = 'block';
        return;
    }
    el('visit-list-loading').style.display = 'none';
    el('visit-list-empty').style.display = 'none';
    list.innerHTML = filtered.map(v => `
        <li class="visit-list-item" data-id="${v.id || ''}" onclick="showVisitDetail('${v.id || ''}')">
            <div class="visit-list-item-top">
                <span class="${getAccountBadgeClass(v)}">${getAccountBadgeLabel(v)}</span>
                <span class="${getStatusBadgeClass(v.status)}">${escHtml(v.status)}</span>
            </div>
            <p class="visit-list-account-name">${escHtml(v.accountName)}</p>
            <p class="visit-list-meta">${escHtml(formatDateTime(v.startDateTime))} · ${escHtml(v.visitType || '')}</p>
        </li>
    `).join('');
}

function renderDetail() {
    const v = state.visit;
    if (!v) return;
    const badge = el('visit-account-badge');
    if (badge) { badge.textContent = getAccountBadgeLabel(v); badge.className = getAccountBadgeClass(v); }
    const statusBadge = el('visit-status-badge');
    if (statusBadge) { statusBadge.textContent = v.status || '—'; statusBadge.className = getStatusBadgeClass(v.status); }
    const nameEl = el('visit-account-name');
    if (nameEl) nameEl.textContent = v.accountName || '—';
    const metaEl = el('visit-account-meta');
    if (metaEl) metaEl.textContent = [v.accountSpecialty, v.accountCity].filter(Boolean).join(' · ') || '—';

    const heroActions = el('hero-actions');
    if (heroActions) heroActions.style.display = 'flex';

    const pathEl = el('visit-path');
    if (pathEl) {
        pathEl.innerHTML = getPathSteps(v).map(s => `<div class="${s.stepClass}"><span class="path-step-label">${escHtml(s.label)}</span></div>`).join('');
    }

    const detailFields = {
        'vd-name': v.name || '—',
        'vd-start': formatDateTime(v.startDateTime),
        'vd-end': formatDateTime(v.endDateTime),
        'vd-duration': v.durationLabel || '—',
        'vd-type': v.visitType || '—',
        'vd-assigned': v.assignedToName || '—'
    };
    Object.entries(detailFields).forEach(([id, val]) => { const e = el(id); if (e) e.textContent = val; });

    const rejectionEl = el('vd-plan-rejection');
    if (rejectionEl) {
        rejectionEl.style.display = v.planRejectionReason ? 'block' : 'none';
        const textEl = el('vd-plan-rejection-text');
        if (textEl) textEl.textContent = v.planRejectionReason;
    }
}

function switchTab(tab) {
    state.activeTab = tab;
    document.querySelectorAll('.visit-tab').forEach(t => t.style.display = 'none');
    const tabEl = el('tab-' + tab);
    if (tabEl) tabEl.style.display = 'block';
    document.querySelectorAll('.nav-item').forEach(n => {
        n.classList.toggle('nav-item-active', n.dataset.key === tab);
    });
}

function showVisitDetail(visitId) {
    state.currentVisitId = visitId;
    loadVisitDetail(visitId);
}

async function loadVisits() {
    state.isLoading = true;
    el('visit-list-loading').style.display = 'block';
    el('visit-list-empty').style.display = 'none';
    try {
        const params = new URLSearchParams(window.location.search);
        state.accountIdFilter = params.get('accountId');
        state.visits = await fetchVisits();
        if (state.accountIdFilter) {
            const account = state.visits.find(v => v.accountId === state.accountIdFilter);
            if (account) {
                el('visit-title').textContent = account.accountName || 'Visits';
            } else {
                el('visit-title').textContent = 'Visits';
            }
        } else {
            el('visit-title').textContent = 'Visits';
        }
        renderVisitList();
    } catch (err) {
        el('visit-list-loading').style.display = 'none';
        el('visit-list-empty').style.display = 'block';
        el('visit-list-empty').textContent = err?.message || 'Unable to load visits.';
    }
    state.isLoading = false;
}

async function loadVisitDetail(visitId) {
    state.isLoading = true;
    try {
        const data = await fetchVisitDetail(visitId);
        applyVisit(data);
        renderDetail();
        el('visits-list-view').style.display = 'none';
        el('visit-detail-view').style.display = 'block';
        el('visit-title').textContent = data.accountName || 'Visit';
        switchTab('details');
    } catch (err) {
        const errBar = el('visit-error');
        if (errBar) { errBar.textContent = err?.message || 'Unable to load visit.'; errBar.style.display = 'block'; }
    }
    state.isLoading = false;
}

function init() {
    const params = new URLSearchParams(window.location.search);
    state.accountIdFilter = params.get('accountId');

    const searchInput = el('visit-search');
    if (searchInput) {
        searchInput.addEventListener('input', () => {
            state.searchTerm = searchInput.value;
            renderVisitList();
        });
    }

    const statusFilter = el('visit-status-filter');
    if (statusFilter) {
        statusFilter.addEventListener('change', () => {
            state.statusFilter = statusFilter.value;
            renderVisitList();
        });
    }

    const backBtn = el('btn-back');
    if (backBtn) backBtn.addEventListener('click', () => {
        el('visits-list-view').style.display = 'block';
        el('visit-detail-view').style.display = 'none';
        el('visit-title').textContent = 'Visits';
    });

    document.querySelectorAll('.nav-item').forEach(btn => {
        btn.addEventListener('click', () => switchTab(btn.dataset.key));
    });

    const statusSelect = el('vd-status');
    if (statusSelect) {
        statusSelect.addEventListener('change', () => {
            state.statusValue = statusSelect.value;
            el('vd-cancellation-field').style.display = state.statusValue === 'Cancelled' ? 'block' : 'none';
            const pendingEl = el('vd-pending-approval');
            if (pendingEl) pendingEl.style.display = state.statusValue === 'Submitted' ? 'block' : 'none';
        });
    }

    const saveBtn = el('btn-save-visit');
    if (saveBtn) saveBtn.addEventListener('click', async () => {
        state.isSaving = true;
        saveBtn.disabled = true;
        saveBtn.textContent = 'Saving…';
        try {
            const path = `/services/apexrest/planner/v1/visits/${state.currentVisitId}`;
            const headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
            if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
            const url = `${REST_BASE ? REST_BASE.replace(/\/$/, '') : ''}${path}`;
            const body = {
                status: state.statusValue,
                visitObjective: el('vd-objective').value,
                visitNotes: el('vd-notes').value,
                productsDiscussed: el('vd-products').value,
                productDetails: el('vd-product-details').value,
                nextVisitDate: el('vd-next-visit').value || null,
                cancellationReason: state.cancellationReason || null
            };
            const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
            if (!resp.ok) throw new Error(`Save failed: HTTP ${resp.status}`);
            await loadVisitDetail(state.currentVisitId);
        } catch (err) {
            const errBar = el('visit-error');
            if (errBar) { errBar.textContent = err?.message || 'Save failed.'; errBar.style.display = 'block'; }
        } finally {
            state.isSaving = false;
            saveBtn.disabled = false;
            saveBtn.textContent = 'Save Visit';
        }
    });

    const viewAccountBtn = el('btn-view-account');
    if (viewAccountBtn) viewAccountBtn.addEventListener('click', () => {
        window.location.href = '/accounts.html';
    });

    const plannerBtn = el('btn-open-planner');
    if (plannerBtn) plannerBtn.addEventListener('click', () => {
        window.location.href = '/index.html';
    });

    loadVisits();
    window.addEventListener('online', () => loadVisits());
    window.addEventListener('offline', () => {
        const errBar = el('visit-error');
        if (errBar) { errBar.textContent = 'You are offline.'; errBar.style.display = 'block'; }
    });
}

    const statusFilter = el('visit-status-filter');
    if (statusFilter) {
        statusFilter.addEventListener('change', () => {
            state.statusFilter = statusFilter.value;
            renderVisitList();
        });
    }

    const backBtn = el('btn-back');
    if (backBtn) backBtn.addEventListener('click', () => {
        el('visits-list-view').style.display = 'block';
        el('visit-detail-view').style.display = 'none';
        el('visit-title').textContent = 'Visits';
    });

    document.querySelectorAll('.nav-item').forEach(btn => {
        btn.addEventListener('click', () => switchTab(btn.dataset.key));
    });

    const statusSelect = el('vd-status');
    if (statusSelect) {
        statusSelect.addEventListener('change', () => {
            state.statusValue = statusSelect.value;
            el('vd-cancellation-field').style.display = state.statusValue === 'Cancelled' ? 'block' : 'none';
            const pendingEl = el('vd-pending-approval');
            if (pendingEl) pendingEl.style.display = state.statusValue === 'Submitted' ? 'block' : 'none';
        });
    }

    const saveBtn = el('btn-save-visit');
    if (saveBtn) saveBtn.addEventListener('click', async () => {
        state.isSaving = true;
        saveBtn.disabled = true;
        saveBtn.textContent = 'Saving…';
        try {
            const path = `/services/apexrest/planner/v1/visits/${state.currentVisitId}`;
            const headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
            if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
            const url = `${REST_BASE ? REST_BASE.replace(/\/$/, '') : ''}${path}`;
            const body = {
                status: state.statusValue,
                visitObjective: el('vd-objective').value,
                visitNotes: el('vd-notes').value,
                productsDiscussed: el('vd-products').value,
                productDetails: el('vd-product-details').value,
                nextVisitDate: el('vd-next-visit').value || null,
                cancellationReason: state.cancellationReason || null
            };
            const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
            if (!resp.ok) throw new Error(`Save failed: HTTP ${resp.status}`);
            await loadVisitDetail(state.currentVisitId);
        } catch (err) {
            const errBar = el('visit-error');
            if (errBar) { errBar.textContent = err?.message || 'Save failed.'; errBar.style.display = 'block'; }
        } finally {
            state.isSaving = false;
            saveBtn.disabled = false;
            saveBtn.textContent = 'Save Visit';
        }
    });

    const viewAccountBtn = el('btn-view-account');
    if (viewAccountBtn) viewAccountBtn.addEventListener('click', () => {
        if (state.visit?.accountId && SF_INSTANCE) {
            window.open(`${SF_INSTANCE.replace(/\/$/, '')}/lightning/r/Account/${state.visit.accountId}/view`, '_blank');
        }
    });

    const plannerBtn = el('btn-open-planner');
    if (plannerBtn) plannerBtn.addEventListener('click', () => {
        if (SF_INSTANCE) window.open(`${SF_INSTANCE.replace(/\/$/, '')}/lightning/n/Field_Rep_Planner`, '_blank');
    });

    loadVisits();
    window.addEventListener('online', () => loadVisits());
    window.addEventListener('offline', () => {
        const errBar = el('visit-error');
        if (errBar) { errBar.textContent = 'You are offline.'; errBar.style.display = 'block'; }
    });
}

document.addEventListener('DOMContentLoaded', init);