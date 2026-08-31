import { LightningElement, track } from 'lwc';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getFleetMapData from '@salesforce/apex/ManagerFleetMapController.getFleetMapData';
import getBusinessUnitOptions from '@salesforce/apex/ManagementKpiController.getBusinessUnitOptions';
import getLineOptions from '@salesforce/apex/ManagementKpiController.getLineOptions';
import getDistrictOptions from '@salesforce/apex/ManagementKpiController.getDistrictOptions';
import {
    ensureLeaflet,
    addOsmTileLayer,
    createVisitPinIcon,
    resolveAccountPinKind
} from 'c/plannerMapPins';
import { fetchOsrmRoute, buildCoordPath } from 'c/plannerMapUtils';

const DEFAULT_MAP_CENTER = [30.0444, 31.2357];
const DEFAULT_MAP_ZOOM = 11;
const REFRESH_INTERVAL_MS = 45000;

const REP_COLORS = [
    '#0176d3',
    '#2e844a',
    '#fe9339',
    '#ba0517',
    '#6a1b9a',
    '#0d9dda',
    '#e3066a',
    '#54698d',
    '#04844b',
    '#ff538a'
];

function toDateInputValue(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function parseRouteDate(value) {
    if (!value) {
        return new Date();
    }
    const parts = value.split('-').map(Number);
    return new Date(parts[0], parts[1] - 1, parts[2]);
}

function formatLastSeen(recordedAt) {
    if (!recordedAt) {
        return 'No location yet';
    }
    const date = new Date(recordedAt);
    if (Number.isNaN(date.getTime())) {
        return 'Unknown';
    }
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function statusLabel(status) {
    if (status === 'online') {
        return 'Online';
    }
    if (status === 'stale') {
        return 'Stale';
    }
    return 'Offline';
}

export default class ManagementFleetMap extends LightningElement {
    @track buOptions = [];
    @track lineOptions = [];
    @track districtOptions = [];
    @track selectedBu = 'ALL';
    @track selectedLine = 'ALL';
    @track selectedDistrict = 'ALL';
    @track routeDateValue = toDateInputValue(new Date());
    @track repRows = [];
    @track summary = { onlineCount: 0, staleCount: 0, offlineCount: 0 };
    @track isLoading = true;
    @track errorMessage;

    mapInstance;
    leafletReady = false;
    repLayers = new Map();
    visibleRepIds = new Set();
    refreshTimer;
    visibilityHandler;
    mapInitScheduled = false;

    async connectedCallback() {
        this.visibilityHandler = () => {
            if (document.hidden) {
                this.stopAutoRefresh();
            } else {
                this.startAutoRefresh();
                this.refreshFleetData(false);
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);
        await Promise.all([this.loadBuOptions(), this.loadLineOptions(), this.loadDistrictOptions()]);
        await this.refreshFleetData(true);
        this.startAutoRefresh();
    }

    disconnectedCallback() {
        document.removeEventListener('visibilitychange', this.visibilityHandler);
        this.stopAutoRefresh();
        this.destroyMapLayers();
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = null;
        }
    }

    renderedCallback() {
        if (!this.mapInitScheduled && this.template.querySelector('.fleet-map-root')) {
            this.mapInitScheduled = true;
            this.initializeMap();
        }
    }

    get scopeLabel() {
        const parts = [];
        const bu = this.buOptions.find((o) => o.value === this.selectedBu);
        const line = this.lineOptions.find((o) => o.value === this.selectedLine);
        const district = this.districtOptions.find((o) => o.value === this.selectedDistrict);
        if (bu && bu.value !== 'ALL') {
            parts.push(bu.label);
        }
        if (line && line.value !== 'ALL') {
            parts.push(line.label);
        }
        if (district && district.value !== 'ALL') {
            parts.push(district.label);
        }
        return parts.length ? parts.join(' · ') : 'All Territories';
    }

    get hasReps() {
        return this.repRows.length > 0;
    }

    get emptyMessage() {
        if (this.isLoading) {
            return '';
        }
        return 'No field reps in the selected territory scope.';
    }

    async loadBuOptions() {
        const options = await getBusinessUnitOptions();
        this.buOptions = (options || []).map((opt) => ({
            label: opt.label,
            value: opt.value || opt.territoryId || 'ALL'
        }));
        if (!this.buOptions.length) {
            this.buOptions = [{ label: 'All Business Units', value: 'ALL' }];
        }
    }

    async loadLineOptions() {
        try {
            const options = await getLineOptions({ buTerritoryId: this.selectedBu });
            this.lineOptions = (options || []).map((opt) => ({
                label: opt.label,
                value: opt.value || opt.territoryId || 'ALL'
            }));
        } catch (error) {
            this.lineOptions = [{ label: 'All Lines', value: 'ALL' }];
        }
        if (!this.lineOptions.length) {
            this.lineOptions = [{ label: 'All Lines', value: 'ALL' }];
        }
    }

    async loadDistrictOptions() {
        try {
            const options = await getDistrictOptions({ lineTerritoryId: this.selectedLine });
            this.districtOptions = (options || []).map((opt) => ({
                label: opt.label,
                value: opt.value || opt.territoryId || 'ALL'
            }));
        } catch (error) {
            this.districtOptions = [{ label: 'All Districts', value: 'ALL' }];
        }
        if (!this.districtOptions.length) {
            this.districtOptions = [{ label: 'All Districts', value: 'ALL' }];
        }
    }

    async handleBuChange(event) {
        this.selectedBu = event.detail.value;
        this.selectedLine = 'ALL';
        this.selectedDistrict = 'ALL';
        await Promise.all([this.loadLineOptions(), this.loadDistrictOptions()]);
        await this.refreshFleetData(true);
    }

    async handleLineChange(event) {
        this.selectedLine = event.detail.value;
        this.selectedDistrict = 'ALL';
        await this.loadDistrictOptions();
        await this.refreshFleetData(true);
    }

    async handleDistrictChange(event) {
        this.selectedDistrict = event.detail.value;
        await this.refreshFleetData(true);
    }

    async handleDateChange(event) {
        this.routeDateValue = event.detail.value;
        await this.refreshFleetData(true);
    }

    async handleManualRefresh() {
        await this.refreshFleetData(true);
    }

    handleRepToggle(event) {
        const repId = event.currentTarget.dataset.repId;
        const isVisible = event.detail.checked;
        if (isVisible) {
            this.visibleRepIds.add(repId);
        } else {
            this.visibleRepIds.delete(repId);
        }
        this.applyRepVisibility(repId, isVisible);
        this.repRows = this.repRows.map((row) =>
            row.userId === repId ? { ...row, isVisible } : row
        );
        this.fitVisibleBounds();
    }

    startAutoRefresh() {
        this.stopAutoRefresh();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.refreshTimer = window.setInterval(() => {
            this.refreshFleetData(false);
        }, REFRESH_INTERVAL_MS);
    }

    stopAutoRefresh() {
        if (this.refreshTimer) {
            window.clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
    }

    async refreshFleetData(showSpinner) {
        if (showSpinner) {
            this.isLoading = true;
        }
        this.errorMessage = null;
        try {
            const payload = await getFleetMapData({
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict,
                routeDate: parseRouteDate(this.routeDateValue)
            });
            const previousVisibility = new Map(this.repRows.map((row) => [row.userId, row.isVisible]));
            this.summary = {
                onlineCount: payload?.onlineCount || 0,
                staleCount: payload?.staleCount || 0,
                offlineCount: payload?.offlineCount || 0
            };
            this.repRows = (payload?.reps || []).map((rep, index) => {
                const color = REP_COLORS[index % REP_COLORS.length];
                const status = rep.location?.status || 'offline';
                const isVisible = previousVisibility.has(rep.userId)
                    ? previousVisibility.get(rep.userId)
                    : true;
                if (isVisible) {
                    this.visibleRepIds.add(rep.userId);
                }
                return {
                    userId: rep.userId,
                    userName: rep.userName,
                    color,
                    swatchStyle: `background-color: ${color}`,
                    status,
                    statusLabel: statusLabel(status),
                    statusClass: `status-pill status-${status}`,
                    lastSeenLabel: formatLastSeen(rep.location?.recordedAt),
                    visitsLabel: `${rep.completedVisits || 0}/${rep.totalVisits || 0} visits`,
                    isVisible,
                    toggleLabel: `Show ${rep.userName} on map`,
                    raw: rep
                };
            });
            if (this.leafletReady) {
                await this.renderFleetLayers();
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load fleet map data.';
        } finally {
            this.isLoading = false;
        }
    }

    async initializeMap() {
        const container = this.template.querySelector('.fleet-map-root');
        if (!container || this.mapInstance) {
            return;
        }
        try {
            const leaflet = await ensureLeaflet(this, LEAFLET);
            container.innerHTML = '';
            const mapDiv = document.createElement('div');
            mapDiv.style.height = '100%';
            mapDiv.style.width = '100%';
            container.appendChild(mapDiv);
            this.mapInstance = leaflet.map(mapDiv, {
                center: DEFAULT_MAP_CENTER,
                zoom: DEFAULT_MAP_ZOOM,
                zoomControl: true
            });
            addOsmTileLayer(this.mapInstance, leaflet);
            this.leafletReady = true;
            await this.renderFleetLayers();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => this.mapInstance?.invalidateSize?.(), 150);
        } catch (error) {
            this.errorMessage = 'Unable to initialize the map.';
        }
    }

    destroyMapLayers() {
        if (!this.mapInstance) {
            return;
        }
        for (const layerGroup of this.repLayers.values()) {
            this.mapInstance.removeLayer(layerGroup);
        }
        this.repLayers.clear();
    }

    applyRepVisibility(repId, isVisible) {
        const layerGroup = this.repLayers.get(repId);
        if (!layerGroup || !this.mapInstance) {
            return;
        }
        if (isVisible) {
            layerGroup.addTo(this.mapInstance);
        } else {
            this.mapInstance.removeLayer(layerGroup);
        }
    }

    async renderFleetLayers() {
        if (!this.mapInstance || !window.L) {
            return;
        }
        this.destroyMapLayers();
        const leaflet = window.L;
        const renderJobs = this.repRows.map((row) => this.renderRepLayer(row, leaflet));
        await Promise.all(renderJobs);
        this.fitVisibleBounds();
    }

    async renderRepLayer(row, leaflet) {
        const rep = row.raw;
        const layerGroup = leaflet.layerGroup();
        this.repLayers.set(row.userId, layerGroup);

        const geocodedStops = (rep.stops || []).filter(
            (stop) => stop.latitude != null && stop.longitude != null
        );

        if (geocodedStops.length >= 2) {
            try {
                const coordPath = buildCoordPath(geocodedStops);
                const route = await fetchOsrmRoute(coordPath);
                const coordinates = route?.geometry?.coordinates || [];
                if (coordinates.length) {
                    const latLngs = coordinates.map((coord) => [coord[1], coord[0]]);
                    leaflet
                        .polyline(latLngs, {
                            color: row.color,
                            weight: 4,
                            opacity: 0.85
                        })
                        .addTo(layerGroup);
                }
            } catch (error) {
                const fallback = geocodedStops.map((stop) => [stop.latitude, stop.longitude]);
                leaflet.polyline(fallback, { color: row.color, weight: 3, opacity: 0.6, dashArray: '6 8' }).addTo(layerGroup);
            }
        } else if (geocodedStops.length === 1) {
            const stop = geocodedStops[0];
            leaflet.circleMarker([stop.latitude, stop.longitude], {
                radius: 6,
                color: row.color,
                fillColor: row.color,
                fillOpacity: 0.35,
                weight: 2
            }).addTo(layerGroup);
        }

        geocodedStops.forEach((stop) => {
            const pinKind = resolveAccountPinKind(
                stop.accountRecordTypeDeveloperName,
                stop.accountRecordTypeName
            );
            const marker = leaflet.marker([stop.latitude, stop.longitude], {
                icon: createVisitPinIcon(pinKind, leaflet)
            });
            marker.bindPopup(
                `<strong>${stop.stopNumber}. ${stop.accountName}</strong><br/>${stop.status || ''}<br/>${row.userName}`
            );
            marker.addTo(layerGroup);
        });

        const location = rep.location;
        if (
            location?.latitude != null &&
            location?.longitude != null &&
            location?.isSharing !== false
        ) {
            const repMarker = leaflet.circleMarker([location.latitude, location.longitude], {
                radius: 10,
                color: '#ffffff',
                fillColor: row.color,
                fillOpacity: 0.95,
                weight: 3
            });
            const nextVisit = rep.nextVisitName
                ? `<br/>Next: ${rep.nextVisitName}`
                : '<br/>No upcoming visits';
            repMarker.bindPopup(
                `<strong>${row.userName}</strong><br/>${row.statusLabel} · ${row.lastSeenLabel}${nextVisit}`
            );
            repMarker.addTo(layerGroup);
        }

        if (row.isVisible) {
            layerGroup.addTo(this.mapInstance);
        }
    }

    fitVisibleBounds() {
        if (!this.mapInstance || !window.L) {
            return;
        }
        const bounds = [];
        for (const row of this.repRows) {
            if (!row.isVisible) {
                continue;
            }
            const rep = row.raw;
            if (rep.location?.latitude != null && rep.location?.longitude != null) {
                bounds.push([rep.location.latitude, rep.location.longitude]);
            }
            (rep.stops || []).forEach((stop) => {
                if (stop.latitude != null && stop.longitude != null) {
                    bounds.push([stop.latitude, stop.longitude]);
                }
            });
        }
        if (bounds.length) {
            this.mapInstance.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 });
        } else {
            this.mapInstance.setView(DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM);
        }
    }
}