const DB_NAME = 'pharmaClmOffline';
const DB_VERSION = 5;

const STORES = {
    manifest: { name: 'manifest', keyPath: 'presentationId' },
    assets: { name: 'assets', keyPath: 'assetKey' },
    presentationList: { name: 'presentationList', keyPath: 'userKey' },
    localSessions: { name: 'localSessions', keyPath: 'clientSessionKey' },
    actionQueue: { name: 'actionQueue', keyPath: 'id', autoIncrement: true },
    ratingContext: { name: 'ratingContext', keyPath: 'visitId' },
    visitPayloads: { name: 'visitPayloads', keyPath: 'visitId' },
    todayPlan: { name: 'todayPlan', keyPath: 'userKey' },
    meta: { name: 'meta', keyPath: 'key' },
    plannerCache: { name: 'plannerCache', keyPath: 'userKey' },
    homeMetrics: { name: 'homeMetrics', keyPath: 'userKey' },
    coachingContext: { name: 'coachingContext', keyPath: 'visitId' },
    clientKeyMap: { name: 'clientKeyMap', keyPath: 'clientKey' },
    accounts: { name: 'accounts', keyPath: 'id' },
    mapAccounts: { name: 'mapAccounts', keyPath: 'userKey' },
    accountsTab: { name: 'accountsTab', keyPath: 'key' }
};

let dbPromise = null;

function openDatabase() {
    if (dbPromise) {
        return dbPromise;
    }
    dbPromise = new Promise((resolve, reject) => {
        if (!window.indexedDB) {
            reject(new Error('IndexedDB is not available.'));
            return;
        }
        const request = window.indexedDB.open(DB_NAME, DB_VERSION);
        request.onupgradeneeded = () => {
            const db = request.result;
            Object.values(STORES).forEach((store) => {
                if (!db.objectStoreNames.contains(store.name)) {
                    const options = store.autoIncrement
                        ? { keyPath: store.keyPath, autoIncrement: true }
                        : { keyPath: store.keyPath };
                    db.createObjectStore(store.name, options);
                }
            });
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || new Error('Unable to open offline store.'));
    });
    return dbPromise;
}

function isIdbRequest(value) {
    return value != null && typeof value === 'object' && 'readyState' in value && 'result' in value;
}

function toArray(value) {
    return Array.isArray(value) ? value : [];
}

function toPlainData(value) {
    if (value == null) {
        return value;
    }
    try {
        return JSON.parse(JSON.stringify(value));
    } catch (_error) {
        return value;
    }
}

async function withStore(storeName, mode, callback) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
        const transaction = db.transaction(storeName, mode);
        const store = transaction.objectStore(storeName);
        let result;
        try {
            result = callback(store);
        } catch (error) {
            reject(error);
            return;
        }
        if (isIdbRequest(result)) {
            result.onsuccess = () => resolve(result.result);
            result.onerror = () => reject(result.error || new Error('IndexedDB request failed.'));
            return;
        }
        transaction.oncomplete = () => resolve(result);
        transaction.onerror = () => reject(transaction.error);
        transaction.onabort = () => reject(transaction.error || new Error('Transaction aborted.'));
    });
}

export async function putManifestEntry(entry) {
    return withStore(STORES.manifest.name, 'readwrite', (store) =>
        store.put({ ...entry, presentationId: entry.presentationId || entry.id })
    );
}

export async function getManifestEntry(presentationId) {
    return withStore(STORES.manifest.name, 'readonly', (store) => store.get(presentationId));
}

export async function getAllManifestEntries() {
    return withStore(STORES.manifest.name, 'readonly', (store) => {
        const request = store.getAll();
        return request;
    });
}

export async function putPresentationList(userKey, presentations, syncedAt = new Date().toISOString()) {
    return withStore(STORES.presentationList.name, 'readwrite', (store) =>
        store.put({ userKey, presentations, syncedAt })
    );
}

export async function getPresentationList(userKey) {
    return withStore(STORES.presentationList.name, 'readonly', (store) => store.get(userKey));
}

function cloneForStorage(blob) {
    if (blob instanceof ArrayBuffer) {
        return blob.slice(0);
    }
    if (ArrayBuffer.isView(blob)) {
        return blob.slice().buffer;
    }
    return blob;
}

export async function putAsset(assetKey, blob, metadata = {}) {
    const stored = cloneForStorage(blob);
    return withStore(STORES.assets.name, 'readwrite', (store) =>
        store.put({
            assetKey,
            blob: stored,
            cachedAt: new Date().toISOString(),
            size: stored?.size || stored?.byteLength || 0,
            ...metadata
        })
    );
}

export async function getAsset(assetKey) {
    const row = await withStore(STORES.assets.name, 'readonly', (store) => store.get(assetKey));
    return row || null;
}

export async function putLocalSession(session) {
    return withStore(STORES.localSessions.name, 'readwrite', (store) => store.put(session));
}

export async function getLocalSession(clientSessionKey) {
    return withStore(STORES.localSessions.name, 'readonly', (store) => store.get(clientSessionKey));
}

export async function updateLocalSession(clientSessionKey, patch) {
    const existing = await getLocalSession(clientSessionKey);
    if (!existing) {
        return null;
    }
    const updated = { ...existing, ...patch };
    await putLocalSession(updated);
    return updated;
}

export async function enqueueAction(action) {
    return withStore(STORES.actionQueue.name, 'readwrite', (store) =>
        store.add({
            ...action,
            status: action.status || 'pending',
            retries: action.retries || 0,
            createdAt: action.createdAt || new Date().toISOString()
        })
    );
}

export async function getPendingActions() {
    const rows = await withStore(STORES.actionQueue.name, 'readonly', (store) => store.getAll());
    return toArray(rows)
        .filter((row) => row.status === 'pending' || row.status === 'failed')
        .sort((a, b) => (a.id || 0) - (b.id || 0));
}

export async function countPendingActions() {
    const pending = await getPendingActions();
    return pending.length;
}

export async function updateAction(id, patch) {
    const row = await withStore(STORES.actionQueue.name, 'readonly', (store) => store.get(id));
    if (!row) {
        return null;
    }
    const updated = { ...row, ...patch };
    await withStore(STORES.actionQueue.name, 'readwrite', (store) => store.put(updated));
    return updated;
}

export async function removeAction(id) {
    return withStore(STORES.actionQueue.name, 'readwrite', (store) => store.delete(id));
}

export async function putRatingContext(visitId, context) {
    return withStore(STORES.ratingContext.name, 'readwrite', (store) =>
        store.put({ visitId, context, cachedAt: new Date().toISOString() })
    );
}

export async function getRatingContext(visitId) {
    const row = await withStore(STORES.ratingContext.name, 'readonly', (store) => store.get(visitId));
    return row?.context || null;
}

export async function putMeta(key, value) {
    return withStore(STORES.meta.name, 'readwrite', (store) => store.put({ key, value }));
}

export async function getMeta(key) {
    const row = await withStore(STORES.meta.name, 'readonly', (store) => store.get(key));
    return row?.value ?? null;
}

export function hashUrl(url) {
    let hash = 0;
    const value = String(url || '');
    for (let i = 0; i < value.length; i += 1) {
        hash = (hash << 5) - hash + value.charCodeAt(i);
        hash |= 0;
    }
    return `url_${Math.abs(hash)}`;
}

export function getUserPresentationListKey(userId) {
    return `presentations_${userId || 'anonymous'}`;
}

export function getUserTodayPlanKey(userId) {
    return `todayPlan_${userId || 'anonymous'}`;
}

export function getUserPlannerCacheKey(userId) {
    return `planner_${userId || 'anonymous'}`;
}

export function getUserHomeMetricsKey(userId) {
    return `homeMetrics_${userId || 'anonymous'}`;
}

export function getUserNbcKey(userId) {
    return `nbc_${userId || 'anonymous'}`;
}

export async function putVisitPayload(visitId, payload) {
    return withStore(STORES.visitPayloads.name, 'readwrite', (store) =>
        store.put({ visitId, payload, cachedAt: new Date().toISOString() })
    );
}

export async function getVisitPayload(visitId) {
    const row = await withStore(STORES.visitPayloads.name, 'readonly', (store) => store.get(visitId));
    return row?.payload || null;
}

export async function putTodayPlan(userKey, visits) {
    return withStore(STORES.todayPlan.name, 'readwrite', (store) =>
        store.put({ userKey, visits: toPlainData(visits), cachedAt: new Date().toISOString() })
    );
}

export async function getTodayPlan(userKey) {
    const row = await withStore(STORES.todayPlan.name, 'readonly', (store) => store.get(userKey));
    return row?.visits || null;
}

export async function putPlannerCache(userKey, payload) {
    return withStore(STORES.plannerCache.name, 'readwrite', (store) =>
        store.put({ userKey, payload: toPlainData(payload), cachedAt: new Date().toISOString() })
    );
}

export async function getPlannerCache(userKey) {
    const row = await withStore(STORES.plannerCache.name, 'readonly', (store) => store.get(userKey));
    return row?.payload || null;
}

export async function putHomeMetrics(userKey, metrics) {
    const plain = toPlainData(metrics);
    return withStore(STORES.homeMetrics.name, 'readwrite', (store) =>
        store.put({ userKey, metrics: plain, cachedAt: new Date().toISOString() })
    );
}

export async function getHomeMetricsCache(userKey) {
    const row = await withStore(STORES.homeMetrics.name, 'readonly', (store) => store.get(userKey));
    return row?.metrics || null;
}

export async function putCoachingContext(visitId, context) {
    return withStore(STORES.coachingContext.name, 'readwrite', (store) =>
        store.put({ visitId, context, cachedAt: new Date().toISOString() })
    );
}

export async function getCoachingContext(visitId) {
    const row = await withStore(STORES.coachingContext.name, 'readonly', (store) => store.get(visitId));
    return row?.context || null;
}

export async function putClientKeyMapping(clientKey, mapping) {
    return withStore(STORES.clientKeyMap.name, 'readwrite', (store) =>
        store.put({
            clientKey,
            ...mapping,
            updatedAt: new Date().toISOString()
        })
    );
}

export async function getClientKeyMapping(clientKey) {
    return withStore(STORES.clientKeyMap.name, 'readonly', (store) => store.get(clientKey));
}

export function newClientKey(prefix) {
    const rand =
        typeof crypto !== 'undefined' && crypto.randomUUID
            ? crypto.randomUUID()
            : `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return `${prefix || 'key'}_${rand}`;
}

export async function putCachedAccounts(accountList) {
    if (!accountList || !accountList.length) {
        return;
    }
    const plain = toPlainData(accountList);
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
        const tx = db.transaction(STORES.accounts.name, 'readwrite');
        const store = tx.objectStore(STORES.accounts.name);
        plain.forEach((account) => {
            if (account && account.id) {
                store.put(account);
            }
        });
        tx.oncomplete = () => {
            console.log(`[OfflineStore] Cached ${plain.length} account(s) in IndexedDB.`);
            resolve();
        };
        tx.onerror = () => reject(tx.error);
    });
}

export async function getCachedAccount(accountId) {
    if (!accountId) {
        return null;
    }
    return withStore(STORES.accounts.name, 'readonly', (store) => store.get(accountId));
}

export async function getAllCachedAccounts() {
    const rows = await withStore(STORES.accounts.name, 'readonly', (store) => store.getAll());
    return toArray(rows);
}

export async function searchCachedAccounts({
    searchTerm,
    recordTypeDeveloperName,
    specialty,
    classification,
    brickId,
    offset = 0,
    pageSize = 10
} = {}) {
    const all = await getAllCachedAccounts();
    const term = (searchTerm || '').trim().toLowerCase();

    const filtered = all.filter((acc) => {
        if (!acc) {
            return false;
        }
        if (term) {
            const name = (acc.name || '').toLowerCase();
            const street = (acc.street || '').toLowerCase();
            const city = (acc.city || '').toLowerCase();
            const spec = (acc.specialty || '').toLowerCase();
            if (!name.includes(term) && !street.includes(term) && !city.includes(term) && !spec.includes(term)) {
                return false;
            }
        }
        if (recordTypeDeveloperName && recordTypeDeveloperName !== 'All') {
            if (acc.recordTypeDeveloperName !== recordTypeDeveloperName && acc.recordTypeName !== recordTypeDeveloperName) {
                return false;
            }
        }
        if (specialty && specialty !== 'All') {
            if (acc.specialty !== specialty && acc.specialtyApiValue !== specialty) {
                return false;
            }
        }
        if (classification && classification !== 'All') {
            if (acc.classification !== classification) {
                return false;
            }
        }
        if (brickId && brickId !== 'All') {
            if (acc.brickId !== brickId && acc.brickName !== brickId) {
                return false;
            }
        }
        return true;
    });

    const page = filtered.slice(offset, offset + pageSize);
    return {
        accounts: page,
        totalCount: filtered.length,
        hasMore: offset + pageSize < filtered.length
    };
}

export function getUserMapAccountsKey(userId) {
    return `mapAccounts_${userId || 'anonymous'}`;
}

export async function putMapAccountsCache(userKey, accounts) {
    const plain = toPlainData(accounts);
    return withStore(STORES.mapAccounts.name, 'readwrite', (store) =>
        store.put({ userKey, accounts: plain, cachedAt: new Date().toISOString() })
    );
}

export async function getMapAccountsCache(userKey) {
    const row = await withStore(STORES.mapAccounts.name, 'readonly', (store) => store.get(userKey));
    return row?.accounts || null;
}

export function getUserAccountsTabKey(userId) {
    return `accountsTab_${userId || 'anonymous'}`;
}

export async function putAccountsTabCache(key, value) {
    const plain = toPlainData(value);
    return withStore(STORES.accountsTab.name, 'readwrite', (store) =>
        store.put({ key, value: plain, cachedAt: new Date().toISOString() })
    );
}

export async function getAccountsTabCache(key) {
    const row = await withStore(STORES.accountsTab.name, 'readonly', (store) => store.get(key));
    return row?.value || null;
}

export async function putAccountsTabBusinessUnits(userId, byAccount) {
    return putAccountsTabCache(`${getUserAccountsTabKey(userId)}.businessUnits`, byAccount);
}

export async function getAccountsTabBusinessUnits(userId) {
    const cached = await getAccountsTabCache(`${getUserAccountsTabKey(userId)}.businessUnits`);
    return cached && typeof cached === 'object' ? cached : {};
}

export async function putAccountsTabRecordTypeOptionsCache(userId, options) {
    return putAccountsTabCache(`${getUserAccountsTabKey(userId)}.options`, options);
}

export async function getAccountsTabRecordTypeOptionsCache(userId) {
    const cached = await getAccountsTabCache(`${getUserAccountsTabKey(userId)}.options`);
    return Array.isArray(cached) ? cached : null;
}