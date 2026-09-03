import { LightningElement, track } from 'lwc';
import getNextBestCustomersPayload from '@salesforce/apex/PlannerMobileRestService.getNextBestCustomersPayload';
import upsertVisit from '@salesforce/apex/FieldPlannerController.upsertVisit';
import {
    getHomeMetricsCache,
    getUserNbcKey,
    newClientKey,
    putCachedAccounts,
    putHomeMetrics
} from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

const NBC_PATH = '/services/apexrest/planner/v1/home/next-best-customers';
const VISITS_UPSERT_PATH = '/services/apexrest/planner/v1/visits/upsert';
const CACHE_USER_FALLBACK = 'me';
const NBC_LIMIT = 5;

const RANK_META = [
    { glyph: '🥇', iconClass: 'rank-icon rank-icon--first', label: '1st place' },
    { glyph: '🥈', iconClass: 'rank-icon rank-icon--second', label: '2nd place' },
    { glyph: '🥉', iconClass: 'rank-icon rank-icon--third', label: '3rd place' },
    { glyph: '4️⃣', iconClass: 'rank-icon rank-icon--fourth', label: '4th place' },
    { glyph: '5️⃣', iconClass: 'rank-icon rank-icon--fifth', label: '5th place' }
];

const DAY_START_HOUR = 6;
const DAY_END_HOUR = 20;
const SLOT_MINUTES = 30;

function plannerRestBase() {
    return typeof globalThis !== 'undefined' ? globalThis.PLANNER_REST_BASE || '' : '';
}

function ceilToNextSlot(date) {
    const d = new Date(date);
    const minutes = d.getMinutes();
    const add = minutes % SLOT_MINUTES === 0 ? SLOT_MINUTES : SLOT_MINUTES - (minutes % SLOT_MINUTES);
    d.setMinutes(minutes + add);
    d.setSeconds(0, 0);
    return d;
}

function clampToWorkingHours(date) {
    const d = new Date(date);
    if (d.getHours() < DAY_START_HOUR) {
        d.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    if (d.getHours() >= DAY_END_HOUR) {
        d.setDate(d.getDate() + 1);
        d.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    return d;
}

export default class FieldRepHomeNextBestCustomer extends LightningElement {
    @track rows = [];
    @track syncStatus = 'idle';
    @track errorMessage = '';
    @track noticeMessage = '';
    @track noticeVariant = 'success';
    @track hasCachedData = false;

    cacheUserKey = CACHE_USER_FALLBACK;
    refreshAbort;
    _connectivityBound = false;

    connectedCallback() {
        this.init();
    }

    disconnectedCallback() {
        if (this.refreshAbort) {
            this.refreshAbort.abort();
            this.refreshAbort = null;
        }
        if (this._onOnline) {
            window.removeEventListener('online', this._onOnline);
        }
        if (this._onOffline) {
            window.removeEventListener('offline', this._onOffline);
        }
        if (this._noticeTimer) {
            clearTimeout(this._noticeTimer);
        }
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    get showSyncChip() {
        return this.syncStatus === 'cached' || this.syncStatus === 'updating' || this.syncStatus === 'offline';
    }

    get syncChipLabel() {
        if (this.syncStatus === 'updating') {
            return 'Updating…';
        }
        if (this.syncStatus === 'offline') {
            return 'Offline';
        }
        if (this.syncStatus === 'cached') {
            return 'Cached';
        }
        return '';
    }

    get syncChipClass() {
        return `sync-chip sync-chip-${this.syncStatus}`;
    }

    get showErrorBanner() {
        return Boolean(this.errorMessage);
    }

    get noticeClass() {
        return `notice-banner notice-${this.noticeVariant || 'success'}`;
    }

    bindConnectivityListeners() {
        if (this._connectivityBound || typeof window === 'undefined') {
            return;
        }
        this._connectivityBound = true;
        this._onOnline = () => {
            this.init();
        };
        this._onOffline = () => {
            // Abort in-flight requests but don't immediately show offline
            // The API call failure in catch block will handle real network failures
            if (this.refreshAbort) {
                this.refreshAbort.abort();
            }
        };
        window.addEventListener('online', this._onOnline);
        window.addEventListener('offline', this._onOffline);
    }

    async init() {
        this.bindConnectivityListeners();
        this.errorMessage = '';
        const cached = await this.readCache();
        if (cached) {
            this.applyCachedBundle(cached);
            this.hasCachedData = true;
            this.syncStatus = 'cached';
        } else {
            this.hasCachedData = false;
        }

        // Note: navigator.onLine is unreliable in Capacitor WebView
        // Always try the API call - catch block handles real network failures
        this.syncStatus = 'updating';
        try {
            const payload = await this.fetchNbcPayload();
            this.applyPayload(payload);
            this.cacheUserKey = payload?.userId || CACHE_USER_FALLBACK;
            await this.writeCache();
            this.hasCachedData = true;
            this.errorMessage = '';
            this.syncStatus = 'idle';
        } catch (error) {
            if (error?.name === 'AbortError') {
                return;
            }
            this.syncStatus = 'offline';
            if (!this.hasCachedData) {
                this.errorMessage = this.isConnectivityError(error)
                    ? 'You are offline. Connect to load next best customers.'
                    : this.reduceError(error) || 'Unable to load next best customers.';
            }
        }
    }

    decorateRows(rows) {
        return (rows || []).map((row, index) => {
            const rankMeta = RANK_META[Math.min(index, RANK_META.length - 1)];
            return {
                ...row,
                callPlanLabel: `${Math.round(row.actualVisits || 0)}/${Math.round(row.targetVisits || 0)}`,
                plannedLabel: row.planned ? 'Yes' : 'No',
                scoreDisplay: Math.round(row.score || 0),
                rankGlyph: rankMeta.glyph,
                rankIconClass: rankMeta.iconClass,
                rankLabel: rankMeta.label
            };
        });
    }

    applyPayload(payload) {
        this.rows = this.decorateRows(payload?.rows || []);
        const nbcAccounts = (payload?.rows || [])
            .filter((r) => r.accountId)
            .map((r) => ({
                id: r.accountId,
                name: r.accountName,
                specialty: r.specialty,
                actualVisits: r.actualVisits,
                targetVisits: r.targetVisits
            }));
        if (nbcAccounts.length) {
            void putCachedAccounts(nbcAccounts);
        }
    }

    applyCachedBundle(cached) {
        const source = Array.isArray(cached) ? cached : cached?.rows || cached?.nbcRows || [];
        this.rows = this.decorateRows(source);
    }

    async readCache() {
        const primary = await getHomeMetricsCache(getUserNbcKey(this.cacheUserKey));
        if (primary) {
            return primary;
        }
        if (this.cacheUserKey !== CACHE_USER_FALLBACK) {
            return getHomeMetricsCache(getUserNbcKey(CACHE_USER_FALLBACK));
        }
        return null;
    }

    async writeCache() {
        const bundle = { rows: this.rows };
        await putHomeMetrics(getUserNbcKey(this.cacheUserKey), bundle);
        if (this.cacheUserKey !== CACHE_USER_FALLBACK) {
            await putHomeMetrics(getUserNbcKey(CACHE_USER_FALLBACK), bundle);
        }
    }

    async fetchNbcPayload() {
        const restBase = plannerRestBase();
        if (restBase) {
            return this.fetchNbcRest(restBase);
        }
        return getNextBestCustomersPayload({ contextUserId: null, limitSize: NBC_LIMIT });
    }

    async fetchNbcRest(restBase) {
        const params = new URLSearchParams();
        params.set('limitSize', String(NBC_LIMIT));
        return this.plannerFetch(`${NBC_PATH}?${params.toString()}`, { method: 'GET' }, restBase);
    }

    async plannerFetch(path, options, restBase = plannerRestBase()) {
        const token = typeof globalThis !== 'undefined' ? globalThis.PLANNER_ACCESS_TOKEN : '';
        const headers = { Accept: 'application/json', ...(options.headers || {}) };
        if (token) {
            headers.Authorization = `Bearer ${token}`;
        }
        if (options.body && !headers['Content-Type']) {
            headers['Content-Type'] = 'application/json';
        }
        if (this.refreshAbort && options.method === 'GET') {
            this.refreshAbort.abort();
        }
        if (options.method === 'GET') {
            this.refreshAbort = typeof AbortController !== 'undefined' ? new AbortController() : null;
        }
        let response;
        try {
            response = await fetch(`${String(restBase).replace(/\/$/, '')}${path}`, {
                method: options.method || 'GET',
                credentials: token ? 'omit' : 'same-origin',
                headers,
                body: options.body,
                signal: options.method === 'GET' && this.refreshAbort ? this.refreshAbort.signal : undefined
            });
        } catch (fetchError) {
            // Network error (TypeError, etc.) - manual mode, no auto-detection
            console.warn('[NextBestCustomer] Network error detected:', fetchError.message);
            const offlineError = new Error('Offline');
            offlineError.name = 'OfflineError';
            throw offlineError;
        }
        // Manual mode - no auto-detection of online status
        if (!response.ok) {
            if (response.status >= 500) {
                const offlineError = new Error('Offline');
                offlineError.name = 'OfflineError';
                throw offlineError;
            }
            let detail = `HTTP ${response.status}`;
            try {
                const failed = await response.json();
                detail = failed?.message || detail;
            } catch (_parseError) {
                // Keep the HTTP status message when the body is not JSON.
            }
            throw new Error(detail);
        }
        if (response.status === 204) {
            return null;
        }
        return response.json();
    }

    isConnectivityError(error) {
        const name = error?.name || '';
        if (name === 'AbortError' || name === 'TypeError' || name === 'OfflineError') {
            return true;
        }
        const message = error?.message || '';
        return /offline|failed to fetch|networkerror|load failed/i.test(message);
    }

    handleOpenAccount(event) {
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }
        this.openSalesforceRecord('Account', accountId);
    }

    async handleCall(event) {
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }

        try {
            const start = clampToWorkingHours(ceilToNextSlot(new Date()));
            const end = new Date(start.getTime() + 60 * 60000);
            const payload = {
                accountId,
                startDateTime: start.toISOString(),
                endDateTime: end.toISOString(),
                status: 'Draft',
                visitType: 'Planned (Automatically)'
            };

            if (isOfflineMode()) {
                const clientVisitKey = newClientKey('visit');
                console.log('[NextBestCustomer] [Offline Plan Call] Enqueueing draft visit for account:', accountId, clientVisitKey);
                await queueOfflineAction({
                    actionType: 'UPSERT_VISIT',
                    clientVisitKey,
                    clientActionKey: clientVisitKey,
                    payloadJson: JSON.stringify(payload)
                });
                console.log('[NextBestCustomer] [Offline Plan Call] Enqueued successfully.');
                this.showToast('Queued offline', 'Draft visit will be created when you are back online.', 'success');
                return;
            }

            const created = await this.upsertVisitRemote(payload);
            this.showToast('Draft created', 'Opening draft call for your next best customer.', 'success');
            if (created?.id) {
                this.openSalesforceRecord('Visit__c', created.id);
            }
        } catch (e) {
            this.showToast('Error', this.reduceError(e) || 'Unable to create a draft visit.', 'error');
        }
    }

    async upsertVisitRemote(payload) {
        const restBase = plannerRestBase();
        if (restBase) {
            return this.plannerFetch(VISITS_UPSERT_PATH, {
                method: 'POST',
                body: JSON.stringify({
                    visitId: null,
                    accountId: payload.accountId,
                    startDateTime: payload.startDateTime,
                    endDateTime: payload.endDateTime,
                    status: payload.status,
                    visitType: payload.visitType,
                    cancellationReason: null
                })
            });
        }
        return upsertVisit({
            visitId: null,
            accountId: payload.accountId,
            startDateTime: payload.startDateTime,
            endDateTime: payload.endDateTime,
            status: payload.status,
            visitType: payload.visitType,
            cancellationReason: null
        });
    }

    openSalesforceRecord(objectApiName, recordId) {
        const instanceUrl = typeof globalThis !== 'undefined' ? globalThis.PLANNER_SF_INSTANCE || '' : '';
        const path = `/lightning/r/${objectApiName}/${recordId}/view`;
        if (instanceUrl && plannerRestBase()) {
            window.open(`${String(instanceUrl).replace(/\/$/, '')}${path}`, '_blank');
            return;
        }
        window.open(path, '_self');
    }

    showToast(title, message, variant) {
        this.noticeVariant = variant === 'error' || variant === 'warning' ? variant : 'success';
        this.noticeMessage = [title, message].filter(Boolean).join(' — ');
        if (this._noticeTimer) {
            clearTimeout(this._noticeTimer);
        }
        this._noticeTimer = setTimeout(() => {
            this.noticeMessage = '';
        }, 4000);
    }

    reduceError(error) {
        if (!error) {
            return null;
        }
        if (typeof error === 'string') {
            return error;
        }
        return error?.body?.message || error?.message || null;
    }
}
