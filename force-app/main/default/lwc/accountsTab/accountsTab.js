import { LightningElement, track } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getAccountsTabPage from '@salesforce/apex/PlannerMobileRestService.getAccountsTabPage';
import getAccountsTabMapPoints from '@salesforce/apex/PlannerMobileRestService.getAccountsTabMapPoints';
import getAccountsTabRecordTypeOptions from '@salesforce/apex/PlannerMobileRestService.getAccountsTabRecordTypeOptions';
import {
    addOsmTileLayer,
    ensureLeaflet,
    HCO_PIN_SVG,
    HCP_PIN_SVG,
    resolveAccountPinKind
} from 'c/plannerMapPins';
import {
    loadAccountCollections,
    getCollectionAccountIds
} from 'c/plannerAccountCollections';
import {
    getAccountsTabBusinessUnits,
    putAccountsTabBusinessUnits,
    getAccountsTabCache,
    putAccountsTabCache,
    getUserAccountsTabKey,
    getAccountsTabRecordTypeOptionsCache,
    putAccountsTabRecordTypeOptionsCache
} from 'c/clmOfflineStore';

const FILTER_ALL = 'All';
const SCOPE_BOTH = 'both';
const SCOPE_IN = 'in';
const SCOPE_OUT = 'out';
const LIST_MODE_ALL = 'all';
const LIST_MODE_COLLECTION = 'collection';
const SORT_AGENTFORCE = 'agentforceScore';
const SORT_CLASSIFICATION = 'classification';
const SORT_NAME = 'name';
const PAGE_SIZE = 10;
const MAP_PAGE_SIZE = 5;
const SEARCH_DEBOUNCE_MS = 350;
const COMPACT_BREAKPOINT_PX = 1024;

const SCOPE_OPTIONS = [
    { label: 'All Accounts', value: SCOPE_BOTH },
    { label: 'In Plan Cycle', value: SCOPE_IN },
    { label: 'Out of Plan Cycle', value: SCOPE_OUT }
];

const SORT_OPTIONS = [
    { label: 'Agentforce Score', value: SORT_AGENTFORCE },
    { label: 'Classification', value: SORT_CLASSIFICATION },
    { label: 'Name', value: SORT_NAME }
];

const RISK_PIN_COLORS = {
    High: '#ba0517',
    Med: '#fe9339',
    Low: '#2e844a'
};

const RISK_DOT_CLASS = {
    High: 'map-list-risk-high',
    Med: 'map-list-risk-med',
    Low: 'map-list-risk-low'
};

export default class AccountsTab extends LightningElement {
  @track rows = [];
  @track mapRows = [];
  @track summary = {
    totalCount: 0,
    inPlanCount: 0,
    outPlanCount: 0,
    behindPaceCount: 0,
    monthLabel: ''
  };
  @track recordTypeCounts = [];

  isLoading = true;
  errorMessage;
  viewMode = 'list';
  scope = SCOPE_BOTH;
  searchTerm = '';
  recordType = FILTER_ALL;
  classification = FILTER_ALL;
  sortBy = SORT_AGENTFORCE;
  sortDirection = 'desc';
  currentPage = 1;
  mapCurrentPage = 1;
  mapEligibleCount = 0;
  isNarrowViewport = false;
  sidebarOpen = true;
  sidebarPanel = 'lists';
  listViewMode = LIST_MODE_ALL;
  selectedCollectionId = null;
  accountCollections = [];

  recordTypeOptions = [{ label: 'All Record Types', value: FILTER_ALL }];
  specialtyOptions = [];
  classificationOptions = [{ label: 'All Classifications', value: FILTER_ALL }];
  scopeOptions = SCOPE_OPTIONS;
  sortOptions = SORT_OPTIONS;

  mapInstance;
  mapMarkers = [];
  markersByAccountId = {};
  mapRenderToken = 0;
  loadRequestToken = 0;
  selectedAccountId;

  searchDebounce;
  syncStatus = 'idle';
  hasCachedData = false;
  _connectivityBound = false;
  _onOnline;
  _onOffline;

  connectedCallback() {
    this.bindConnectivityListeners();
    this.updateViewportMode();
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', this.handleResize);
    }
    this.loadPlannerCollections();
    this.loadFilterOptions();
    this.reloadData(true);
  }

  disconnectedCallback() {
    this.destroyMap();
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
    }
    if (this._onOnline) {
      window.removeEventListener('online', this._onOnline);
    }
    if (this._onOffline) {
      window.removeEventListener('offline', this._onOffline);
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('resize', this.handleResize);
    }
  }

  handleResize = () => {
    this.updateViewportMode();
    if (this.isMapView && this.mapInstance) {
      setTimeout(() => this.mapInstance?.invalidateSize(), 100);
    }
  };

  updateViewportMode() {
    if (typeof window === 'undefined') {
      return;
    }
    this.isNarrowViewport = window.innerWidth <= COMPACT_BREAKPOINT_PX;
    if (this.isCompactView && window.innerWidth <= 640) {
      this.sidebarOpen = false;
    }
  }

  bindConnectivityListeners() {
    if (this._connectivityBound || typeof window === 'undefined') {
      return;
    }
    this._connectivityBound = true;
    this._onOnline = () => {
      this.loadPlannerCollections();
      this.reloadData(true);
    };
    this._onOffline = () => {
      this.syncStatus = 'offline';
      if (!this.hasCachedData) {
        this.errorMessage = 'You are offline. Connect to load accounts.';
      }
    };
    window.addEventListener('online', this._onOnline);
    window.addEventListener('offline', this._onOffline);
  }

  get isCompactView() {
    return this.isNarrowViewport;
  }

  get isListView() {
    return this.viewMode === 'list';
  }

  get isMapView() {
    return this.viewMode === 'map';
  }

  get listViewToggleClass() {
    return `view-toggle-btn${this.isListView ? ' view-toggle-btn-active' : ''}`;
  }

  get mapViewToggleClass() {
    return `view-toggle-btn${this.isMapView ? ' view-toggle-btn-active' : ''}`;
  }

  get scopeOptionList() {
    return this.withSelection(this.scopeOptions, this.scope);
  }

  get recordTypeOptionList() {
    return this.withSelection(this.recordTypeOptions, this.recordType);
  }

  get classificationOptionList() {
    return this.withSelection(this.classificationOptions, this.classification);
  }

  get sortOptionList() {
    return this.withSelection(this.sortOptions, this.sortBy);
  }

  withSelection(options, current) {
    return (options || []).map((option) => ({
      ...option,
      isSelected: option?.value === current
    }));
  }

  get toolbarClass() {
    return `accounts-toolbar${this.isCompactView ? ' accounts-toolbar-compact' : ''}`;
  }

  get summaryCardsClass() {
    return `summary-cards${this.isCompactView ? ' summary-cards-compact' : ''}`;
  }

  get sidebarClass() {
    const classes = ['oce-sidebar'];
    if (this.sidebarOpen) {
      classes.push('oce-sidebar-open');
    }
    return classes.join(' ');
  }

  get isListsPanel() {
    return this.sidebarPanel === 'lists';
  }

  get isFiltersPanel() {
    return this.sidebarPanel === 'filters';
  }

  get listsSegmentClass() {
    return `oce-segment-btn${this.isListsPanel ? ' oce-segment-btn-active' : ''}`;
  }

  get filtersSegmentClass() {
    return `oce-segment-btn${this.isFiltersPanel ? ' oce-segment-btn-active' : ''}`;
  }

  get listNavItems() {
    return [
      {
        value: SCOPE_BOTH,
        label: `All (${this.summary.totalCount || 0})`,
        buttonClass: this.navButtonClass(
          this.listViewMode === LIST_MODE_ALL && this.scope === SCOPE_BOTH
        )
      },
      {
        value: SCOPE_IN,
        label: `In Plan Cycle (${this.summary.inPlanCount || 0})`,
        buttonClass: this.navButtonClass(
          this.listViewMode === LIST_MODE_ALL && this.scope === SCOPE_IN
        )
      },
      {
        value: SCOPE_OUT,
        label: `Out of Plan Cycle (${this.summary.outPlanCount || 0})`,
        buttonClass: this.navButtonClass(
          this.listViewMode === LIST_MODE_ALL && this.scope === SCOPE_OUT
        )
      }
    ];
  }

  get hasPlannerCollections() {
    return (this.accountCollections || []).length > 0;
  }

  get collectionChips() {
    return (this.accountCollections || []).map((collection) => ({
      id: collection.id,
      label: `${collection.name} (${getCollectionAccountIds(collection).length})`,
      title: collection.name,
      chipClass: `collection-chip${
        this.selectedCollectionId === collection.id ? ' collection-chip-active' : ''
      }`
    }));
  }

  get allAccountsChipClass() {
    return `collection-chip collection-chip-all${
      this.listViewMode === LIST_MODE_ALL ? ' collection-chip-active' : ''
    }`;
  }

  get selectedCollectionAccountIds() {
    if (this.listViewMode !== LIST_MODE_COLLECTION || !this.selectedCollectionId) {
      return [];
    }
    const collection = (this.accountCollections || []).find(
      (item) => item.id === this.selectedCollectionId
    );
    return getCollectionAccountIds(collection);
  }

  get countLabel() {
    if (this.listViewMode === LIST_MODE_COLLECTION) {
      const collection = (this.accountCollections || []).find(
        (item) => item.id === this.selectedCollectionId
      );
      const listCount = this.summary.totalCount || 0;
      const collectionSize = getCollectionAccountIds(collection).length;
      if (collectionSize > listCount) {
        return `${listCount} of ${collectionSize} in “${collection?.name || 'list'}”`;
      }
      return `${listCount} in “${collection?.name || 'list'}”`;
    }
    const total = this.summary.totalCount || 0;
    const scopeLabel =
      this.scope === SCOPE_IN
        ? 'in plan cycle'
        : this.scope === SCOPE_OUT
          ? 'out of plan cycle'
          : 'accounts';
    return `${total} ${scopeLabel}`;
  }

  get typeNavItems() {
    return (this.recordTypeCounts || []).map((item) => ({
      value: item.value,
      label: `${item.label} (${item.count || 0})`,
      buttonClass: this.navButtonClass(this.recordType === item.value)
    }));
  }

  get mapListItems() {
    return (this.mapRows || []).map((row) => {
      const pinKind = resolveAccountPinKind(
        row.recordTypeDeveloperName,
        row.recordTypeName
      );
      const isSelected = row.accountId === this.selectedAccountId;
      return {
        ...row,
        pinKind,
        typeLabel: pinKind === 'hco' ? 'HCO' : 'HCP',
        riskDotClass: RISK_DOT_CLASS[row.agentforceRisk] || RISK_DOT_CLASS.Low,
        itemClass: `map-account-item${isSelected ? ' map-account-item-selected' : ''}`,
        subtitle: [row.accountSubtype || row.recordTypeName, row.city].filter(Boolean).join(' · ') || '—',
        hasBusinessUnits: Array.isArray(row.businessUnits) && row.businessUnits.length > 0,
        businessUnitLabel: row.businessUnitLabel || ''
      };
    });
  }

  get mapListCountLabel() {
    const geocoded = this.mapEligibleCount || 0;
    const matched = this.summary.totalCount || 0;
    if (geocoded === 0) {
      return matched > 0 ? `0 on map (${matched} matched)` : '0 on map';
    }
    const start = (this.mapCurrentPage - 1) * MAP_PAGE_SIZE + 1;
    const end = Math.min(this.mapCurrentPage * MAP_PAGE_SIZE, geocoded);
    let label = `Showing ${start}–${end} of ${geocoded}`;
    if (geocoded < matched) {
      label += ` (${matched} matched)`;
    }
    return label;
  }

  get showMapPagination() {
    return (this.mapEligibleCount || 0) > MAP_PAGE_SIZE;
  }

  get mapTotalPages() {
    return Math.max(1, Math.ceil((this.mapEligibleCount || 0) / MAP_PAGE_SIZE));
  }

  get mapHasPreviousPage() {
    return this.mapCurrentPage > 1;
  }

  get mapHasNextPage() {
    return this.mapCurrentPage < this.mapTotalPages;
  }

  get isMapPrevDisabled() {
    return !this.mapHasPreviousPage || this.isLoading;
  }

  get isMapNextDisabled() {
    return !this.mapHasNextPage || this.isLoading;
  }

  get mapRangeLabel() {
    const total = this.mapEligibleCount || 0;
    if (total === 0) {
      return '';
    }
    const start = (this.mapCurrentPage - 1) * MAP_PAGE_SIZE + 1;
    const end = Math.min(this.mapCurrentPage * MAP_PAGE_SIZE, total);
    return `Showing ${start}–${end} of ${total}`;
  }

  get mapPageLabel() {
    return `Page ${this.mapCurrentPage} of ${this.mapTotalPages}`;
  }

  get hasMapListItems() {
    return (this.mapRows || []).length > 0;
  }

  navButtonClass(isActive) {
    return `oce-nav-btn${isActive ? ' oce-nav-btn-active' : ''}`;
  }

  get showPagination() {
    return this.isListView && (this.summary.totalCount || 0) > PAGE_SIZE;
  }

  get totalPages() {
    return Math.max(1, Math.ceil((this.summary.totalCount || 0) / PAGE_SIZE));
  }

  get hasPreviousPage() {
    return this.currentPage > 1;
  }

  get hasNextPage() {
    return this.currentPage < this.totalPages;
  }

  get isPrevDisabled() {
    return !this.hasPreviousPage || this.isLoading;
  }

  get isNextDisabled() {
    return !this.hasNextPage || this.isLoading;
  }

  get rangeLabel() {
    const total = this.summary.totalCount || 0;
    if (total === 0) {
      return '';
    }
    const start = (this.currentPage - 1) * PAGE_SIZE + 1;
    const end = Math.min(this.currentPage * PAGE_SIZE, total);
    return `Showing ${start}–${end} of ${total}`;
  }

  get pageLabel() {
    return `Page ${this.currentPage} of ${this.totalPages}`;
  }

  get showEmptyState() {
    return !this.isLoading && !this.errorMessage && (this.rows || []).length === 0;
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

  get cacheBaseKey() {
    return getUserAccountsTabKey(USER_ID);
  }

  filterSignature() {
    return [
      this.scope,
      (this.searchTerm || '').trim().toLowerCase(),
      this.recordType,
      this.classification,
      this.sortBy,
      this.sortDirection
    ].join('~');
  }

  summaryCacheKey() {
    return `${this.cacheBaseKey}.summary.${this.filterSignature()}`;
  }

  listPageCacheKey() {
    return `${this.cacheBaseKey}.list.${this.filterSignature()}.${this.currentPage}`;
  }

  mapPageCacheKey() {
    return `${this.cacheBaseKey}.map.${this.filterSignature()}.${this.mapCurrentPage}`;
  }

  async loadFilterOptions() {
    try {
      const cached = await getAccountsTabRecordTypeOptionsCache(USER_ID);
      if (cached?.length) {
        this.recordTypeOptions = this.normalizeComboboxOptions(cached, this.recordTypeOptions);
      }
      if (typeof navigator === 'undefined' || navigator.onLine !== false) {
        if (!cached?.length) {
          const recordTypes = await getAccountsTabRecordTypeOptions();
          await putAccountsTabRecordTypeOptionsCache(USER_ID, recordTypes);
          this.recordTypeOptions = this.normalizeComboboxOptions(recordTypes, this.recordTypeOptions);
        }
      }
      this.classificationOptions = [
        { label: 'All Classifications', value: FILTER_ALL },
        { label: 'A', value: 'A' },
        { label: 'B', value: 'B' },
        { label: 'C', value: 'C' }
      ];
    } catch (error) {
      // Filters are optional; list still works with defaults.
    }
  }

  loadPlannerCollections() {
    this.accountCollections = loadAccountCollections(USER_ID);
    if (
      this.selectedCollectionId &&
      !this.accountCollections.some((item) => item.id === this.selectedCollectionId)
    ) {
      this.selectedCollectionId = null;
      this.listViewMode = LIST_MODE_ALL;
    }
  }

  normalizeComboboxOptions(options, fallback = []) {
    const source = Array.isArray(options) && options.length ? options : fallback;
    return source
      .map((option) => ({
        label: option?.label,
        value: option?.value
      }))
      .filter((option) => option.label && option.value);
  }

  readInputValue(event) {
    if (event?.detail?.value != null) {
      return event.detail.value;
    }
    if (event?.target?.value != null) {
      return event.target.value;
    }
    return '';
  }

  buildApexParams(mapMode = false) {
    const accountIds = this.selectedCollectionAccountIds;
    const trimmedSearch = (this.searchTerm || '').trim();
    const pageSize = mapMode ? MAP_PAGE_SIZE : PAGE_SIZE;
    const page = mapMode ? this.mapCurrentPage : this.currentPage;
    return {
      scope: this.scope,
      searchTerm: trimmedSearch || null,
      recordTypeDeveloperName: this.recordType,
      classification:
        this.classification === FILTER_ALL ? null : this.classification,
      sortBy: this.sortBy,
      sortDirection: this.sortDirection,
      offset: (page - 1) * pageSize,
      pageSize,
      monthStart: null,
      contextUserId: null,
      accountIds: accountIds.length ? accountIds : null
    };
  }

  applyPageSummary(result) {
    this.summary = {
      totalCount: result?.totalCount || 0,
      inPlanCount: result?.inPlanCount || 0,
      outPlanCount: result?.outPlanCount || 0,
      behindPaceCount: result?.behindPaceCount || 0,
      monthLabel: result?.monthLabel || ''
    };
    this.recordTypeCounts = result?.recordTypeCounts || [];
    this.mapEligibleCount = result?.mapEligibleCount ?? this.mapEligibleCount;
    const maxPage = Math.max(
      1,
      Math.ceil((this.summary.totalCount || 0) / PAGE_SIZE)
    );
    if (this.currentPage > maxPage) {
      this.currentPage = maxPage;
    }
    const maxMapPage = Math.max(
      1,
      Math.ceil((this.mapEligibleCount || 0) / MAP_PAGE_SIZE)
    );
    if (this.mapCurrentPage > maxMapPage) {
      this.mapCurrentPage = maxMapPage;
    }
  }

  reloadData(reset) {
    if (reset) {
      this.currentPage = 1;
      this.mapCurrentPage = 1;
    }
    if (this.isMapView) {
      return this.refreshMapView();
    }
    return this.loadPage();
  }

  async loadPage() {
    const token = ++this.loadRequestToken;
    this.isLoading = true;
    this.errorMessage = null;
    this.rows = [];

    try {
      const cached = await this.readPageCache();
      if (token !== this.loadRequestToken) {
        return;
      }
      if (cached.summary?.summary || cached.page?.rows?.length) {
        if (cached.summary?.summary) {
          this.applyPageSummary(cached.summary.summary);
          this.recordTypeCounts = cached.summary.recordTypeCounts || [];
        }
        if (cached.page?.rows?.length) {
          this.rows = cached.page.rows.map((row) => this.mapRow(row));
        }
        this.hasCachedData = true;
        this.syncStatus = 'cached';
      }
    } catch (_cacheError) {
      // Cache read is best-effort; continue to the network call.
    }

    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      if (!this.hasCachedData) {
        this.errorMessage = 'You are offline. Connect to load accounts.';
      }
      this.syncStatus = 'offline';
      if (token === this.loadRequestToken) {
        this.isLoading = false;
      }
      return;
    }

    this.syncStatus = 'updating';
    try {
      const result = await getAccountsTabPage(this.buildApexParams(false));
      if (token !== this.loadRequestToken) {
        return;
      }
      const mappedRows = (result?.rows || []).map((row) => this.mapRow(row));
      this.rows = mappedRows;
      await this.cacheBusinessUnits(mappedRows);
      this.applyPageSummary(result);
      await this.writePageCaches(result?.rows || []);
      this.hasCachedData = true;
      this.errorMessage = null;
      this.syncStatus = 'idle';
    } catch (error) {
      if (token !== this.loadRequestToken) {
        return;
      }
      if (error?.name === 'AbortError') {
        return;
      }
      if (this.rows.length === 0) {
        const cachedRows = await this.loadCachedPageRows();
        if (cachedRows.length) {
          this.rows = cachedRows;
          this.hasCachedData = true;
          this.syncStatus = 'cached';
          this.errorMessage = null;
          return;
        }
      }
      this.syncStatus = 'offline';
      if (!this.hasCachedData) {
        this.errorMessage = this.isConnectivityError(error)
          ? 'You are offline. Connect to load accounts.'
          : this.reduceError(error);
      }
    } finally {
      if (token === this.loadRequestToken) {
        this.isLoading = false;
      }
    }
  }

  async readPageCache() {
    const [summary, page] = await Promise.all([
      getAccountsTabCache(this.summaryCacheKey()),
      getAccountsTabCache(this.listPageCacheKey())
    ]);
    return { summary, page };
  }

  async writePageCaches(rawRows) {
    await putAccountsTabCache(this.summaryCacheKey(), {
      summary: this.summary,
      recordTypeCounts: this.recordTypeCounts,
      mapEligibleCount: this.mapEligibleCount
    });
    await putAccountsTabCache(this.listPageCacheKey(), { rows: rawRows || [] });
  }

  async refreshMapView() {
    const token = ++this.mapRenderToken;
    this.isLoading = true;
    this.errorMessage = null;
    this.selectedAccountId = null;

    try {
      const cached = await this.readMapCache();
      if (token !== this.mapRenderToken) {
        return;
      }
      if (cached.summary?.summary || cached.mapPage?.mapRows?.length) {
        if (cached.summary?.summary) {
          this.applyPageSummary(cached.summary.summary);
          this.recordTypeCounts = cached.summary.recordTypeCounts || [];
        }
        if (cached.mapPage?.mapRows?.length) {
          this.mapRows = cached.mapPage.mapRows.map((row) => this.mapRow(row));
          this.mapEligibleCount =
            cached.mapPage.mapEligibleCount ?? this.mapEligibleCount;
          this.hasCachedData = true;
          this.syncStatus = 'cached';
          this.safelyDrawMapMarkers(token);
        }
      }
    } catch (_cacheError) {
      // Cache read is best-effort; continue to the network call.
    }

    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      if (!this.hasCachedData) {
        this.errorMessage = 'You are offline. Connect to load accounts.';
      }
      this.syncStatus = 'offline';
      if (token === this.mapRenderToken) {
        this.isLoading = false;
      }
      return;
    }

    this.syncStatus = 'updating';
    try {
      const summaryParams = {
        ...this.buildApexParams(false),
        offset: 0,
        pageSize: 1
      };
      const mapParams = this.buildApexParams(true);
      const [pageResult, mapPage] = await Promise.all([
        getAccountsTabPage(summaryParams),
        getAccountsTabMapPoints(mapParams)
      ]);
      if (token !== this.mapRenderToken) {
        return;
      }
      this.applyPageSummary(pageResult);
      this.mapEligibleCount = mapPage?.mapEligibleCount || 0;
      this.mapRows = (mapPage?.rows || []).map((row) => this.mapRow(row));
      await this.drawMapMarkers(this.mapRows, token);
      await this.writeMapCaches(pageResult, mapPage);
      this.hasCachedData = true;
      this.errorMessage = null;
      this.syncStatus = 'idle';
    } catch (error) {
      if (token !== this.mapRenderToken) {
        return;
      }
      if (error?.name === 'AbortError') {
        return;
      }
      this.syncStatus = 'offline';
      if (!this.hasCachedData) {
        this.errorMessage = this.isConnectivityError(error)
          ? 'You are offline. Connect to load accounts.'
          : this.reduceError(error);
      }
    } finally {
      if (token === this.mapRenderToken) {
        this.isLoading = false;
      }
    }
  }

  async readMapCache() {
    const [summary, mapPage] = await Promise.all([
      getAccountsTabCache(this.summaryCacheKey()),
      getAccountsTabCache(this.mapPageCacheKey())
    ]);
    return { summary, mapPage };
  }

  async writeMapCaches(pageResult, mapPage) {
    await putAccountsTabCache(this.summaryCacheKey(), {
      summary: this.summary,
      recordTypeCounts: this.recordTypeCounts,
      mapEligibleCount: this.mapEligibleCount
    });
    await putAccountsTabCache(this.mapPageCacheKey(), {
      mapRows: mapPage?.rows || [],
      mapEligibleCount: this.mapEligibleCount
    });
  }

  async safelyDrawMapMarkers(token) {
    try {
      await this.drawMapMarkers(this.mapRows, token);
    } catch (_mapError) {
      // Map tiles may be unavailable offline; the list still works.
    }
  }

  mapRow(row, businessUnitOverride) {
    const target = row.targetVisits;
    const actual = row.actualVisits || 0;
    const planned = row.plannedVisits || 0;
    const hasTarget = target != null;
    const businessUnits =
      businessUnitOverride ||
      (Array.isArray(row.businessUnits) ? row.businessUnits : []);
    const businessUnitLabel =
      row.businessUnitLabel ||
      businessUnits
        .map((link) => link.chipLabel || link.businessUnitName)
        .filter(Boolean)
        .join(', ');
    return {
      ...row,
      businessUnits,
      hasBusinessUnits: businessUnits.length > 0,
      businessUnitLabel,
      reachPercentDisplay:
        row.reachPercent != null ? `${Math.round(Number(row.reachPercent))}%` : '—',
      projectedPercentDisplay:
        row.projectedPercent != null
          ? `${Math.round(Number(row.projectedPercent))}%`
          : '—',
      agentforceScoreDisplay:
        row.agentforceScore != null ? Number(row.agentforceScore).toFixed(1) : '—',
      isKolLabel: row.isKol ? 'Yes' : 'No',
      targetLabel: row.inPlanCycle ? 'Yes' : 'No',
      callPlanLabel: hasTarget ? `${actual}/${target}` : '—',
      plannedPlanLabel: hasTarget ? `Planned ${planned}/${target}` : '—',
      targetVisits: hasTarget ? target : null,
      visitGap: hasTarget ? row.visitGap : null
    };
  }

  async cacheBusinessUnits(rows) {
    if (!rows?.length) {
      return;
    }
    const byAccount = {};
    rows.forEach((row) => {
      if (row.accountId && row.businessUnits?.length) {
        byAccount[row.accountId] = row.businessUnits;
      }
    });
    if (Object.keys(byAccount).length) {
      await putAccountsTabBusinessUnits(USER_ID, byAccount);
    }
  }

  async loadCachedPageRows() {
    const byAccount = await getAccountsTabBusinessUnits(USER_ID);
    if (!Object.keys(byAccount).length) {
      return [];
    }
    return Object.entries(byAccount).map(([accountId, businessUnits]) =>
      this.mapRow(
        {
          accountId,
          accountName: businessUnits[0]?.accountName || 'Account',
          businessUnits
        },
        businessUnits
      )
    );
  }

  handleShowList() {
    this.viewMode = 'list';
    this.destroyMap();
    if (!this.rows.length) {
      this.reloadData(true);
    }
  }

  async handleShowMap() {
    this.viewMode = 'map';
    await this.refreshMapView();
  }

  handleScopeChange(event) {
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.scope = this.readInputValue(event);
    this.reloadData(true);
  }

  handleRecordTypeChange(event) {
    this.recordType = this.readInputValue(event);
    this.reloadData(true);
  }

  handleClassificationChange(event) {
    this.classification = this.readInputValue(event);
    this.reloadData(true);
  }

  handleSortChange(event) {
    this.sortBy = this.readInputValue(event);
    this.sortDirection = this.sortBy === SORT_NAME ? 'asc' : 'desc';
    this.reloadData(true);
  }

  handleOceSortToggle() {
    if (this.sortBy !== SORT_NAME) {
      this.sortBy = SORT_NAME;
      this.sortDirection = 'asc';
    } else {
      this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
    }
    this.reloadData(true);
  }

  handleSearchChange(event) {
    this.applySearch(this.readInputValue(event));
  }

  handleSearchKeyUp(event) {
    this.scheduleSearch(this.readInputValue(event));
  }

  applySearch(value) {
    this.searchTerm = value ?? '';
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = null;
    }
    this.reloadData(true);
  }

  scheduleSearch(value) {
    this.searchTerm = value ?? '';
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout(() => {
      this.searchDebounce = null;
      this.reloadData(true);
    }, SEARCH_DEBOUNCE_MS);
  }

  handleRefresh() {
    this.loadPlannerCollections();
    this.reloadData(true);
  }

  handleShowAllAccounts() {
    this.loadPlannerCollections();
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.reloadData(true);
  }

  handleSelectCollection(event) {
    this.loadPlannerCollections();
    const collectionId = event.currentTarget.dataset.collectionId;
    const collection = (this.accountCollections || []).find((item) => item.id === collectionId);
    if (!collection) {
      return;
    }
    this.selectedCollectionId = collectionId;
    this.listViewMode = LIST_MODE_COLLECTION;
    this.reloadData(true);
  }

  handlePreviousPage() {
    if (!this.hasPreviousPage || this.isLoading) {
      return;
    }
    this.currentPage -= 1;
    this.loadPage();
  }

  handleNextPage() {
    if (!this.hasNextPage || this.isLoading) {
      return;
    }
    this.currentPage += 1;
    this.loadPage();
  }

  handleMapPreviousPage() {
    if (!this.mapHasPreviousPage || this.isLoading) {
      return;
    }
    this.mapCurrentPage -= 1;
    this.refreshMapView();
  }

  handleMapNextPage() {
    if (!this.mapHasNextPage || this.isLoading) {
      return;
    }
    this.mapCurrentPage += 1;
    this.refreshMapView();
  }

  handleToggleFilters() {
    if (this.sidebarOpen && this.sidebarPanel === 'filters') {
      this.sidebarOpen = false;
      return;
    }
    this.sidebarPanel = 'filters';
    this.sidebarOpen = true;
  }

  handleToggleSidebar() {
    this.sidebarOpen = !this.sidebarOpen;
  }

  handleShowListsPanel() {
    this.loadPlannerCollections();
    this.sidebarPanel = 'lists';
    this.sidebarOpen = true;
  }

  handleShowFiltersPanel() {
    this.sidebarPanel = 'filters';
    this.sidebarOpen = true;
  }

  handleListNavSelect(event) {
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.scope = event.currentTarget.dataset.value;
    this.reloadData(true);
  }

  handleTypeNavSelect(event) {
    this.recordType = event.currentTarget.dataset.value;
    this.reloadData(true);
  }

  handleMapListSelect(event) {
    const accountId = event.currentTarget.dataset.accountId;
    if (!accountId) {
      return;
    }
    this.selectedAccountId = accountId;
    const row = (this.mapRows || []).find((item) => item.accountId === accountId);
    if (row?.latitude != null && row?.longitude != null) {
      this.flyToAccount(row.latitude, row.longitude, accountId);
    }
  }

  handleMapListViewAccount(event) {
    event.stopPropagation();
    const accountId = event.currentTarget.dataset.accountId;
    if (accountId) {
      this.navigateToAccount(accountId);
    }
  }

  handleOceRowAction(event) {
    const { accountId, action } = event.detail;
    if (action === 'plan') {
      this.navigateToPlanner();
      return;
    }
    if (accountId) {
      this.navigateToAccount(accountId);
    }
  }

  async waitForMapContainer() {
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const container = this.template.querySelector('.accounts-map');
      if (container) {
        return container;
      }
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }
    return null;
  }

  async ensureMapReady(leaflet, token) {
    const container = await this.waitForMapContainer();
    if (!container || token !== this.mapRenderToken) {
      return null;
    }
    if (this.mapInstance) {
      this.destroyMap();
    }
    container.innerHTML = '';
    const mapDiv = document.createElement('div');
    mapDiv.style.height = '100%';
    mapDiv.style.width = '100%';
    container.appendChild(mapDiv);
    const map = leaflet.map(mapDiv, { zoomControl: true });
    addOsmTileLayer(map, leaflet);
    this.mapInstance = map;
    return map;
  }

  buildRiskPinIcon(leaflet, row) {
    const pinKind = resolveAccountPinKind(
      row.recordTypeDeveloperName,
      row.recordTypeName
    );
    const svg = (pinKind === 'hco' ? HCO_PIN_SVG : HCP_PIN_SVG).replace(
      '<svg ',
      '<svg style="width:16px;height:16px;" '
    );
    const color = RISK_PIN_COLORS[row.agentforceRisk] || RISK_PIN_COLORS.Low;
    const safeName = String(row.accountName || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;');
    return leaflet.divIcon({
      className: 'map-pin-icon-shell',
      html: `<div style="width:30px;height:30px;border-radius:50%;background:${color};border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;" title="${safeName}">${svg}</div>`,
      iconSize: [30, 30],
      iconAnchor: [15, 15],
      popupAnchor: [0, -16]
    });
  }

  async drawMapMarkers(points, token) {
    const leaflet = await ensureLeaflet(this, LEAFLET);
    if (token !== this.mapRenderToken) {
      return;
    }
    const map = await this.ensureMapReady(leaflet, token);
    if (!map) {
      return;
    }
    this.clearMarkers();
    const bounds = [];
    this.markersByAccountId = {};
    (points || []).forEach((row) => {
      if (row.latitude == null || row.longitude == null) {
        return;
      }
      const latLng = [Number(row.latitude), Number(row.longitude)];
      bounds.push(latLng);
      const icon = this.buildRiskPinIcon(leaflet, row);
      const marker = leaflet
        .marker(latLng, { icon })
        .addTo(map)
        .bindPopup(this.buildPopupHtml(row));
      marker.on('click', () => {
        this.selectedAccountId = row.accountId;
        this.scrollMapListItemIntoView(row.accountId);
        marker.openPopup();
      });
      this.mapMarkers.push(marker);
      this.markersByAccountId[row.accountId] = marker;
    });
    if (bounds.length) {
      map.fitBounds(bounds, { padding: [30, 30], maxZoom: 14 });
    } else {
      map.setView([30.0444, 31.2357], 6);
    }
    setTimeout(() => map.invalidateSize(), 100);
  }

  flyToAccount(latitude, longitude, accountId) {
    if (!this.mapInstance) {
      return;
    }
    const lat = Number(latitude);
    const lng = Number(longitude);
    this.mapInstance.flyTo([lat, lng], 15, { duration: 0.8 });
    const marker = this.markersByAccountId[accountId];
    if (marker) {
      setTimeout(() => marker.openPopup(), 400);
    }
  }

  scrollMapListItemIntoView(accountId) {
    const listItem = this.template.querySelector(
      `[data-account-id="${accountId}"]`
    );
    if (listItem) {
      listItem.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  buildPopupHtml(row) {
    const projected =
      row.projectedPercent != null ? `${Math.round(Number(row.projectedPercent))}%` : 'N/A';
    const hasTarget = row.targetVisits != null;
    return `<strong>${row.accountName}</strong><br/>
      ${row.classification || '—'} · ${row.planCycleLabel}<br/>
      Visits: ${hasTarget ? `${row.actualVisits || 0}/${row.targetVisits}` : `${row.actualVisits || 0} (no target)`}<br/>
      Pace: ${row.paceStatusLabel || 'N/A'} · Score: ${Number(row.agentforceScore || 0).toFixed(1)}`;
  }

  get isPwaContext() {
    const p = window?.location?.pathname || '';
    return p === '/' || p.endsWith('/index.html') || p.endsWith('/accounts.html') || p.endsWith('/visits.html');
  }

  navigateToAccount(accountId) {
    if (this.isPwaContext) {
      window.location.href = `/accounts.html?accountId=${accountId}`;
      return;
    }
    const sfInstance =
      (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || '';
    if (sfInstance) {
      window.open(
        `${String(sfInstance).replace(/\/$/, '')}/lightning/r/Account/${accountId}/view`,
        '_blank'
      );
    } else {
      window.open(`/lightning/r/Account/${accountId}/view`, '_self');
    }
  }

  navigateToPlanner() {
    if (this.isPwaContext) {
      window.location.href = '/index.html';
      return;
    }
    const sfInstance =
      (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || '';
    if (sfInstance) {
      window.open(
        `${String(sfInstance).replace(/\/$/, '')}/lightning/n/Field_Rep_Planner`,
        '_blank'
      );
    } else {
      window.open('/lightning/n/Field_Rep_Planner', '_self');
    }
  }

  clearMarkers() {
    if (!this.mapMarkers?.length || !this.mapInstance) {
      this.mapMarkers = [];
      this.markersByAccountId = {};
      return;
    }
    this.mapMarkers.forEach((marker) => this.mapInstance.removeLayer(marker));
    this.mapMarkers = [];
    this.markersByAccountId = {};
  }

  destroyMap() {
    this.clearMarkers();
    if (this.mapInstance) {
      this.mapInstance.remove();
      this.mapInstance = null;
    }
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((e) => e.message).join(', ');
    }
    return error?.body?.message || error?.message || 'Unable to load accounts.';
  }

  isConnectivityError(error) {
    const name = error?.name || '';
    if (name === 'AbortError' || name === 'TypeError') {
      return true;
    }
    const message = error?.message || '';
    return /offline|failed to fetch|networkerror|load failed/i.test(message);
  }
}