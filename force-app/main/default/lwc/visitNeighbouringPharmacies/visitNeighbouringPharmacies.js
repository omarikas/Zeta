import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getVisitContextInsights from '@salesforce/apex/VisitContextInsightsController.getVisitContextInsights';
import searchOpenMapPharmacies from '@salesforce/apex/VisitContextInsightsController.searchOpenMapPharmacies';
import addExternalPharmacyToRoute from '@salesforce/apex/VisitContextInsightsController.addExternalPharmacyToRoute';
import scheduleAccountPharmacyOnRoute from '@salesforce/apex/VisitNeighbouringPharmacyRouteService.scheduleAccountPharmacyOnRoute';
import { addOsmTileLayer, createVisitPinIcon, ensureLeaflet } from 'c/plannerMapPins';

const DEFAULT_PAGE_SIZE = 5;
const DEFAULT_MAP_ZOOM = 14;
const MIN_MAP_ZOOM = 12;
const MAX_MAP_ZOOM = 18;
const FILTER_ALL = 'all';
const FILTER_IN_LIST = 'inList';
const FILTER_OUT_OF_LIST = 'outOfList';
const EXTERNAL_LOAD_ERROR_MESSAGE =
    'Additional pharmacies could not be loaded right now. Your in-list results are still available.';

function formatPharmacyAddress(row) {
    const parts = [row.street, row.city, row.state, row.postalCode, row.country].filter(Boolean);
    return parts.length ? parts.join(', ') : row.city || '';
}

function decoratePharmacy(row, index, addingExternalKey) {
    const inAccountList = row.inAccountList === true;
    const key = row.accountId || row.externalId || `pharmacy-${index}`;
    const addressLabel = formatPharmacyAddress(row);
    return {
        ...row,
        rank: index + 1,
        key,
        addressLabel,
        distanceLabel: row.distanceKm != null ? `${row.distanceKm} km` : '—',
        isAccountRecord: inAccountList,
        badgeLabel: inAccountList ? 'In list' : 'Out of list',
        badgeClass: inAccountList ? 'source-badge source-badge-in-list' : 'source-badge source-badge-out-list',
        isAdding: addingExternalKey === key
    };
}

function createExternalPharmacyIcon(leaflet) {
    return leaflet.divIcon({
        className: 'map-pin-icon-shell',
        html: '<div class="map-pin-marker map-pin-marker-external" title="Pharmacy out of list"></div>',
        iconSize: [16, 16],
        iconAnchor: [8, 8],
        popupAnchor: [0, -8]
    });
}

export default class VisitNeighbouringPharmacies extends NavigationMixin(LightningElement) {
    @api visitId;

    insights;
    error;
    wiredResult;
    accountPharmacies = [];
    externalPharmacies = [];
    combinedPharmacies = [];
    listFilter = FILTER_ALL;
    currentPage = 1;
    externalLoading = false;
    externalLoadError;
    externalLoadStarted = false;
    externalLoadFailed = false;
    mapInstance;
    mapMarkers = [];
    mapRenderToken = 0;
    addingExternalKey;

    @wire(getVisitContextInsights, { visitId: '$visitId' })
    wiredInsights(result) {
        this.wiredResult = result;
        if (result.data) {
            this.insights = result.data;
            this.accountPharmacies = (result.data.neighbouringPharmacies || []).map((row) => ({
                ...row,
                inAccountList: row.inAccountList !== false
            }));
            this.error = undefined;
            this.currentPage = 1;
            this.rebuildCombinedPharmacies();
            this.scheduleMapRender();
            this.lazyLoadOpenMapPharmacies();
            return;
        }
        if (result.error) {
            this.insights = undefined;
            this.accountPharmacies = [];
            this.combinedPharmacies = [];
            this.error = result.error?.body?.message || 'Unable to load neighbouring pharmacies.';
        }
    }

    get isLoading() {
        return !this.wiredResult || this.wiredResult.loading;
    }

    get pageSize() {
        return this.insights?.pharmacyPageSize || DEFAULT_PAGE_SIZE;
    }

    get filteredPharmacies() {
        if (this.listFilter === FILTER_IN_LIST) {
            return this.combinedPharmacies.filter((row) => row.inAccountList === true);
        }
        if (this.listFilter === FILTER_OUT_OF_LIST) {
            return this.combinedPharmacies.filter((row) => row.inAccountList !== true);
        }
        return this.combinedPharmacies;
    }

    get filteredCount() {
        return this.filteredPharmacies.length;
    }

    get hasPharmacies() {
        return this.filteredPharmacies.length > 0;
    }

    get searchRadiusKm() {
        return this.insights?.searchRadiusKm || 25;
    }

    get showGeoEmpty() {
        return this.insights && !this.insights.hasGeo;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredPharmacies.length / this.pageSize));
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get showPager() {
        return this.filteredPharmacies.length > this.pageSize;
    }

    get visiblePharmacies() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.filteredPharmacies.slice(start, start + this.pageSize);
    }

    get pageStartIndex() {
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    get pageRangeLabel() {
        if (!this.hasPharmacies) {
            return '0';
        }
        const start = this.pageStartIndex;
        const end = start + this.visiblePharmacies.length - 1;
        return start === end ? `${start}` : `${start}–${end}`;
    }

    get emptyListMessage() {
        if (this.listFilter === FILTER_IN_LIST) {
            return 'No in-list pharmacies found within range of this call.';
        }
        if (this.listFilter === FILTER_OUT_OF_LIST) {
            return this.externalLoadFailed
                ? EXTERNAL_LOAD_ERROR_MESSAGE
                : 'No out-of-list pharmacies found within range of this call.';
        }
        return `No pharmacies found within ${this.searchRadiusKm} km of this call.`;
    }

    get isAllFilter() {
        return this.listFilter === FILTER_ALL;
    }

    get isInListFilter() {
        return this.listFilter === FILTER_IN_LIST;
    }

    get isOutListFilter() {
        return this.listFilter === FILTER_OUT_OF_LIST;
    }

    get allFilterClass() {
        return this.listFilter === FILTER_ALL ? 'filter-btn filter-btn-active' : 'filter-btn';
    }

    get inListFilterClass() {
        return this.listFilter === FILTER_IN_LIST ? 'filter-btn filter-btn-active' : 'filter-btn';
    }

    get outListFilterClass() {
        return this.listFilter === FILTER_OUT_OF_LIST ? 'filter-btn filter-btn-active' : 'filter-btn';
    }

    renderedCallback() {
        if (this.insights?.hasGeo && !this.mapInstance) {
            this.scheduleMapRender();
        }
    }

    disconnectedCallback() {
        this.destroyMap();
    }

    rebuildCombinedPharmacies() {
        const merged = [...this.accountPharmacies, ...this.externalPharmacies];
        this.combinedPharmacies = merged.map((row, index) =>
            decoratePharmacy(row, index, this.addingExternalKey)
        );
        this.resetPagination();
    }

    resetPagination() {
        const maxPage = Math.max(1, Math.ceil(this.filteredPharmacies.length / this.pageSize));
        if (this.currentPage > maxPage) {
            this.currentPage = maxPage;
        }
    }

    handleFilterClick(event) {
        const nextFilter = event.currentTarget.dataset.filter;
        if (!nextFilter || nextFilter === this.listFilter) {
            return;
        }
        this.listFilter = nextFilter;
        this.currentPage = 1;
        this.scheduleMapRender();
    }

    async lazyLoadOpenMapPharmacies() {
        if (
            this.externalLoadStarted ||
            !this.insights?.hasGeo ||
            this.insights.centerLatitude == null ||
            this.insights.centerLongitude == null
        ) {
            return;
        }

        this.externalLoadStarted = true;
        this.externalLoading = true;
        this.externalLoadError = undefined;
        this.externalLoadFailed = false;

        const anchorsJson = JSON.stringify(
            this.accountPharmacies.map((row) => ({
                latitude: row.latitude,
                longitude: row.longitude,
                name: row.name
            }))
        );

        try {
            const externalRows = await searchOpenMapPharmacies({
                centerLat: this.insights.centerLatitude,
                centerLng: this.insights.centerLongitude,
                radiusKm: this.searchRadiusKm,
                accountPharmacyAnchorsJson: anchorsJson
            });
            this.externalPharmacies = externalRows || [];
            this.rebuildCombinedPharmacies();
            this.scheduleMapRender();
        } catch (loadError) {
            this.externalLoadFailed = true;
            this.externalLoadError = EXTERNAL_LOAD_ERROR_MESSAGE;
        } finally {
            this.externalLoading = false;
        }
    }

    scheduleMapRender() {
        if (!this.insights?.hasGeo) {
            this.destroyMap();
            return;
        }
        window.requestAnimationFrame(() => {
            window.requestAnimationFrame(() => {
                this.renderMap();
            });
        });
    }

    resolveMapCenter() {
        const lat = Number(this.insights?.centerLatitude);
        const lng = Number(this.insights?.centerLongitude);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
            return null;
        }
        if (Math.abs(lat) > 90 || Math.abs(lng) > 180) {
            return null;
        }
        return { lat, lng };
    }

    isPlottablePharmacy(pharmacy, center) {
        if (pharmacy.latitude == null || pharmacy.longitude == null) {
            return false;
        }
        const lat = Number(pharmacy.latitude);
        const lng = Number(pharmacy.longitude);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
            return false;
        }
        if (Math.abs(lat) > 90 || Math.abs(lng) > 180) {
            return false;
        }

        const distanceKm = Number(pharmacy.distanceKm);
        if (Number.isFinite(distanceKm)) {
            return distanceKm <= this.searchRadiusKm + 1;
        }

        const kmPerDegree = 111;
        const maxDelta = (this.searchRadiusKm / kmPerDegree) * 1.25;
        return (
            Math.abs(lat - center.lat) <= maxDelta &&
            Math.abs(lng - center.lng) <= maxDelta
        );
    }

    resolveMapZoom(pharmacies) {
        let nearestKm = Infinity;
        pharmacies.forEach((row) => {
            const distanceKm = Number(row.distanceKm);
            if (Number.isFinite(distanceKm) && distanceKm < nearestKm) {
                nearestKm = distanceKm;
            }
        });

        if (nearestKm < 1) {
            return 15;
        }
        if (nearestKm < 5) {
            return 14;
        }
        if (nearestKm < 15) {
            return 13;
        }
        return DEFAULT_MAP_ZOOM;
    }

    enforceMapView(center, zoom) {
        if (!this.mapInstance || !center) {
            return;
        }
        this.mapInstance.invalidateSize();
        this.mapInstance.setView([center.lat, center.lng], zoom, { animate: false });
    }

    getMapPharmacies() {
        return this.filteredPharmacies;
    }

    async renderMap() {
        if (!this.insights?.hasGeo) {
            return;
        }

        const center = this.resolveMapCenter();
        if (!center) {
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

        const mapPharmacies = this.getMapPharmacies();
        const mapZoom = this.resolveMapZoom(mapPharmacies);

        this.destroyMap();
        container.innerHTML = '';
        const mapDiv = document.createElement('div');
        mapDiv.className = 'map-canvas';
        container.appendChild(mapDiv);

        const leaflet = window.L;
        this.mapInstance = leaflet.map(mapDiv, {
            zoomControl: true,
            center: [center.lat, center.lng],
            zoom: mapZoom,
            minZoom: MIN_MAP_ZOOM,
            maxZoom: MAX_MAP_ZOOM,
            worldCopyJump: false
        });
        addOsmTileLayer(this.mapInstance, leaflet);

        const centerMarker = leaflet.circleMarker([center.lat, center.lng], {
            radius: 11,
            color: '#0176d3',
            fillColor: '#0176d3',
            fillOpacity: 0.95,
            weight: 2
        });
        centerMarker.addTo(this.mapInstance);
        centerMarker.bindPopup(
            `<strong>${this.insights.centerAccountName || 'Call location'}</strong><br/><span>Current visit account</span>`
        );
        this.mapMarkers.push(centerMarker);

        mapPharmacies.forEach((pharmacy) => {
            if (!this.isPlottablePharmacy(pharmacy, center)) {
                return;
            }
            const lat = Number(pharmacy.latitude);
            const lng = Number(pharmacy.longitude);
            const inAccountList = pharmacy.inAccountList === true;
            const marker = inAccountList
                ? leaflet.marker([lat, lng], {
                      icon: createVisitPinIcon('hco', leaflet)
                  })
                : leaflet.marker([lat, lng], {
                      icon: createExternalPharmacyIcon(leaflet)
                  });
            marker.addTo(this.mapInstance);
            const sourceLabel = inAccountList ? 'In list' : 'Out of list';
            marker.bindPopup(
                `<strong>${pharmacy.name}</strong><br/>${pharmacy.addressLabel || pharmacy.city || ''}<br/>${pharmacy.distanceLabel}<br/><em>${sourceLabel}</em>`
            );
            marker.accountId = pharmacy.accountId;
            this.mapMarkers.push(marker);
        });

        this.enforceMapView(center, mapZoom);
        window.setTimeout(() => this.enforceMapView(center, mapZoom), 120);
        window.setTimeout(() => this.enforceMapView(center, mapZoom), 400);
    }

    destroyMap() {
        this.mapMarkers = [];
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = null;
        }
    }

    handlePreviousPage() {
        if (!this.isFirstPage) {
            this.currentPage -= 1;
        }
    }

    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage += 1;
        }
    }

    handleOpenPharmacy(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId || !this.visitId) {
            return;
        }
        this.scheduleInListPharmacy(accountId);
    }

    async scheduleInListPharmacy(pharmacyAccountId) {
        if (this.addingExternalKey) {
            return;
        }
        this.addingExternalKey = pharmacyAccountId;
        this.rebuildCombinedPharmacies();
        try {
            const result = await scheduleAccountPharmacyOnRoute({
                currentVisitId: this.visitId,
                pharmacyAccountId
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Visit scheduled',
                    message: `${result.accountName} was added to your route after this visit.`,
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredResult);
            this.rebuildCombinedPharmacies();
            this.scheduleMapRender();
        } catch (scheduleError) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to schedule pharmacy visit',
                    message:
                        scheduleError?.body?.message ||
                        'The pharmacy visit could not be scheduled. Try again.',
                    variant: 'error'
                })
            );
        } finally {
            this.addingExternalKey = undefined;
            this.rebuildCombinedPharmacies();
        }
    }

    isAddingExternal(pharmacyKey) {
        return this.addingExternalKey === pharmacyKey;
    }

    async handleAddExternalPharmacy(event) {
        const button = event.currentTarget;
        const pharmacyKey = button.dataset.key;
        const externalId = button.dataset.externalId;
        const name = button.dataset.name;
        const street = button.dataset.street;
        const city = button.dataset.city;
        const state = button.dataset.state;
        const postalCode = button.dataset.postalCode;
        const country = button.dataset.country;
        const phone = button.dataset.phone;
        const latitude = button.dataset.latitude ? Number(button.dataset.latitude) : null;
        const longitude = button.dataset.longitude ? Number(button.dataset.longitude) : null;

        if (!this.visitId || !externalId || !name || latitude == null || longitude == null) {
            return;
        }
        if (this.addingExternalKey) {
            return;
        }

        this.addingExternalKey = pharmacyKey;
        this.rebuildCombinedPharmacies();
        try {
            const result = await addExternalPharmacyToRoute({
                currentVisitId: this.visitId,
                externalId,
                name,
                street,
                city,
                state,
                postalCode,
                country,
                phone,
                latitude,
                longitude
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: result.createdAccount ? 'Pharmacy added to your list' : 'Visit scheduled',
                    message: `${result.accountName} was added to your route after this visit.`,
                    variant: 'success'
                })
            );

            this.externalPharmacies = this.externalPharmacies.filter(
                (row) => row.externalId !== externalId
            );
            await refreshApex(this.wiredResult);
            this.rebuildCombinedPharmacies();
            this.scheduleMapRender();
        } catch (addError) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to add pharmacy',
                    message:
                        addError?.body?.message ||
                        'The pharmacy could not be added to your route. Try again.',
                    variant: 'error'
                })
            );
        } finally {
            this.addingExternalKey = undefined;
            this.rebuildCombinedPharmacies();
        }
    }
}