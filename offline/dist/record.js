const SF_INSTANCE =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
  'https://zetapharma.my.salesforce.com';
const API_TOKEN =
  (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
  (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
  '';
const REST_BASE = SF_INSTANCE;
const PREFIX_CACHE_KEY = 'zeta.pwa.sobjectPrefixes';

const DEFAULT_API_VERSION = 'v62.0';
let apiVersion = DEFAULT_API_VERSION;

const describeCache = {};
let prefixMap = null;
let currentRecord = null;
let currentObject = null;
let currentDescribe = null;
let currentMode = 'flat'; // 'layout' when rendered from UI API page layout
let currentGroups = null;

function el(id) { return document.getElementById(id); }

function recordCacheKey(object, id) {
    return `pwa_cache_record.${String(object || '').toLowerCase()}.${id}`;
}

function writeCache(key, data) {
    try {
        localStorage.setItem(key, JSON.stringify({
            fetchedAt: Date.now(),
            payload: data
        }));
    } catch (_err) { /* storage full */ }
}

function readCache(key) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (_err) { /* corrupt or unavailable */ }
    return null;
}

function describeCacheKey(object) {
    return `pwa_cache_record_desc.${String(object || '').toLowerCase()}`;
}

function setVisible(id, show) {
    const node = el(id);
    if (node) node.style.display = show ? '' : 'none';
}

function showError(msg) {
    const bar = el('record-error');
    if (!bar) return;
    if (msg) { bar.textContent = msg; bar.style.display = 'block'; }
    else { bar.style.display = 'none'; }
}

function showLoading(show) {
    setVisible('record-loading', show);
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
        } catch (_err) { /* keep status message */ }
        throw new Error(detail);
    }
    return resp.json();
}

async function getPrefixMap() {
    if (prefixMap) return prefixMap;
    try {
        const raw = localStorage.getItem(PREFIX_CACHE_KEY);
        if (raw) {
            prefixMap = JSON.parse(raw);
            return prefixMap;
        }
    } catch (_err) { /* no cache */ }

    const data = await sfFetch('/sobjects');
    const map = {};
    for (const so of data.sobjects || []) {
        if (so.keyPrefix) map[so.keyPrefix] = so.name;
    }
    prefixMap = map;
    try { localStorage.setItem(PREFIX_CACHE_KEY, JSON.stringify(map)); } catch (_err) { /* storage full */ }
    return map;
}

async function resolveObject(recordId) {
    const prefix = String(recordId).slice(0, 3).toUpperCase();
    const map = await getPrefixMap();
    return map[prefix] || null;
}

async function getDescribe(object) {
    const key = String(object).toLowerCase();
    if (describeCache[key]) return describeCache[key];
    const fromStorage = readCache(describeCacheKey(object));
    if (fromStorage && fromStorage.payload) {
        describeCache[key] = fromStorage.payload;
        return describeCache[key];
    }
    const desc = await sfFetch(`/sobjects/${encodeURIComponent(object)}/describe`);
    describeCache[key] = desc;
    writeCache(describeCacheKey(object), desc);
    return desc;
}

function recordUiCacheKey(object, id) {
    return `pwa_cache_record_ui.${String(object || '').toLowerCase()}.${id}`;
}

// Salesforce UI API: returns record values + page layout (sections/rows in
// layout order) + field metadata in one call. Layout order mirrors what the
// user sees in Salesforce; displayValue is already formatted by the platform.
async function getRecordUi(id) {
    return sfFetch(
        `/ui-api/record-ui/${encodeURIComponent(id)}?layoutTypes=Full&modes=View`
    );
}

// Flatten a UI API layout (Full/View) into ordered sections of field items.
function extractLayoutGroups(recordUi, id) {
    const record = recordUi?.records?.[id];
    if (!record) return null;
    const object = record.apiName;
    const objInfo = recordUi.objectInfos?.[object] || { fields: {} };
    const layoutsForObj = recordUi.layouts?.[object] || {};
    const rtId = record.recordTypeId || Object.keys(layoutsForObj)[0];
    const layout = layoutsForObj?.[rtId]?.Full?.View;
    if (!layout || !Array.isArray(layout.sections)) return null;

    const groups = [];
    for (const section of layout.sections) {
        const items = [];
        for (const row of section.layoutRows || []) {
            for (const item of row.layoutItems || []) {
                for (const comp of item.layoutComponents || []) {
                    if (comp.componentType !== 'Field' || !comp.apiName) continue;
                    const apiName = comp.apiName;
                    if (!Object.prototype.hasOwnProperty.call(record.fields, apiName)) continue;
                    const objField = objInfo.fields?.[apiName];
                    items.push({
                        apiName,
                        label: item.label || objField?.label || apiName,
                        cell: record.fields[apiName],
                        dataType: objField?.dataType
                    });
                }
            }
        }
        if (items.length) {
            groups.push({ heading: section.useHeading ? section.heading : '', items });
        }
    }
    return { object, objectLabel: objInfo.label || object, record, groups };
}

function formatUiValue(dataType, cell) {
    if (!cell) return '—';
    const val = cell.value;
    const disp = cell.displayValue;
    if (val == null && disp == null) return '—';
    switch (dataType) {
        case 'Boolean':
            return val ? 'Yes' : 'No';
        case 'Reference': {
            const text = disp || String(val);
            const base = String(SF_INSTANCE).replace(/\.my\./i, '.lightning.');
            return formatLink(`${base.replace(/\/$/, '')}/lightning/r/${val}/view`, text);
        }
        case 'Url':
            return formatLink(String(val), disp || String(val));
        case 'Email':
            return formatLink(`mailto:${val}`, disp || String(val));
        default:
            return disp != null ? disp : String(val);
    }
}

function buildFieldInfo(describe) {
    const map = {};
    for (const f of describe.fields || []) {
        map[f.name.toLowerCase()] = f;
    }
    return map;
}

function pickTitle(record) {
    if (record.Name) return record.Name;
    if (record.FirstName || record.LastName) {
        return `${record.FirstName || ''} ${record.LastName || ''}`.trim();
    }
    if (record.Label) return record.Label;
    if (record.Title) return record.Title;
    if (record.Subject) return record.Subject;
    return record.Id;
}

function formatCompound(value) {
    if (value == null) return '—';
    if (typeof value !== 'object') return String(value);
    const parts = [];
    for (const key of ['street', 'city', 'state', 'postalCode', 'country']) {
        if (value[key] != null && value[key] !== '') parts.push(value[key]);
    }
    return parts.length ? parts.join(' · ') : '—';
}

function formatLink(href, text) {
    const anchor = document.createElement('a');
    anchor.href = href;
    anchor.target = '_blank';
    anchor.rel = 'noopener noreferrer';
    anchor.className = 'record-link';
    anchor.textContent = text;
    return anchor;
}

function formatValue(field, value) {
    if (value == null || value === '') return '—';
    const type = field?.type;

    switch (type) {
        case 'boolean':
            return value ? 'Yes' : 'No';
        case 'datetime':
            return new Date(value).toLocaleString();
        case 'date':
            return String(value);
        case 'reference': {
            const source = String(value);
            const targetType =
                (field.referenceTo || []).find(Boolean) ||
                (prefixMap ? prefixMap[source.slice(0, 3)] : null) ||
                'sObject';
            const base = String(SF_INSTANCE).replace(/\.my\./i, '.lightning.');
            return formatLink(`${base.replace(/\/$/, '')}/lightning/r/${source}/view`, `${targetType}: ${source}`);
        }
        case 'address':
            return formatCompound(value);
        case 'url':
            return formatLink(String(value), String(value));
        case 'currency':
        case 'double':
        case 'percent': {
            const num = Number(value);
            return Number.isFinite(num) ? num.toLocaleString(undefined, { maximumFractionDigits: 2 }) : String(value);
        }
        default: {
            if (typeof value === 'object') return JSON.stringify(value);
            return String(value);
        }
    }
}

function renderRecord(record, object, describe) {
    const fieldInfo = buildFieldInfo(describe);
    currentMode = 'flat';
    currentGroups = null;
    currentRecord = record;
    currentObject = object;
    currentDescribe = describe;
    setVisible('record-sections', false);
    setVisible('record-table-wrap', true);
    const iconEl = el('record-icon');
    if (iconEl) iconEl.textContent = (describe.label || object || '?').trim().charAt(0).toUpperCase();
    const objectBadge = el('record-object-badge');
    objectBadge.textContent = describe.label || object;
    objectBadge.title = `${object} (API name)`;

    const typeBadge = el('record-type-badge');
    if (record.RecordTypeId || record.RecordType) {
        const label = record.RecordType?.Name || prefixMap?.[String(record.RecordTypeId).slice(0, 3)] || record.RecordTypeId;
        typeBadge.textContent = `Record type: ${label}`;
        typeBadge.style.display = '';
    } else {
        typeBadge.style.display = 'none';
    }

    const idBadge = el('record-id-badge');
    idBadge.textContent = record.Id;
    idBadge.title = record.Id;

    el('record-title').textContent = pickTitle(record);

    const subtitleParts = [];
    if (record.CreatedDate) subtitleParts.push(`Created ${new Date(record.CreatedDate).toLocaleString()}`);
    if (record.LastModifiedDate) subtitleParts.push(`Updated ${new Date(record.LastModifiedDate).toLocaleString()}`);
    el('record-subtitle').textContent = subtitleParts.length ? subtitleParts.join(' · ') : '—';

    renderTable(fieldInfo, record, describe, '');
    el('record-raw').textContent = JSON.stringify(record, null, 2);

    showError('');
    setVisible('record-result', true);
}

function renderRecordFromUi(uiGroups, id) {
    currentMode = 'layout';
    currentGroups = uiGroups.groups;
    currentRecord = uiGroups.record;
    currentObject = uiGroups.object;
    currentDescribe = null;

    const record = uiGroups.record;
    const fieldVal = (name) => record.fields?.[name]?.value;
    const fieldDisp = (name) => record.fields?.[name]?.displayValue;

    const objectBadge = el('record-object-badge');
    objectBadge.textContent = uiGroups.objectLabel;
    objectBadge.title = `${uiGroups.object} (API name)`;

    const iconEl = el('record-icon');
    if (iconEl) iconEl.textContent = (uiGroups.objectLabel || '?').trim().charAt(0).toUpperCase();

    const typeBadge = el('record-type-badge');
    const rtName = record.recordTypeInfo?.name;
    if (rtName) {
        typeBadge.textContent = rtName;
        typeBadge.style.display = '';
    } else {
        typeBadge.style.display = 'none';
    }

    const idBadge = el('record-id-badge');
    idBadge.textContent = id;
    idBadge.title = id;

    el('record-title').textContent =
        fieldDisp('Name') || fieldVal('Name') ||
        `${fieldVal('FirstName') || ''} ${fieldVal('LastName') || ''}`.trim() || id;

    const subtitleParts = [];
    if (fieldDisp('CreatedDate')) subtitleParts.push(`Created ${fieldDisp('CreatedDate')}`);
    if (fieldDisp('LastModifiedDate')) subtitleParts.push(`Updated ${fieldDisp('LastModifiedDate')}`);
    el('record-subtitle').textContent = subtitleParts.length ? subtitleParts.join(' · ') : '—';

    renderGroups(uiGroups.groups, '');
    el('record-raw').textContent = JSON.stringify(record.fields, null, 2);

    showError('');
    setVisible('record-result', true);
}

// Render UI API layout as SLDS-style section cards with a two-column field grid.
function renderGroups(groups, filter) {
    const host = el('record-sections');
    setVisible('record-table-wrap', false);
    setVisible('record-sections', true);
    host.innerHTML = '';
    const q = String(filter || '').trim().toLowerCase();
    let count = 0;

    for (const group of groups) {
        const matching = group.items.filter((it) =>
            !q || it.label.toLowerCase().includes(q) || it.apiName.toLowerCase().includes(q)
        );
        if (!matching.length) continue;

        const card = document.createElement('section');
        card.className = 'record-card';

        if (group.heading) {
            const head = document.createElement('div');
            head.className = 'record-card-head';
            head.textContent = group.heading;
            card.appendChild(head);
        }

        const grid = document.createElement('div');
        grid.className = 'record-card-grid';

        for (const it of matching) {
            const item = document.createElement('div');
            item.className = 'record-item';

            const label = document.createElement('div');
            label.className = 'record-item-label';
            label.textContent = it.label;
            label.title = it.apiName;
            item.appendChild(label);

            const value = document.createElement('div');
            value.className = 'record-item-value';
            const formatted = formatUiValue(it.dataType, it.cell);
            if (formatted instanceof Node) value.appendChild(formatted);
            else value.textContent = formatted;
            item.appendChild(value);

            grid.appendChild(item);
            count += 1;
        }

        card.appendChild(grid);
        host.appendChild(card);
    }

    if (count === 0) {
        const empty = document.createElement('div');
        empty.className = 'record-empty record-card';
        empty.textContent = q ? 'No fields match the filter.' : 'No fields on this layout.';
        host.appendChild(empty);
    }
}

function renderTable(fieldInfo, record, describe, filter) {
    const tbody = el('record-tbody');
    tbody.innerHTML = '';
    const q = String(filter || '').trim().toLowerCase();

    let count = 0;
    for (const f of describe.fields || []) {
        if (!Object.prototype.hasOwnProperty.call(record, f.name)) continue;
        const value = record[f.name];
        const label = String(f.label || f.name);
        if (q && !label.toLowerCase().includes(q) && !f.name.toLowerCase().includes(q)) continue;
        if (String(value).toLowerCase().includes(q) || label.toLowerCase().includes(q)) { /* keep */ }

        const tr = document.createElement('tr');
        tr.className = 'record-row';

        const tdLabel = document.createElement('td');
        tdLabel.className = 'record-cell record-cell-label';
        const labelStrong = document.createElement('span');
        labelStrong.textContent = label;
        tdLabel.appendChild(labelStrong);
        const apiName = document.createElement('span');
        apiName.className = 'record-api-name';
        apiName.textContent = f.name;
        tdLabel.appendChild(apiName);
        tr.appendChild(tdLabel);

        const tdValue = document.createElement('td');
        tdValue.className = 'record-cell record-cell-value';
        const formatted = formatValue(fieldInfo[f.name.toLowerCase()], value);
        if (formatted instanceof Node) {
            tdValue.appendChild(formatted);
        } else {
            tdValue.textContent = formatted;
        }
        tr.appendChild(tdValue);

        tbody.appendChild(tr);
        count += 1;
    }

    if (count === 0) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = 2;
        td.className = 'record-empty';
        td.textContent = q ? 'No fields match the filter.' : 'No fields returned for this record.';
        tr.appendChild(td);
        tbody.appendChild(tr);
    }
}

async function loadRecord(recordId, objectName) {
    const id = String(recordId || '').trim();
    if (!id) {
        showError('Enter a record ID.');
        setVisible('record-result', false);
        return;
    }

    if (!/^[a-zA-Z0-9]{15,18}$/.test(id)) {
        showError('That does not look like a Salesforce record ID.');
        setVisible('record-result', false);
        return;
    }

    let object = String(objectName || '').trim();
    if (!object) {
        showLoading(true);
        showError('');
        setVisible('record-result', false);
        try {
            object = await resolveObject(id);
        } catch (err) {
            showLoading(false);
            showError(err?.message || 'Unable to detect the object for this ID.');
            return;
        }
        if (!object) {
            showLoading(false);
            showError('Could not auto-detect the object for this record ID. Enter the object API name (e.g. Account) manually.');
            return;
        }
    }

    showLoading(true);
    showError('');
    const cacheKey = recordCacheKey(object, id);
    const uiCacheKey = recordUiCacheKey(object, id);
    const cached = readCache(cacheKey);
    const cachedUi = readCache(uiCacheKey);

    // Prefer the cached page-layout view while the network request runs.
    if (cachedUi && cachedUi.payload) {
        try {
            const groups = extractLayoutGroups(cachedUi.payload, id);
            if (groups) renderRecordFromUi(groups, id);
        } catch (_e) { /* fall through */ }
    } else if (cached && cached.payload && cached.payload.record) {
        try {
            const cachedDesc = readCache(describeCacheKey(object));
            renderRecord(
                cached.payload.record,
                object,
                cachedDesc && cachedDesc.payload ? cachedDesc.payload : { label: object, fields: [] }
            );
        } catch (_renderErr) { /* fall through to network */ }
    }

    // Primary path: UI API page layout (order/sections mirror Salesforce).
    try {
        const recordUi = await getRecordUi(id);
        const groups = extractLayoutGroups(recordUi, id);
        if (!groups) throw new Error('No page layout returned for this record.');
        writeCache(uiCacheKey, recordUi);
        renderRecordFromUi(groups, id);
        showError('');
        return;
    } catch (layoutErr) {
        // Fallback: raw sObject describe dump (all accessible fields).
        try {
            const [record, describe] = await Promise.all([
                sfFetch(`/sobjects/${encodeURIComponent(object)}/${encodeURIComponent(id)}`),
                getDescribe(object)
            ]);
            writeCache(cacheKey, { record, object });
            renderRecord(record, object, describe);
            showError('');
        } catch (err) {
            if (cachedUi?.payload || (cached && cached.payload && cached.payload.record)) {
                showError(`Showing cached copy — ${err?.message || 'network unavailable.'}`);
            } else {
                showError(err?.message || layoutErr?.message || 'Unable to load the record.');
            }
        }
    } finally {
        showLoading(false);
    }
}

function setupFilter() {
    const filter = el('record-filter');
    if (!filter) return;
    filter.addEventListener('input', () => {
        if (currentMode === 'layout' && currentGroups) {
            renderGroups(currentGroups, filter.value);
        } else if (currentRecord && currentDescribe) {
            renderTable(buildFieldInfo(currentDescribe), currentRecord, currentDescribe, filter.value);
        }
    });
}

function setupRawToggle() {
    const btn = el('btn-raw');
    if (!btn) return;
    btn.addEventListener('click', () => {
        const raw = el('record-raw');
        if (!raw) return;
        const showing = raw.style.display !== 'none';
        raw.style.display = showing ? 'none' : 'block';
        btn.textContent = showing ? 'Show raw JSON' : 'Hide raw JSON';
    });
}

function setupForm() {
    const form = el('record-form');
    const idInput = el('record-id');
    const objectInput = el('record-object');
    if (!form || !idInput) return;
    form.addEventListener('submit', (event) => {
        event.preventDefault();
        loadRecord(idInput.value, objectInput.value);
    });
}

function setupQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const version = params.get('apiVersion');
    if (version && /^v\d+\.\d+$/.test(version)) {
        apiVersion = version;
        const versionBadge = el('record-version');
        if (versionBadge) versionBadge.textContent = version;
    }
    const recordId = params.get('recordId');
    const object = params.get('object');
    if (recordId) {
        const idInput = el('record-id');
        const objectInput = el('record-object');
        if (idInput) idInput.value = recordId;
        if (objectInput && object) objectInput.value = object;
        loadRecord(recordId, object);
    }
}

function init() {
    const backBtn = el('btn-back');
    if (backBtn) {
        backBtn.addEventListener('click', () => { window.location.href = '/'; });
    }
    setupForm();
    setupFilter();
    setupRawToggle();
    setupQueryParams();
}

document.addEventListener('DOMContentLoaded', init);