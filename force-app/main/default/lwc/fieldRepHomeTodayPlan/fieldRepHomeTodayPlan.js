import { LightningElement, track } from 'lwc';
import getTodayPlanPayload from '@salesforce/apex/PlannerMobileRestService.getTodayPlanPayload';
import deleteVisit from '@salesforce/apex/FieldPlannerController.deleteVisit';
import rescheduleVisits from '@salesforce/apex/FieldPlannerController.rescheduleVisits';
import getCallReportPayload from '@salesforce/apex/VisitCallReportController.getCallReportPayload';
import getRatingCaptureContext from '@salesforce/apex/ClmMetricsController.getRatingCaptureContext';
import getCoachingFormContext from '@salesforce/apex/VisitCoachingController.getCoachingFormContext';
import { detectRouteOutliers, formatDistantStopsSummary, normalizeSalesforceId } from 'c/plannerRouteUtils';
import {
    getTodayPlan,
    getUserTodayPlanKey,
    newClientKey,
    putCachedAccounts,
    putCoachingContext,
    putRatingContext,
    putTodayPlan,
    putVisitPayload
} from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

const TODAY_PLAN_PATH = '/services/apexrest/planner/v1/home/today-plan';
const VISITS_RESCHEDULE_PATH = '/services/apexrest/planner/v1/visits/reschedule';
const VISITS_DELETE_PATH = '/services/apexrest/planner/v1/visits/delete';
const CACHE_USER_FALLBACK = 'me';
const LEAFLET_CDN = 'https://unpkg.com/leaflet@1.9.4/dist';

const OSRM_BASE = 'https://router.project-osrm.org';
const DEFAULT_MAP_CENTER = [30.0444, 31.2357];
const DEFAULT_MAP_ZOOM = 12;
const PLANNER_TAB_API = 'Field_Rep_Planner';
const GOOGLE_MAPS_MAX_STOPS_WITH_ORIGIN = 10;
const GOOGLE_MAPS_MAX_STOPS_WITHOUT_ORIGIN = 11;

const HCP_RECORD_TYPES = new Set([
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
]);

const HCO_RECORD_TYPES = new Set(['Institution_HCO', 'Pharmacy']);

const HCP_PIN_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 12c2.2 0 4-1.8 4-4s-1.8-4-4-4-4 1.8-4 4 1.8 4 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z"/></svg>';

const HCO_PIN_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 7V3H2v18h20V7H12zm-2 12H6v-2h4v2zm0-4H6v-2h4v2zm0-4H6V9h4v2zm0-4H6V5h4v2zm6 12h-4v-2h4v2zm0-4h-4v-2h4v2zm0-4h-4V9h4v2zm0-4h-4V5h4v2zm8 12h-6v-2h2v-2h-2v-2h2v-2h-2V9h6v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>';

function parseSalesforceDateTime(value) {
    if (!value) {
        return null;
    }
    return new Date(value);
}

function toDateKey(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function toApexDate(date) {
    return toDateKey(date);
}

function toApexDateTime(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) {
        return null;
    }
    return date.toISOString();
}

function sameSalesforceId(left, right) {
    if (!left || !right) {
        return left === right;
    }
    return String(left).substring(0, 15) === String(right).substring(0, 15);
}

function formatTime(date) {
    if (!date) {
        return '';
    }
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function buildCoordPath(points) {
    return points.map((point) => `${point.longitude},${point.latitude}`).join(';');
}

function resolveAccountPinKind(recordTypeDeveloperName, recordTypeName) {
    const developerName = recordTypeDeveloperName || '';
    if (HCP_RECORD_TYPES.has(developerName)) {
        return 'hcp';
    }
    if (HCO_RECORD_TYPES.has(developerName)) {
        return 'hco';
    }
    const label = (recordTypeName || '').toLowerCase();
    if (label.includes('hcp') || label.includes('professional') || label.includes('person')) {
        return 'hcp';
    }
    if (label.includes('hco') || label.includes('institution') || label.includes('pharmacy')) {
        return 'hco';
    }
    return 'hcp';
}

function resolveAccountTypeLabel(pinKind, recordTypeName) {
    if (recordTypeName) {
        return recordTypeName;
    }
    return pinKind === 'hco' ? 'Healthcare organization' : 'Healthcare professional';
}

function createVisitPinIcon(pinKind) {
    const svg = pinKind === 'hco' ? HCO_PIN_SVG : HCP_PIN_SVG;
    return window.L.divIcon({
        className: 'map-pin-icon-shell',
        html: `<div class="map-pin-marker map-pin-marker-${pinKind}" title="${pinKind === 'hco' ? 'HCO' : 'HCP'}">${svg}</div>`,
        iconSize: [30, 30],
        iconAnchor: [15, 15],
        popupAnchor: [0, -16]
    });
}

function resolveStatusMeta(status) {
    if (status === 'Draft') {
        return { label: 'Draft', statusClass: 'status-pill status-draft' };
    }
    if (status === 'Scheduled' || status === 'Rescheduled') {
        return { label: status, statusClass: 'status-pill status-scheduled' };
    }
    if (status === 'Completed') {
        return { label: 'Completed', statusClass: 'status-pill status-completed' };
    }
    if (status === 'Cancelled') {
        return { label: 'Cancelled', statusClass: 'status-pill status-cancelled' };
    }
    return { label: status || 'Visit', statusClass: 'status-pill' };
}

function getCurrentPosition() {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject(new Error('Geolocation is not supported in this browser.'));
            return;
        }
        navigator.geolocation.getCurrentPosition(
            (position) =>
                resolve({
                    latitude: position.coords.latitude,
                    longitude: position.coords.longitude
                }),
            (error) => {
                const messages = {
                    1: 'Location permission denied.',
                    2: 'Unable to determine your location.',
                    3: 'Location request timed out.'
                };
                reject(new Error(messages[error.code] || 'Unable to get your current location.'));
            },
            { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }
        );
    });
}

async function fetchOsrmRoute(coordPath, alternatives = false) {
    const altParam = alternatives ? '&alternatives=true&continue_straight=false' : '';
    const url = `${OSRM_BASE}/route/v1/driving/${coordPath}?overview=full&geometries=geojson${altParam}`;
    const response = await fetch(url);
    const data = await response.json();
    if (data.code !== 'Ok' || !data.routes?.length) {
        throw new Error('No route returned from routing service.');
    }
    if (alternatives) {
        return data.routes;
    }
    return data.routes[0];
}

async function fetchOsrmTrip(coordPath) {
    const url = `${OSRM_BASE}/trip/v1/driving/${coordPath}?source=first&roundtrip=false&geometries=geojson`;
    const response = await fetch(url);
    return response.json();
}

function parseOptimizedVisitOrder(tripResponse, visitIds) {
    const waypoints = tripResponse.waypoints || [];
    const visitIndices = waypoints
        .map((waypoint, inputIndex) => ({ inputIndex, tripIndex: waypoint.waypoint_index }))
        .filter((item) => item.inputIndex > 0)
        .sort((a, b) => a.tripIndex - b.tripIndex)
        .map((item) => item.inputIndex - 1);
    return visitIndices.map((index) => visitIds[index]).filter(Boolean);
}

function waitForDom() {
    return new Promise((resolve) => {
        window.requestAnimationFrame(() => {
            window.setTimeout(resolve, 0);
        });
    });
}

function plannerRestBase() {
    return typeof globalThis !== 'undefined' ? globalThis.PLANNER_REST_BASE || '' : '';
}

function isPwaRuntime() {
    return Boolean(plannerRestBase());
}

function loadStylesheet(href) {
    return new Promise((resolve, reject) => {
        if (typeof document === 'undefined') {
            reject(new Error('Document is not available.'));
            return;
        }
        const existing = document.querySelector(`link[data-leaflet-href="${href}"]`);
        if (existing) {
            resolve();
            return;
        }
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        link.setAttribute('data-leaflet-href', href);
        link.onload = () => resolve();
        link.onerror = () => reject(new Error(`Unable to load stylesheet ${href}`));
        document.head.appendChild(link);
    });
}

function loadScriptTag(src) {
    return new Promise((resolve, reject) => {
        if (typeof window !== 'undefined' && window.L) {
            resolve();
            return;
        }
        const script = document.createElement('script');
        script.src = src;
        script.async = false;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error(`Unable to load script ${src}`));
        document.head.appendChild(script);
    });
}

function formatMapCoord(point) {
    return `${point.latitude},${point.longitude}`;
}

function limitStopsForGoogleMaps(stops, hasOrigin) {
    const maxStops = hasOrigin ? GOOGLE_MAPS_MAX_STOPS_WITH_ORIGIN : GOOGLE_MAPS_MAX_STOPS_WITHOUT_ORIGIN;
    if (stops.length <= maxStops) {
        return { stops, truncatedCount: 0 };
    }
    return { stops: stops.slice(0, maxStops), truncatedCount: stops.length - maxStops };
}

function buildGoogleMapsDirectionsUrl(stops, originLocation) {
    if (!stops?.length) {
        return null;
    }

    const params = new URLSearchParams();
    params.set('api', '1');
    params.set('travelmode', 'driving');

    if (stops.length === 1) {
        if (originLocation) {
            params.set('origin', formatMapCoord(originLocation));
        }
        params.set('destination', formatMapCoord(stops[0]));
        return `https://www.google.com/maps/dir/?${params.toString()}`;
    }

    if (originLocation) {
        params.set('origin', formatMapCoord(originLocation));
        params.set('destination', formatMapCoord(stops[stops.length - 1]));
        const intermediates = stops.slice(0, -1);
        if (intermediates.length) {
            params.set('waypoints', intermediates.map(formatMapCoord).join('|'));
        }
    } else {
        params.set('origin', formatMapCoord(stops[0]));
        params.set('destination', formatMapCoord(stops[stops.length - 1]));
        const intermediates = stops.slice(1, -1);
        if (intermediates.length) {
            params.set('waypoints', intermediates.map(formatMapCoord).join('|'));
        }
    }

    return `https://www.google.com/maps/dir/?${params.toString()}`;
}

export default class FieldRepHomeTodayPlan extends LightningElement {
    @track upNextVisits = [];
    @track routeSummary;
    @track optimizationIdeas = [];
    @track routeOutliers = [];
    @track outlierVisitIds = [];
    @track unlinkedVisitCount = 0;
    @track plannerViewerContext;
    @track selectedContextUserId;
    @track isMutatingVisit = false;
    @track syncStatus = 'idle';
    @track errorMessage = '';
    @track noticeMessage = '';
    @track noticeVariant = 'success';
    @track hasCachedData = false;

    leafletReady = false;
    mapInstance;
    mapMarkers = [];
    markersByVisitId = {};
    routeLayer;
    selectedVisitId;
    currentLocation;
    cacheUserKey = CACHE_USER_FALLBACK;
    refreshAbort;
    _connectivityBound = false;

    connectedCallback() {
        this.init();
    }

    disconnectedCallback() {
        this.destroyMap();
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

    get hasNoVisits() {
        return !this.upNextVisits || this.upNextVisits.length === 0;
    }

    get geoVisits() {
        return (this.upNextVisits || []).filter((v) => v.hasLocation);
    }

    get canSwitchView() {
        return this.plannerViewerContext?.canSwitchView === true;
    }

    get viewerOptions() {
        const defaultUserId = this.plannerViewerContext?.defaultUserId;
        const options = [{ key: `my-plan-${defaultUserId || 'me'}`, label: 'My plan', value: defaultUserId }];
        const seen = new Set();
        if (defaultUserId) {
            seen.add(String(defaultUserId).substring(0, 15));
        }
        (this.plannerViewerContext?.options || []).forEach((option, idx) => {
            const val = option.userId || option.value;
            const norm = val ? String(val).substring(0, 15) : '';
            if (val && !seen.has(norm)) {
                seen.add(norm);
                options.push({
                    key: `rep-${val}-${idx}`,
                    label: option.label,
                    value: val
                });
            }
        });
        return options.map((option) => ({
            ...option,
            isSelected: option.value && this.selectedContextUserId ? sameSalesforceId(option.value, this.selectedContextUserId) : false
        }));
    }

    get isViewingSelf() {
        const defaultUserId = this.plannerViewerContext?.defaultUserId;
        return (
            !this.selectedContextUserId ||
            !defaultUserId ||
            sameSalesforceId(this.selectedContextUserId, defaultUserId)
        );
    }

    get contextUserId() {
        if (this.isViewingSelf) {
            return this.plannerViewerContext?.defaultUserId || null;
        }
        return this.selectedContextUserId || null;
    }

    get selectedRepDisplayName() {
        if (this.isViewingSelf) {
            return null;
        }
        const option = (this.plannerViewerContext?.options || []).find(
            (item) => item.userId === this.selectedContextUserId
        );
        return option?.userName || option?.label || 'Selected rep';
    }

    get viewingOtherBanner() {
        if (this.isViewingSelf) {
            return null;
        }
        return `Viewing ${this.selectedRepDisplayName}'s plan (read-only)`;
    }

    get planSubtitle() {
        const datePart = this.todayLabel;
        const stopsPart = this.stopsLabel;
        if (this.isViewingSelf) {
            return `${datePart} · ${stopsPart}`;
        }
        return `${datePart} · ${this.selectedRepDisplayName} · ${stopsPart}`;
    }

    get hasOptimizationIdeas() {
        return (this.optimizationIdeas || []).length > 0;
    }

    get hasRouteOutliers() {
        return (this.routeOutliers || []).length > 0;
    }

    get distantStopsSummary() {
        return formatDistantStopsSummary(this.routeOutliers);
    }

    get decoratedRouteOutliers() {
        return (this.routeOutliers || []).map((outlier) => ({
            ...outlier,
            canAct: this.canMutatePlan
        }));
    }

    get canMutatePlan() {
        return this.isViewingSelf;
    }

    get todayLabel() {
        return new Date().toLocaleDateString([], {
            weekday: 'long',
            month: 'short',
            day: 'numeric'
        });
    }

    get stopsLabel() {
        const count = this.upNextVisits?.length || 0;
        const geo = this.geoVisits.length;
        if (count === 0) {
            return this.isViewingSelf ? 'No account visits today' : 'No account visits scheduled';
        }
        if (geo === count) {
            return count === 1 ? '1 stop on route' : `${count} stops on route`;
        }
        return `${count} stops · ${geo} on map`;
    }

    get visitCountLabel() {
        return this.stopsLabel;
    }

    get showUnlinkedNote() {
        return this.unlinkedVisitCount > 0;
    }

    get unlinkedNote() {
        const n = this.unlinkedVisitCount;
        return n === 1
            ? '1 visit without an account is hidden. Link it in Planner.'
            : `${n} visits without an account are hidden. Link them in Planner.`;
    }

    get isGoogleNavigateDisabled() {
        return (this.geoVisits?.length || 0) === 0;
    }

    get googleNavigateTitle() {
        const count = this.geoVisits?.length || 0;
        if (count === 0) {
            return 'Add geocoded account visits to navigate';
        }
        if (count === 1) {
            return 'Open route to 1 stop in Google Maps';
        }
        return `Open route with ${count} stops in Google Maps`;
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

    get showOpenPlanner() {
        return !isPwaRuntime();
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

    setOptimizationIdeas(ideas) {
        this.optimizationIdeas = (ideas || []).map((idea, index) => {
            if (typeof idea === 'string') {
                return {
                    id: `idea-${index}`,
                    type: 'info',
                    text: idea,
                    isInfo: true,
                    isOutlier: false,
                    itemClass: 'ideas-item',
                    iconGlyph: '💡',
                    iconClass: 'ideas-icon'
                };
            }
            const isOutlier = idea.type === 'outlier';
            return {
                ...idea,
                id: idea.id || `idea-${index}`,
                type: idea.type || 'info',
                isInfo: (idea.type || 'info') === 'info',
                isOutlier,
                itemClass: isOutlier ? 'ideas-item ideas-item-outlier' : 'ideas-item',
                iconGlyph: isOutlier ? '⚠️' : '💡',
                iconClass: isOutlier ? 'ideas-icon ideas-icon-warning' : 'ideas-icon'
            };
        });
    }

    updateOutlierState(outliers) {
        this.routeOutliers = outliers || [];
        this.outlierVisitIds = this.routeOutliers.map((item) => item.visitId);
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
            await waitForDom();
            await this.initializeMapView();
        } else {
            this.hasCachedData = false;
        }

        // Note: navigator.onLine is unreliable in Capacitor WebView
        // Always try the API call - catch block handles real network failures
        this.syncStatus = 'updating';
        try {
            await this.loadTodayPlan({ skipMap: this.hasCachedData });
            this.errorMessage = '';
            this.syncStatus = 'idle';
        } catch (error) {
            if (error?.name === 'AbortError') {
                return;
            }
            this.syncStatus = 'offline';
            if (!this.hasCachedData) {
                this.errorMessage = this.isConnectivityError(error)
                    ? 'You are offline. Connect to load today’s plan.'
                    : this.reduceError(error) || 'Unable to load today’s plan.';
            }
        }
    }

    async handleContextUserChange(event) {
        this.selectedContextUserId = event.target?.value || event.detail?.value;
        this.destroyMap();
        try {
            this.syncStatus = 'updating';
            await this.loadTodayPlan();
            this.syncStatus = 'idle';
        } catch (error) {
            this.syncStatus = 'offline';
            this.showToast('Error', this.reduceError(error) || 'Unable to load today’s plan.', 'error');
        }
    }

    async loadTodayPlan(options = {}) {
        const payload = await this.fetchTodayPlan();
        this.applyTodayPlanPayload(payload);
        this.cacheUserKey = payload?.userId || this.contextUserId || CACHE_USER_FALLBACK;
        await this.writeCache();
        this.hasCachedData = true;
        if (!isPwaRuntime()) {
            this.prefetchVisitPayloads((this.upNextVisits || []).map((visit) => visit.id));
        }
        await waitForDom();
        await this.initializeMapView();
    }

    applyTodayPlanPayload(payload) {
        const todayKey = toDateKey(new Date());
        if (payload?.viewerContext) {
            this.plannerViewerContext = payload.viewerContext;
            if (!this.selectedContextUserId) {
                this.selectedContextUserId = payload.viewerContext.defaultUserId;
            }
        }
        const sortedVisits = (payload?.visits || [])
            .filter((v) => {
                const start = parseSalesforceDateTime(v.startDateTime);
                return !start || toDateKey(start) === todayKey;
            })
            .map((v) => this.normalizeVisit(v))
            .sort((a, b) => new Date(a.startDateTime) - new Date(b.startDateTime));
        const accountVisits = sortedVisits.filter((v) => v.accountId);
        const accountsToCache = accountVisits.map((v) => ({
            id: v.accountId,
            name: v.accountName,
            street: v.accountAddress,
            city: v.accountCity,
            specialty: v.accountSpecialty,
            classification: v.accountClassification,
            latitude: v.accountLatitude,
            longitude: v.accountLongitude
        }));
        if (accountsToCache.length) {
            void putCachedAccounts(accountsToCache);
        }
        this.unlinkedVisitCount = sortedVisits.length - accountVisits.length;
        this.selectedVisitId = accountVisits[0]?.id || this.selectedVisitId || null;
        this.upNextVisits = accountVisits.map((v, index) => this.decorateVisit(v, index));
    }

    applyCachedBundle(cached) {
        const visits = Array.isArray(cached) ? cached : cached?.visits || [];
        this.unlinkedVisitCount = Array.isArray(cached) ? 0 : cached?.unlinkedVisitCount || 0;
        if (cached?.viewerContext) {
            this.plannerViewerContext = cached.viewerContext;
            this.selectedContextUserId = cached.selectedContextUserId || cached.viewerContext.defaultUserId;
        }
        this.upNextVisits = visits;
        this.selectedVisitId = visits[0]?.id || null;
        this.refreshVisitSelection();
    }

    async readCache() {
        const primary = await getTodayPlan(getUserTodayPlanKey(this.cacheUserKey));
        if (primary) {
            return primary;
        }
        if (this.cacheUserKey !== CACHE_USER_FALLBACK) {
            return getTodayPlan(getUserTodayPlanKey(CACHE_USER_FALLBACK));
        }
        return null;
    }

    async writeCache() {
        const bundle = {
            visits: this.upNextVisits,
            unlinkedVisitCount: this.unlinkedVisitCount,
            viewerContext: this.plannerViewerContext,
            selectedContextUserId: this.selectedContextUserId
        };
        await putTodayPlan(getUserTodayPlanKey(this.cacheUserKey), bundle);
        if (this.cacheUserKey !== CACHE_USER_FALLBACK) {
            await putTodayPlan(getUserTodayPlanKey(CACHE_USER_FALLBACK), bundle);
        }
    }

    async fetchTodayPlan() {
        const restBase = plannerRestBase();
        if (restBase) {
            return this.fetchTodayPlanRest(restBase);
        }
        return getTodayPlanPayload({
            contextUserId: this.contextUserId,
            planDate: toApexDate(new Date())
        });
    }

    async fetchTodayPlanRest(restBase) {
        const params = new URLSearchParams();
        params.set('planDate', toApexDate(new Date()));
        if (this.contextUserId) {
            params.set('contextUserId', this.contextUserId);
        }
        return this.plannerFetch(`${TODAY_PLAN_PATH}?${params.toString()}`, { method: 'GET' }, restBase);
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
            console.warn('[TodayPlan] Network error detected:', fetchError.message);
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

    prefetchVisitPayloads(visitIds) {
        (visitIds || []).forEach((visitId) => {
            if (!visitId) {
                return;
            }
            getCallReportPayload({ visitId })
                .then((payload) => putVisitPayload(visitId, payload))
                .catch(() => {
                    // Best effort cache for offline visits.
                });
            getRatingCaptureContext({ visitId, sessionId: null })
                .then((context) => putRatingContext(visitId, context))
                .catch(() => {
                    // Best effort ratings cache.
                });
            getCoachingFormContext({ visitId })
                .then((context) => putCoachingContext(visitId, context))
                .catch(() => {
                    // Best effort coaching cache.
                });
        });
    }

    normalizeVisit(v) {
        const start = parseSalesforceDateTime(v.startDateTime);
        const end = parseSalesforceDateTime(v.endDateTime);
        const pinKind = resolveAccountPinKind(v.accountRecordTypeDeveloperName, v.accountRecordTypeName);
        const latitude =
            v.accountLatitude != null && v.accountLatitude !== ''
                ? Number(v.accountLatitude)
                : null;
        const longitude =
            v.accountLongitude != null && v.accountLongitude !== ''
                ? Number(v.accountLongitude)
                : null;
        const hasLocation = Number.isFinite(latitude) && Number.isFinite(longitude);

        return {
            id: v.id,
            visitName: v.name,
            accountName: v.accountName,
            accountId: v.accountId,
            status: v.status,
            visitType: v.visitType,
            accountSpecialty: v.accountSpecialty,
            accountRecordTypeDeveloperName: v.accountRecordTypeDeveloperName,
            accountRecordTypeName: v.accountRecordTypeName,
            pinKind,
            accountTypeLabel: resolveAccountTypeLabel(pinKind, v.accountRecordTypeName),
            startDateTime: v.startDateTime,
            endDateTime: v.endDateTime,
            latitude,
            longitude,
            hasLocation,
            timeLabel:
                start && end
                    ? `${formatTime(start)} – ${formatTime(end)}`
                    : formatTime(start)
        };
    }

    decorateVisit(visit, index) {
        const isSelected = visit.id === this.selectedVisitId;
        const visitIdKey = normalizeSalesforceId(visit.id);
        const isOutlier = (this.outlierVisitIds || []).some(
            (id) => normalizeSalesforceId(id) === visitIdKey
        );
        const statusMeta = resolveStatusMeta(visit.status);
        const outlierSuffix = isOutlier ? ' route-stop-outlier' : '';
        return {
            ...visit,
            order: index + 1,
            orderLabel: String(index + 1),
            orderClass: `route-stop-order route-stop-order-${visit.pinKind}${isOutlier ? ' route-stop-order-outlier' : ''}`,
            stopClass: `route-stop${isSelected ? ' route-stop-selected' : ''}${outlierSuffix}`,
            statusLabel: statusMeta.label,
            statusClass: statusMeta.statusClass,
            isOutlier,
            canMutate: this.canMutatePlan && visit.status !== 'Completed' && !isOutlier
        };
    }

    refreshVisitSelection() {
        this.upNextVisits = (this.upNextVisits || []).map((v, index) => this.decorateVisit(v, index));
    }

    async initializeMapView() {
        try {
            await this.ensureLeaflet();
            await this.renderMap();
            await this.computeRouteAndOptimization();
        } catch (e) {
            this.setOptimizationIdeas(['Unable to load today’s plan map.']);
        }
    }

    async ensureLeaflet() {
        if (this.leafletReady && window.L) {
            return;
        }
        const useCdn = isPwaRuntime();
        const cssHref = useCdn ? `${LEAFLET_CDN}/leaflet.css` : '/resource/leaflet/leaflet.css';
        const jsSrc = useCdn ? `${LEAFLET_CDN}/leaflet.js` : '/resource/leaflet/leaflet.js';
        const iconBase = useCdn ? `${LEAFLET_CDN}/images` : '/resource/leaflet';
        await loadStylesheet(cssHref);
        await loadScriptTag(jsSrc);
        if (!window.L) {
            throw new Error('Leaflet failed to load.');
        }
        delete window.L.Icon.Default.prototype._getIconUrl;
        window.L.Icon.Default.mergeOptions({
            iconRetinaUrl: `${iconBase}/marker-icon-2x.png`,
            iconUrl: `${iconBase}/marker-icon.png`,
            shadowUrl: `${iconBase}/marker-shadow.png`
        });
        this.leafletReady = true;
    }

    destroyMap() {
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = undefined;
        }
        this.mapMarkers = [];
        this.markersByVisitId = {};
        this.routeLayer = undefined;
    }

    fitAllVisits() {
        const points = this.geoVisits;
        if (!this.mapInstance || !points.length) {
            return;
        }
        if (points.length === 1) {
            this.mapInstance.setView([points[0].latitude, points[0].longitude], 15);
            return;
        }
        const bounds = window.L.latLngBounds(points.map((p) => [p.latitude, p.longitude]));
        this.mapInstance.fitBounds(bounds.pad(0.15), { maxZoom: 14 });
    }

    flyToVisit(visitId, animate = true) {
        const visit = (this.upNextVisits || []).find((v) => v.id === visitId);
        if (!visit?.latitude || !visit?.longitude || !this.mapInstance) {
            return;
        }
        const latlng = [visit.latitude, visit.longitude];
        if (animate) {
            this.mapInstance.flyTo(latlng, 16, { duration: 0.75 });
        } else {
            this.mapInstance.setView(latlng, 16);
        }
        const marker = this.markersByVisitId[visitId];
        if (marker) {
            window.setTimeout(() => marker.openPopup(), animate ? 400 : 0);
        }
    }

    buildVisitPopupHtml(visit) {
        return `<strong>${visit.order}. ${visit.accountName}</strong><br/><span>${visit.accountTypeLabel}</span><br/>${visit.timeLabel}<br/><span>${visit.statusLabel}</span>`;
    }

    async renderMap() {
        await this.ensureLeaflet();
        const container = this.template.querySelector('.map-container');
        if (!container) {
            return;
        }

        this.destroyMap();
        container.innerHTML = '';
        const mapDiv = document.createElement('div');
        mapDiv.className = 'map-canvas';
        container.appendChild(mapDiv);

        const points = this.geoVisits;
        const defaultCenter = points.length ? [points[0].latitude, points[0].longitude] : DEFAULT_MAP_CENTER;
        const defaultZoom = points.length === 1 ? 15 : DEFAULT_MAP_ZOOM;

        this.mapInstance = window.L.map(mapDiv).setView(defaultCenter, defaultZoom);
        window.L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '&copy; OpenStreetMap contributors'
        }).addTo(this.mapInstance);

        this.currentLocation = null;

        points.forEach((v) => {
            const marker = window.L.marker([v.latitude, v.longitude], {
                icon: createVisitPinIcon(v.pinKind)
            }).addTo(this.mapInstance);
            marker.bindPopup(this.buildVisitPopupHtml(v));
            marker.on('click', () => {
                this.selectedVisitId = v.id;
                this.refreshVisitSelection();
            });
            this.mapMarkers.push(marker);
            this.markersByVisitId[v.id] = marker;
        });

        window.setTimeout(() => {
            this.mapInstance?.invalidateSize?.();
            if (this.selectedVisitId) {
                this.flyToVisit(this.selectedVisitId, false);
            } else {
                this.fitAllVisits();
            }
        }, 120);
    }

    async computeRouteAndOptimization() {
        this.routeSummary = null;
        this.updateOutlierState([]);
        this.setOptimizationIdeas([]);

        const geoStops = this.geoVisits.map((v) => ({
            id: v.id,
            accountName: v.accountName,
            latitude: v.latitude,
            longitude: v.longitude
        }));
        const outliers = detectRouteOutliers(geoStops);
        this.updateOutlierState(outliers);
        this.refreshVisitSelection();

        const infoIdeas = [];
        const points = geoStops.map((v) => ({ latitude: v.latitude, longitude: v.longitude }));

        if (points.length < 2) {
            infoIdeas.push('Add more geocoded account visits in Planner to see route optimization.');
            this.setOptimizationIdeas(infoIdeas);
            return;
        }

        const coordPath = buildCoordPath(points);

        try {
            const selectedRoute = await fetchOsrmRoute(coordPath, false);
            const coords = selectedRoute.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
            this.routeLayer = window.L.polyline(coords, { color: '#2e7d32', weight: 5, opacity: 0.85 });
            this.routeLayer.addTo(this.mapInstance);
            this.mapInstance.fitBounds(this.routeLayer.getBounds().pad(0.15));

            this.routeSummary = {
                durationMin: Math.round(selectedRoute.duration / 60),
                distanceKm: (selectedRoute.distance / 1000).toFixed(1)
            };

            const tripResponse = await fetchOsrmTrip(coordPath);
            const trip = tripResponse?.trips?.[0];
            if (!trip) {
                infoIdeas.push('Open the route in Planner to review optimization options.');
            } else {
                const originalVisitIds = this.upNextVisits.map((v) => v.id);
                const optimizedOrder = parseOptimizedVisitOrder(tripResponse, originalVisitIds);
                const isSameOrder =
                    optimizedOrder?.length === originalVisitIds.length &&
                    optimizedOrder.every((id, idx) => id === originalVisitIds[idx]);

                if (isSameOrder) {
                    infoIdeas.push(
                        'The current stop order is already near-optimal for estimated drive time.'
                    );
                } else {
                    const savingsMin = Math.max(0, Math.round((selectedRoute.duration - trip.duration) / 60));
                    infoIdeas.push(
                        `Reordering stops could reduce estimated travel time by about ${savingsMin} minutes.`,
                        'Open Planner to apply the suggested stop order.'
                    );
                }
            }
        } catch (e) {
            infoIdeas.push('Route optimization is unavailable right now. Try again later.');
        }

        this.setOptimizationIdeas(infoIdeas);
    }

    resolveVisitIdFromEvent(event) {
        const candidates = [event?.currentTarget, event?.target, event?.target?.closest?.('[data-visit-id]')];
        for (const element of candidates) {
            const visitId = element?.dataset?.visitId;
            if (visitId) {
                return visitId;
            }
        }
        return null;
    }

    findVisitById(visitId) {
        if (!visitId) {
            return null;
        }
        const key = normalizeSalesforceId(visitId);
        return (this.upNextVisits || []).find((visit) => normalizeSalesforceId(visit.id) === key) || null;
    }

    async handlePostponeVisit(event) {
        event?.stopPropagation?.();
        const visitId = this.resolveVisitIdFromEvent(event);
        if (!visitId || !this.canMutatePlan) {
            return;
        }
        const visit = this.findVisitById(visitId);
        if (!visit) {
            this.showToast('Postpone failed', 'Visit not found in today’s plan.', 'error');
            return;
        }
        const start = parseSalesforceDateTime(visit.startDateTime);
        const end = parseSalesforceDateTime(visit.endDateTime);
        if (!start || !end) {
            this.showToast('Postpone failed', 'Visit times are missing.', 'error');
            return;
        }
        const label = visit.accountName || 'this visit';
        const confirmed = window.confirm(`Postpone ${label} to tomorrow at the same time?`);
        if (!confirmed) {
            return;
        }

        const tomorrowStart = new Date(start);
        tomorrowStart.setDate(tomorrowStart.getDate() + 1);
        const tomorrowEnd = new Date(end);
        tomorrowEnd.setDate(tomorrowEnd.getDate() + 1);

        this.isMutatingVisit = true;
        try {
            if (isOfflineMode()) {
                console.log('[TodayPlan] [Offline Postpone] Queueing reschedule for visit:', visit.id);
                await queueOfflineAction({
                    actionType: 'RESCHEDULE_VISITS',
                    clientActionKey: newClientKey('reschedule'),
                    payloadJson: JSON.stringify({
                        visitIds: [visit.id],
                        startDateTimes: [tomorrowStart.toISOString()],
                        endDateTimes: [tomorrowEnd.toISOString()]
                    })
                });
                console.log('[TodayPlan] [Offline Postpone] Optimistically removed from today view & cached.');
                this.upNextVisits = (this.upNextVisits || []).filter((row) => row.id !== visit.id);
                await this.writeCache();
                this.showToast(
                    'Queued offline',
                    `${label} will move to tomorrow when you sync.`,
                    'success'
                );
                return;
            }
            await this.rescheduleVisitRemote(visit.id, tomorrowStart, tomorrowEnd);
            this.showToast('Visit postponed', `${label} moved to tomorrow.`, 'success');
            await this.loadTodayPlan();
        } catch (error) {
            this.showToast('Postpone failed', this.reduceError(error), 'error');
        } finally {
            this.isMutatingVisit = false;
        }
    }

    async handleRemoveVisit(event) {
        event?.stopPropagation?.();
        const visitId = this.resolveVisitIdFromEvent(event);
        if (!visitId || !this.canMutatePlan) {
            return;
        }
        const visit = this.findVisitById(visitId);
        if (!visit) {
            this.showToast('Remove failed', 'Visit not found in today’s plan.', 'error');
            return;
        }
        if (visit.status === 'Completed') {
            this.showToast('Cannot remove', 'Completed visits cannot be deleted.', 'error');
            return;
        }
        const label = visit.accountName || 'this visit';
        const confirmed = window.confirm(`Remove ${label} from today’s plan? This cannot be undone.`);
        if (!confirmed) {
            return;
        }

        // If offline, queue the action and update UI optimistically
        if (isOfflineMode()) {
            await queueOfflineAction({
                type: 'DELETE_VISIT',
                path: VISITS_DELETE_PATH,
                payload: { visitId: visit.id }
            });
            // Optimistically remove from UI
            this.upNextVisits = this.upNextVisits.filter(
                (v) => !sameSalesforceId(v.id, visit.id)
            );
            this.showToast('Visit queued for removal', `${label} will be removed when online`, 'info');
            return;
        }

        this.isMutatingVisit = true;
        try {
            await this.deleteVisitRemote(visit.id);
            this.showToast('Visit removed', label, 'success');
            await this.loadTodayPlan();
        } catch (error) {
            // If network error, queue for later
            if (error?.name === 'OfflineError' || error?.message?.includes('fetch')) {
                await queueOfflineAction({
                    type: 'DELETE_VISIT',
                    path: VISITS_DELETE_PATH,
                    payload: { visitId: visit.id }
                });
                // Optimistically remove from UI
                this.upNextVisits = this.upNextVisits.filter(
                    (v) => !sameSalesforceId(v.id, visit.id)
                );
                this.showToast('Visit queued for removal', `${label} will be removed when online`, 'info');
            } else {
                this.showToast('Remove failed', this.reduceError(error), 'error');
            }
        } finally {
            this.isMutatingVisit = false;
        }
    }

    handleSelectVisit(event) {
        const visitId = event?.currentTarget?.dataset?.visitId;
        if (!visitId || visitId === this.selectedVisitId) {
            return;
        }
        this.selectedVisitId = visitId;
        this.refreshVisitSelection();
        this.flyToVisit(visitId);
    }

    handleOpenVisit(event) {
        event?.stopPropagation?.();
        const visitId = event?.currentTarget?.dataset?.visitId;
        if (!visitId) {
            return;
        }
        this.openSalesforceRecord('Visit__c', visitId);
    }

    handleOpenAccount(event) {
        event?.stopPropagation?.();
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }
        this.openSalesforceRecord('Account', accountId);
    }

    handleOpenPlanner() {
        if (isPwaRuntime()) {
            return;
        }
        window.open(`/lightning/n/${PLANNER_TAB_API}`, '_self');
    }

    openSalesforceRecord(objectApiName, recordId) {
        if (isPwaRuntime() && objectApiName !== 'Account') {
            window.open(`/record.html?recordId=${encodeURIComponent(recordId)}&object=${encodeURIComponent(objectApiName)}`, '_blank');
            return;
        }
        const instanceUrl = typeof globalThis !== 'undefined' ? globalThis.PLANNER_SF_INSTANCE || '' : '';
        const path = `/lightning/r/${objectApiName}/${recordId}/view`;
        if (instanceUrl) {
            window.open(`${String(instanceUrl).replace(/\/$/, '')}${path}`, '_blank');
            return;
        }
        window.open(path, '_self');
    }

    handleNavigateGoogle() {
        const geoStops = this.geoVisits.map((visit) => ({
            latitude: visit.latitude,
            longitude: visit.longitude
        }));

        if (!geoStops.length) {
            this.showToast(
                'No map stops',
                'Add geocoded account visits in Planner to open a Google Maps route.',
                'warning'
            );
            return;
        }

        const originLocation = this.isViewingSelf ? this.currentLocation : null;
        const { stops, truncatedCount } = limitStopsForGoogleMaps(geoStops, Boolean(originLocation));
        const mapsUrl = buildGoogleMapsDirectionsUrl(stops, originLocation);

        if (!mapsUrl) {
            this.showToast('Unable to open route', 'Could not build a Google Maps route.', 'error');
            return;
        }

        window.open(mapsUrl, '_blank', 'noopener');

        const stopCount = stops.length;
        const message =
            truncatedCount > 0
                ? `Opened Google Maps with ${stopCount} stops (${truncatedCount} omitted — Google Maps limit).`
                : stopCount === 1
                  ? 'Opened Google Maps with your next stop.'
                  : `Opened Google Maps with ${stopCount} stops in today’s visit order.`;

        this.showToast('Google Maps', message, 'success');
    }

    async rescheduleVisitRemote(visitId, startDateTime, endDateTime) {
        const restBase = plannerRestBase();
        if (restBase) {
            return this.plannerFetch(VISITS_RESCHEDULE_PATH, {
                method: 'POST',
                body: JSON.stringify({
                    moves: [
                        {
                            visitId,
                            startDateTime: startDateTime.toISOString(),
                            endDateTime: endDateTime.toISOString()
                        }
                    ]
                })
            });
        }
        return rescheduleVisits({
            visitIds: [visitId],
            startDateTimes: [toApexDateTime(startDateTime)],
            endDateTimes: [toApexDateTime(endDateTime)]
        });
    }

    async deleteVisitRemote(visitId) {
        const restBase = plannerRestBase();
        if (restBase) {
            return this.plannerFetch(VISITS_DELETE_PATH, {
                method: 'POST',
                body: JSON.stringify({ visitId })
            });
        }
        return deleteVisit({ visitId });
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