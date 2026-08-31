import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getAccountVisitContext from '@salesforce/apex/AccountVisitInsightsController.getAccountVisitContext';
import getNearbyPlanTargets from '@salesforce/apex/AccountVisitInsightsController.getNearbyPlanTargets';
import bulkCreateDraftVisits from '@salesforce/apex/AccountVisitInsightsController.bulkCreateDraftVisits';
import {
    addOsmTileLayer,
    createVisitPinIcon,
    ensureLeaflet,
    getPinColor,
    resolveAccountPinKind,
    resolveAccountTypeLabel
} from 'c/plannerMapPins';

const NEIGHBOR_PAGE_SIZE = 5;
const SINGLE_ACCOUNT_MAP_ZOOM = 15;

const PACE_LABELS = {
    ahead: 'Ahead of target pace',
    on_track: 'On track to hit target',
    behind: 'Behind target pace',
    critical: 'Critically behind pace',
    not_applicable: 'Pace not available'
};

function formatDateTime(value) {
    if (!value) {
        return '';
    }
    return new Date(value).toLocaleString(undefined, {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit'
    });
}

function formatPercent(value) {
    const num = Number(value) || 0;
    return `${Math.round(num)}%`;
}

function todayIso() {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${now.getFullYear()}-${month}-${day}`;
}

export default class AccountVisitInsightsPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    isLoading = true;
    isNeighborsLoading = true;
    isSaving = false;
    errorMessage;

    context;
    neighborRows = [];
    currentNeighborPage = 1;
    searchRadiusKm = 25;
    selectedAccountIds = new Set();
    visitDate = todayIso();

    mapInstance;
    mapMarkers = [];
    mapMarkersByAccountId = {};
    mapRenderToken = 0;
    mapNeedsRender = false;

    @wire(getAccountVisitContext, { accountId: '$recordId' })
    wiredContext({ data, error }) {
        this.isLoading = false;
        if (error) {
            this.errorMessage = error.body?.message || 'Unable to load visit insights.';
            return;
        }
        this.context = data;
        this.errorMessage = null;
        this.loadNeighbors();
    }

    disconnectedCallback() {
        this.mapNeedsRender = false;
        this.destroyMap();
    }

    renderedCallback() {
        if (!this.showMap || this.isNeighborsLoading) {
            return;
        }
        if (!this.mapNeedsRender) {
            return;
        }
        this.mapNeedsRender = false;
        window.requestAnimationFrame(() => {
            this.renderNeighborMap();
        });
    }

    async loadNeighbors() {
        if (!this.recordId) {
            this.isNeighborsLoading = false;
            return;
        }
        this.isNeighborsLoading = true;
        try {
            const result = await getNearbyPlanTargets({
                accountId: this.recordId,
                radiusKm: null
            });
            this.searchRadiusKm = result?.searchRadiusKm ?? 25;
            const selected = new Set(this.selectedAccountIds);
            this.neighborRows = (result?.targets || []).map((row) => {
                const accountId = row.accountId;
                if (row.selectedByDefault) {
                    selected.add(accountId);
                }
                const pinKind = resolveAccountPinKind(
                    row.recordTypeDeveloperName,
                    row.recordTypeName
                );
                return {
                    ...row,
                    key: accountId,
                    pinKind,
                    accountTypeLabel: resolveAccountTypeLabel(pinKind, row.recordTypeName),
                    distanceLabel: `${row.distanceKm} km`,
                    gapLabel: `${row.actualVisits || 0}/${row.targetVisits || 0} visits`,
                    checked: selected.has(accountId),
                    disabled: row.isCenterAccount,
                    rowClass: row.isCenterAccount ? 'neighbor-row center-row' : 'neighbor-row'
                };
            });
            if (!selected.size && this.recordId) {
                selected.add(this.recordId);
            }
            this.selectedAccountIds = selected;
            this.currentNeighborPage = 1;
            this.syncNeighborChecks();
            this.mapNeedsRender = true;
        } catch (error) {
            this.neighborRows = [];
            this.currentNeighborPage = 1;
            this.mapNeedsRender = false;
            this.destroyMap();
        } finally {
            this.isNeighborsLoading = false;
        }
    }

    syncNeighborChecks() {
        this.neighborRows = (this.neighborRows || []).map((row) => ({
            ...row,
            checked: this.selectedAccountIds.has(row.accountId)
        }));
        this.updateMarkerSelection();
    }

    get hasPlanTarget() {
        return this.context?.hasPlanTarget === true;
    }

    get hasGeo() {
        return this.context?.hasGeo === true;
    }

    get canMutateVisits() {
        return this.context?.canMutateVisits === true;
    }

    get progressPercent() {
        const target = Number(this.context?.targetVisits) || 0;
        const actual = Number(this.context?.actualVisits) || 0;
        if (target <= 0) {
            return actual > 0 ? 100 : 0;
        }
        return Math.min(100, Math.round((actual / target) * 100));
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get paceSummaryLabel() {
        return `${this.context?.actualVisits || 0} of ${this.context?.targetVisits || 0} visits completed`;
    }

    get gapLabel() {
        const gap = Number(this.context?.visitGap) || 0;
        if (gap <= 0) {
            return 'Target met or exceeded';
        }
        return `${gap} visit${gap === 1 ? '' : 's'} behind`;
    }

    get frequencyBadgeClass() {
        const status = (this.context?.frequencyStatus || '').toLowerCase();
        return `freq-badge freq-${status || 'unknown'}`;
    }

    get frequencyStatusLabel() {
        return this.context?.frequencyStatus || '—';
    }

    get paceStatusClass() {
        const status = this.context?.paceStatus || 'not_applicable';
        return `pace-pill pace-${status}`;
    }

    get paceStatusLabel() {
        return PACE_LABELS[this.context?.paceStatus] || PACE_LABELS.not_applicable;
    }

    get projectionDetail() {
        const projected = Number(this.context?.projectedVisits || 0).toFixed(1);
        const percent = formatPercent(this.context?.projectedPercent);
        const elapsed = this.context?.elapsedWorkingDays || 0;
        const total = this.context?.totalWorkingDays || 0;
        return `Projected ${projected} visits (${percent} of target) · ${elapsed}/${total} working days elapsed`;
    }

    get committedDetail() {
        const committed = this.context?.committedVisits || 0;
        const target = this.context?.targetVisits || 0;
        return `${committed} committed with planned visits · target ${target}`;
    }

    get futureVisits() {
        return (this.context?.futureVisits || []).map((visit) => ({
            ...visit,
            key: visit.id,
            whenLabel: formatDateTime(visit.startDateTime)
        }));
    }

    get hasFutureVisits() {
        return this.futureVisits.length > 0;
    }

    get showMap() {
        return this.hasGeo && (this.neighborRows || []).length > 0;
    }

    get hasNeighborAccounts() {
        return (this.neighborRows || []).some((row) => !row.isCenterAccount);
    }

    get neighborsEmptyMessage() {
        return `No incomplete plan-cycle accounts with geolocation found within ${this.searchRadiusKm} km.`;
    }

    get totalNeighborPages() {
        const total = (this.neighborRows || []).length;
        return Math.max(1, Math.ceil(total / NEIGHBOR_PAGE_SIZE));
    }

    get activeNeighborPage() {
        return Math.min(Math.max(this.currentNeighborPage, 1), this.totalNeighborPages);
    }

    get paginatedNeighborRows() {
        const start = (this.activeNeighborPage - 1) * NEIGHBOR_PAGE_SIZE;
        return (this.neighborRows || []).slice(start, start + NEIGHBOR_PAGE_SIZE);
    }

    get showNeighborPagination() {
        return (this.neighborRows || []).length > NEIGHBOR_PAGE_SIZE;
    }

    get neighborRangeLabel() {
        const total = (this.neighborRows || []).length;
        if (total === 0) {
            return '';
        }
        const start = (this.activeNeighborPage - 1) * NEIGHBOR_PAGE_SIZE + 1;
        const end = Math.min(this.activeNeighborPage * NEIGHBOR_PAGE_SIZE, total);
        return `Showing ${start}–${end} of ${total}`;
    }

    get neighborPageLabel() {
        return `Page ${this.activeNeighborPage} of ${this.totalNeighborPages}`;
    }

    get isNeighborPrevDisabled() {
        return this.activeNeighborPage <= 1;
    }

    get isNeighborNextDisabled() {
        return this.activeNeighborPage >= this.totalNeighborPages;
    }

    get selectedCount() {
        return this.selectedAccountIds.size;
    }

    get bulkButtonLabel() {
        return `Create ${this.selectedCount} Draft Visit${this.selectedCount === 1 ? '' : 's'}`;
    }

    get bulkDisabled() {
        return this.isSaving || !this.canMutateVisits || this.selectedCount === 0 || !this.visitDate;
    }

    get centerAccountRow() {
        return (this.neighborRows || []).find((row) => row.isCenterAccount);
    }

    get centerPinKind() {
        return this.centerAccountRow?.pinKind || 'hcp';
    }

    get centerLegendPinClass() {
        return `legend-pin legend-pin-center legend-pin-center-${this.centerPinKind}`;
    }

    get centerLegendLabel() {
        return this.centerPinKind === 'hco' ? 'Current account (HCO)' : 'Current account (HCP)';
    }

    handleNeighborPreviousPage() {
        if (this.isNeighborPrevDisabled) {
            return;
        }
        this.currentNeighborPage -= 1;
    }

    handleNeighborNextPage() {
        if (this.isNeighborNextDisabled) {
            return;
        }
        this.currentNeighborPage += 1;
    }

    handleNeighborToggle(event) {
        const accountId = event.target.dataset.accountId;
        const checked = event.target.checked;
        const next = new Set(this.selectedAccountIds);
        if (checked) {
            next.add(accountId);
        } else if (accountId !== this.recordId) {
            next.delete(accountId);
        }
        if (!next.has(this.recordId)) {
            next.add(this.recordId);
        }
        this.selectedAccountIds = next;
        this.syncNeighborChecks();
    }

    handleVisitDateChange(event) {
        this.visitDate = event.target.value;
    }

    handleOpenVisit(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: visitId,
                objectApiName: 'Visit__c',
                actionName: 'view'
            }
        });
    }

    async handleBulkCreate() {
        if (this.bulkDisabled) {
            return;
        }
        this.isSaving = true;
        try {
            const created = await bulkCreateDraftVisits({
                accountIds: Array.from(this.selectedAccountIds),
                visitDate: this.visitDate,
                startHour: 9
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Draft visits created',
                    message: `${created.length} draft visit${created.length === 1 ? '' : 's'} added to your planner.`,
                    variant: 'success'
                })
            );
            await this.refreshData();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not create visits',
                    message: error.body?.message || error.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    async refreshData() {
        this.isLoading = true;
        try {
            this.context = await getAccountVisitContext({ accountId: this.recordId });
        } finally {
            this.isLoading = false;
        }
        await this.loadNeighbors();
    }

    destroyMap() {
        this.clearMapMarkers();
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = null;
        }
    }

    clearMapMarkers() {
        (this.mapMarkers || []).forEach((marker) => marker.remove());
        this.mapMarkers = [];
        this.mapMarkersByAccountId = {};
    }

    resolveMapCenter() {
        const centerRow = this.centerAccountRow;
        if (centerRow?.latitude != null && centerRow?.longitude != null) {
            return {
                lat: Number(centerRow.latitude),
                lng: Number(centerRow.longitude)
            };
        }
        const lat = Number(this.context?.centerLatitude);
        const lng = Number(this.context?.centerLongitude);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
            return { lat, lng };
        }
        return null;
    }

    resolveMapZoom() {
        const neighbors = (this.neighborRows || []).filter(
            (row) => !row.isCenterAccount && row.latitude != null && row.longitude != null
        );
        if (!neighbors.length) {
            return SINGLE_ACCOUNT_MAP_ZOOM;
        }

        let furthestKm = 0;
        neighbors.forEach((row) => {
            const distanceKm = Number(row.distanceKm);
            if (Number.isFinite(distanceKm) && distanceKm > furthestKm) {
                furthestKm = distanceKm;
            }
        });

        if (furthestKm < 1) {
            return SINGLE_ACCOUNT_MAP_ZOOM;
        }
        if (furthestKm < 5) {
            return 14;
        }
        if (furthestKm < 15) {
            return 13;
        }
        return 12;
    }

    applyMapViewport() {
        const center = this.resolveMapCenter();
        if (!center || !this.mapInstance) {
            return;
        }
        const zoom = this.resolveMapZoom();
        this.mapInstance.invalidateSize();
        this.mapInstance.setView([center.lat, center.lng], zoom, { animate: false });
    }

    openCenterMarkerPopup() {
        const marker = this.mapMarkersByAccountId[this.recordId];
        if (marker?.openPopup) {
            marker.openPopup();
        }
    }

    buildPopupHtml(row) {
        const typeLabel = row.accountTypeLabel || resolveAccountTypeLabel(row.pinKind, null);
        const specialty = row.specialty ? `<br/>${row.specialty}` : '';
        return `<strong>${row.name}</strong><br/><span>${typeLabel}</span>${specialty}<br/>${row.gapLabel} · ${row.distanceLabel}`;
    }

    addMapMarker(row) {
        if (!this.mapInstance || row.latitude == null || row.longitude == null) {
            return;
        }

        const leaflet = window.L;
        const isSelected = this.selectedAccountIds.has(row.accountId);
        let marker;

        if (row.isCenterAccount) {
            const pinKind = row.pinKind || 'hcp';
            const color = getPinColor(pinKind);
            marker = leaflet.circleMarker([row.latitude, row.longitude], {
                radius: 10,
                color,
                fillColor: color,
                fillOpacity: 0.95,
                weight: 2
            });
        } else {
            marker = leaflet.marker([row.latitude, row.longitude], {
                icon: createVisitPinIcon(row.pinKind || 'hcp', leaflet),
                opacity: isSelected ? 1 : 0.35
            });
        }

        marker.addTo(this.mapInstance);
        marker.bindPopup(this.buildPopupHtml(row));
        marker.accountId = row.accountId;
        this.mapMarkers.push(marker);
        this.mapMarkersByAccountId[row.accountId] = marker;
    }

    updateMarkerSelection() {
        if (!this.mapInstance) {
            return;
        }
        const selected = this.selectedAccountIds;
        this.mapMarkers.forEach((marker) => {
            if (marker.accountId && marker.setOpacity) {
                marker.setOpacity(selected.has(marker.accountId) ? 1 : 0.35);
            }
        });
    }

    async renderNeighborMap() {
        if (!this.showMap) {
            this.destroyMap();
            return;
        }

        const renderToken = ++this.mapRenderToken;
        await ensureLeaflet(this, LEAFLET);
        if (renderToken !== this.mapRenderToken) {
            return;
        }

        const container = this.template.querySelector('.map-container');
        if (!container) {
            return;
        }

        this.destroyMap();
        container.innerHTML = '';
        const mapDiv = document.createElement('div');
        mapDiv.className = 'map-canvas';
        container.appendChild(mapDiv);

        const center = this.resolveMapCenter();
        if (!center) {
            return;
        }

        const leaflet = window.L;
        const mapZoom = this.resolveMapZoom();
        this.mapInstance = leaflet.map(mapDiv, {
            zoomControl: true,
            center: [center.lat, center.lng],
            zoom: mapZoom
        });
        addOsmTileLayer(this.mapInstance, leaflet);

        (this.neighborRows || []).forEach((row) => this.addMapMarker(row));

        this.applyMapViewport();
        window.requestAnimationFrame(() => {
            this.applyMapViewport();
            window.setTimeout(() => {
                this.applyMapViewport();
                this.openCenterMarkerPopup();
            }, 120);
        });
    }
}