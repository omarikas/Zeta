const SF_INSTANCE =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
  'https://zetapharma.my.salesforce.com';
const API_TOKEN =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
  '';
const REST_BASE = SF_INSTANCE;

const DEFAULT_API_VERSION = 'v62.0';
let apiVersion = DEFAULT_API_VERSION;

const describeCache = {};
let currentObject = null;

function el(id) { return document.getElementById(id); }

function setVisible(id, show) {
    const node = el(id);
    if (node) node.style.display = show ? '' : 'none';
}

function showError(msg) {
    const bar = el('list-error');
    if (!bar) return;
    if (msg) { bar.textContent = msg; bar.style.display = 'block'; }
    else { bar.style.display = 'none'; }
}

function showLoading(show) {
    setVisible('list-loading', show);
}

function readCache(key) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (_err) { /* corrupt */ }
    return null;
}

async function sfFetch(path) {
    if (!API_TOKEN) {
        throw new Error('Not signed in. Open the app, sign in with Salesforce, then try again.');
    }
    const headers = { Accept: 'application/json', 'Content-Type': 'application/json' };
    headers.Authorization = `Bearer ${API_TOKEN}`;
    const url = `${String(REST_BASE).replace(/\/$/, '')}/services/data/${apiVersion}${path}`;
    const resp = await fetch(url, { method: 'GET', headers });
    if (resp.status === 401) {
        throw new Error('Session expired. Sign in again in the main app.');
    }
    if (!resp.ok) {
        let detail = `HTTP ${resp.status}`;
        try {
            const err = await resp.json();
            const first = Array.isArray(err) ? err[0] : err;
            detail = first?.message || detail;
        } catch (_err) { /* keep status */ }
        throw new Error(detail);
    }
    return resp.json();
}

async function getDescribe(object) {
    const key = String(object).toLowerCase();
    if (describeCache[key]) return describeCache[key];
    const fromStorage = readCache(`pwa_cache_record_desc.${key}`);
    if (fromStorage && fromStorage.payload) {
        describeCache[key] = fromStorage.payload;
    } else {
        const desc = await sfFetch(`/sobjects/${encodeURIComponent(object)}/describe`);
        describeCache[key] = desc;
        try { localStorage.setItem(`pwa_cache_record_desc.${key}`, JSON.stringify({ savedAt: Date.now(), payload: desc })); } catch (_err) {}
    }
    return describeCache[key];
}

function pickDefaultFields(describe) {
    const preferred = ['Id', 'Name', 'CreatedDate', 'LastModifiedDate'];
    const present = [];
    for (const p of preferred) {
        const f = describe.fields.find((x) => x.name === p && !x.nameOfObject && x.type !== 'base64' && x.type !== 'address');
        if (f) present.push(p);
    }
    if (!present.includes('Id')) present.unshift('Id');
    return present.slice(0, 4);
}

function sanitizeFields(list, describe) {
    const names = new Set(describe.fields.map((f) => f.name));
    const out = [];
    for (let raw of list) {
        let f = String(raw).trim();
        if (!f) continue;
        if (f.endsWith('__r')) f = f.slice(0, -3); // drop relationship suffix to query id
        if (f === 'attributes') continue;
        if (!names.has(f)) continue;
        if (!out.includes(f)) out.push(f);
    }
    return out;
}

async function runQuery(object) {
    const describe = await getDescribe(object);
    let fields = pickDefaultFields(describe);

    let soql = `SELECT ${fields.join(', ')} FROM ${object} LIMIT 200`;

    const encoded = encodeURIComponent(soql);
    const url = `/query?q=${encoded}`;
    const data = await sfFetch(url);

    const records = [...(data.records || [])];
    let next = data.nextRecordsUrl;
    const seen = new Set(records.map((r) => r.Id));
    // Walk pagination up to a cap so the list stays responsive on mobile.
    while (next && records.length < 1000) {
        const nxt = await sfFetch(next);
        for (const r of nxt.records || []) {
            if (r.Id && seen.has(r.Id)) continue;
            if (r.Id) seen.add(r.Id);
            records.push(r);
        }
        next = nxt.nextRecordsUrl;
    }

    currentObject = object;
    renderList(records, fields, describe);
    setVisible('list-result', true);
    showError('');
    return records.length;
}

function renderList(records, fields, describe) {
    const fieldInfo = {};
    for (const f of describe.fields) fieldInfo[f.name] = f;

    const thead = el('list-thead');
    thead.innerHTML = '';
    let tr = document.createElement('tr');
    const thIndex = document.createElement('th');
    thIndex.scope = 'col';
    thIndex.className = 'col-row';
    thIndex.textContent = '#';
    tr.appendChild(thIndex);
    for (const f of fields) {
        const th = document.createElement('th');
        th.scope = 'col';
        th.textContent = (fieldInfo[f] && fieldInfo[f].label) || f;
        th.title = f;
        tr.appendChild(th);
    }
    thead.appendChild(tr);

    const tbody = el('list-tbody');
    tbody.innerHTML = '';

    let shown = 0;
    records.forEach((record, index) => {
        const rowTr = document.createElement('tr');
        rowTr.className = 'list-row';
        rowTr.dataset.id = record.Id || '';
        rowTr.dataset.object = currentObject || '';
        rowTr.addEventListener('click', handleRowClick);

        const tdIdx = document.createElement('td');
        tdIdx.className = 'col-row list-cell';
        tdIdx.textContent = index + 1;
        rowTr.appendChild(tdIdx);

        for (const f of fields) {
            const td = document.createElement('td');
            td.className = 'list-cell';
            const value = record[f];
            if (f === 'Id' && record.Id) {
                const link = document.createElement('a');
                link.className = 'list-link';
                link.href = `/record.html?recordId=${encodeURIComponent(record.Id)}&object=${encodeURIComponent(currentObject || '')}`;
                link.textContent = record.Id;
                link.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); openRecord(record.Id, currentObject); });
                td.appendChild(link);
            } else if (value != null && typeof value === 'object' && value.attributes && value.attributes.type) {
                const link = document.createElement('a');
                link.className = 'list-link';
                link.href = `/record.html?recordId=${encodeURIComponent(value.Id)}&object=${encodeURIComponent(value.attributes.type)}`;
                link.textContent = value.Name || value.Id;
                link.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); openRecord(value.Id, value.attributes.type); });
                td.appendChild(link);
            } else {
                td.textContent = formatCell(fieldInfo[f], value);
            }
            rowTr.appendChild(td);
        }
        tbody.appendChild(rowTr);
        shown += 1;
    });

    if (shown === 0) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = fields.length + 1;
        td.className = 'list-empty';
        td.textContent = 'No records returned.';
        tr.appendChild(td);
        tbody.appendChild(tr);
    }
}

function formatCell(field, value) {
    if (value == null || value === '') return '—';
    const type = field?.type;
    switch (type) {
        case 'boolean': return value ? 'Yes' : 'No';
        case 'datetime': {
            const d = new Date(value);
            return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleString();
        }
        case 'date': return String(value);
        case 'currency':
        case 'double':
        case 'percent': {
            const n = Number(value);
            return Number.isFinite(n) ? n.toLocaleString(undefined, { maximumFractionDigits: 2 }) : String(value);
        }
        default:
            return typeof value === 'object' ? JSON.stringify(value) : String(value);
    }
}

function openRecord(id, object) {
    if (!id) return;
    window.open(`/record.html?recordId=${encodeURIComponent(id)}&object=${encodeURIComponent(object || '')}`, '_blank');
}

function handleRowClick(event) {
    const row = event.currentTarget;
    openRecord(row.dataset.id, row.dataset.object);
}

function setupQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const version = params.get('apiVersion');
    if (version && /^v\d+\.\d+$/.test(version)) {
        apiVersion = version;
    }
}

async function init() {
    setupQueryParams();
    const params = new URLSearchParams(window.location.search);
    const object = params.get('object');
    if (!object) {
        showError('No object specified.');
        return;
    }
    showLoading(true);
    try {
        await runQuery(object);
    } catch (err) {
        showError(err?.message || 'Query failed.');
    } finally {
        showLoading(false);
    }
}

document.addEventListener('DOMContentLoaded', init);
