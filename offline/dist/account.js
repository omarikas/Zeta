const SF_INSTANCE =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
  'https://zetapharma.my.salesforce.com';
const API_TOKEN =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
  '';
const REST_BASE = SF_INSTANCE;

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
    const bar = el('account-error');
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

async function fetchAccount(accountId) {
    const path = `/services/apexrest/planner/v1/accounts/${encodeURIComponent(accountId)}`;
    const headers = { 'Accept': 'application/json' };
    if (API_TOKEN) headers['Authorization'] = `Bearer ${API_TOKEN}`;
    const url = `${String(REST_BASE).replace(/\/$/, '')}${path}`;
    const resp = await fetch(url, { method: 'GET', headers });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const contentType = resp.headers.get('content-type') || '';
    if (!contentType.includes('application/json')) {
        throw new Error('Account data unavailable (unexpected response).');
    }
    return resp.json();
}

function formatAddress(data) {
    const parts = [];
    if (data.shippingStreet) parts.push(data.shippingStreet);
    if (data.shippingCity && data.shippingState) {
        parts.push(`${data.shippingCity}, ${data.shippingState}`);
    } else if (data.shippingCity) {
        parts.push(data.shippingCity);
    }
    if (data.shippingPostalCode) parts.push(data.shippingPostalCode);
    if (data.shippingCountry) parts.push(data.shippingCountry);
    return parts.length ? parts.join(' · ') : '—';
}

function riskBadgeClass(risk) {
    const r = String(risk || '').toLowerCase();
    if (r.includes('high')) return 'badge-high';
    if (r.includes('med') || r.includes('moderate')) return 'badge-med';
    if (r.includes('low')) return 'badge-low';
    return 'badge-default';
}

function setValue(id, value) {
    const node = el(id);
    if (node) node.textContent = value == null || value === '' ? '—' : String(value);
}

function render(data) {
    el('account-hero').style.display = 'block';
    el('account-grid').style.display = 'grid';

    setValue('account-name', data.name);
    setValue('account-specialty', data.specialty);
    setValue('account-record-type', data.recordTypeName);
    setValue('account-classification', data.classification);

    const riskLabel = data.agentforceRisk || '—';
    const riskEl = el('account-risk');
    riskEl.textContent = riskLabel;
    riskEl.className = `badge ${riskBadgeClass(data.agentforceRisk)}`;

    setValue('field-phone', data.phone);
    setValue('field-business-unit', data.businessUnit);
    setValue('field-record-type', data.recordTypeName);

    setValue('field-address', formatAddress(data));
    setValue('field-city-state', data.shippingCity && data.shippingState ? `${data.shippingCity}, ${data.shippingState}` : (data.shippingCity || '—'));
    setValue('field-postal', data.shippingPostalCode);
    setValue('field-country', data.shippingCountry);

    setValue('field-agentforce-score', data.agentforceScore != null ? Number(data.agentforceScore).toFixed(1) : '—');
    setValue('field-agentforce-risk', riskLabel);
    setValue('field-projected-percent', data.projectedPercent != null ? `${Math.round(Number(data.projectedPercent))}%` : '—');

    setValue('field-visits', `${data.actualVisits || 0}/${data.targetVisits != null ? data.targetVisits : 'No target'}`);
    setValue('field-pace-status', data.paceStatusLabel || data.paceStatus || '—');
    setValue('field-plan-cycle', data.planCycleLabel);
}

async function loadAccount() {
    const params = new URLSearchParams(window.location.search);
    const accountId = params.get('accountId');
    if (!accountId) {
        showError('No account specified. Go back and select an account.');
        el('account-loading').style.display = 'none';
        return;
    }

    const cacheKey = `account.${accountId}`;
    const cached = await readCache(cacheKey);
    if (cached) {
        render(cached);
        el('account-loading').style.display = 'none';
        showSyncChip('cached', 'Cached');
    }

    if (!navigator.onLine) {
        if (!cached) {
            showError('You are offline. Connect to load this account.');
            el('account-loading').style.display = 'none';
            showSyncChip('offline', 'Offline');
        }
        return;
    }

    showSyncChip('updating', 'Updating…');
    try {
        const data = await fetchAccount(accountId);
        if (data && !data.error) {
            await writeCache(cacheKey, data);
            render(data);
            el('account-loading').style.display = 'none';
            showError('');
            showSyncChip('cached', 'Cached');
        } else {
            throw new Error(data?.error || 'Account not found');
        }
    } catch (err) {
        if (!cached) {
            showError(err?.message || 'Unable to load account.');
            el('account-loading').style.display = 'none';
            showSyncChip('offline', 'Offline');
        }
    }
}

function init() {
    const backBtn = el('btn-back');
    if (backBtn) {
        backBtn.addEventListener('click', () => { window.location.href = '/accounts.html'; });
    }
    window.addEventListener('online', loadAccount);
    window.addEventListener('offline', () => {
        showSyncChip('offline', 'Offline');
        showError('You are offline.');
    });
    loadAccount();
}

document.addEventListener('DOMContentLoaded', init);
