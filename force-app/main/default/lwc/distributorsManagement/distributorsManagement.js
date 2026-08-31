import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/sheetjs';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import DISTRIBUTOR_LOGOS from '@salesforce/resourceUrl/DistributorLogos';
import { ensureLeaflet, addOsmTileLayer } from 'c/plannerMapPins';
import {
    DISTRIBUTOR_OPTIONS,
    REPORT_CADENCE_OPTIONS,
    detectDistributor,
    parseDistributorWorkbook,
    inferReportMonth
} from './distributorExcelAdapters';
import getProductAliases from '@salesforce/apex/DistributorsManagementController.getProductAliases';
import getProductMappingNav from '@salesforce/apex/DistributorsManagementController.getProductMappingNav';
import saveProductAliasDrafts from '@salesforce/apex/DistributorsManagementController.saveProductAliasDrafts';
import bulkConfirmProductAliases from '@salesforce/apex/DistributorsManagementController.bulkConfirmProductAliases';
import getSelloutAliases from '@salesforce/apex/DistributorsManagementController.getSelloutAliases';
import updateSelloutAlias from '@salesforce/apex/DistributorsManagementController.updateSelloutAlias';
import mergeSelloutAliases from '@salesforce/apex/DistributorsManagementController.mergeSelloutAliases';
import searchPharmacies from '@salesforce/apex/DistributorsManagementController.searchPharmacies';
import ingestNormalizedRows from '@salesforce/apex/DistributorsManagementController.ingestNormalizedRows';
import previewMappingCoverage from '@salesforce/apex/DistributorsManagementController.previewMappingCoverage';
import getImportBatches from '@salesforce/apex/DistributorsManagementController.getImportBatches';
import getGeocodeConfigStatus from '@salesforce/apex/DistributorsManagementController.getGeocodeConfigStatus';
import saveGeocodeApiKey from '@salesforce/apex/DistributorsManagementController.saveGeocodeApiKey';

const LOGO_FILE_BY_CODE = {
    EPDA: 'epda.png',
    Ebda: 'epda.png',
    EBDA: 'epda.png',
    'EPDA Cust': 'epda.png',
    'Ebda Cust': 'epda.png',
    'EBDA Cust': 'epda.png',
    Egydrug: 'egydrug.png',
    Elezaby: 'elezaby.png',
    IBNSINA: 'ibnsina.png',
    POS: 'pos.png',
    Sofico: 'sofico.png'
};

/** Correct UI spelling; imports still accept Ebda as a typo. */
function displayDistributorLabel(code) {
    if (!code) return code;
    const upper = String(code).trim().toUpperCase();
    if (upper === 'EBDA' || upper === 'EPDA') return 'EPDA';
    if (upper === 'EBDA CUST' || upper === 'EPDA CUST') return 'EPDA Cust';
    return code;
}

function logoFileFor(code) {
    if (!code) return null;
    const raw = String(code).trim();
    if (LOGO_FILE_BY_CODE[raw]) return LOGO_FILE_BY_CODE[raw];
    const labeled = displayDistributorLabel(raw);
    if (LOGO_FILE_BY_CODE[labeled]) return LOGO_FILE_BY_CODE[labeled];
    const upper = raw.toUpperCase();
    if (upper === 'EBDA' || upper === 'EPDA') return 'epda.png';
    if (upper === 'EBDA CUST' || upper === 'EPDA CUST') return 'epda.png';
    return null;
}

const PRODUCT_PAGE_SIZE_OPTIONS = [
    { label: '25', value: '25' },
    { label: '50', value: '50' },
    { label: '100', value: '100' }
];

const TABS = [
    { id: 'import', label: 'Import' },
    { id: 'products', label: 'Product mapping' },
    { id: 'sellouts', label: 'Sellout mapping' },
    { id: 'batches', label: 'Batches' }
];

const CHUNK_SIZE = 1500;

const STATUS_COLORS = {
    Confirmed: '#2e844a',
    Suggested: '#dd7a01',
    Unmatched: '#ba0517',
    Rejected: '#706e6b',
    Pending: '#0176d3'
};

export default class DistributorsManagement extends LightningElement {
    @track activeTab = 'import';
    @track distributorCode = '';
    @track fileName = '';
    @track reportMonth = '';
    @track parsedRows = [];
    @track parseWarnings = [];
    @track sheetUsed = '';
    @track coverage;
    @track isParsing = false;
    @track isImporting = false;
    @track importMessage = '';
    @track reportCadence = '';
    @track detectedFrom = '';
    @track importMaxRows = 200;
    @track preferAddressedRows = true;
    @track geocodeStatus;
    @track googleApiKeyInput = '';
    @track isSavingGeocode = false;

    @track productRows = [];
    @track productStatusFilter = '';
    @track productUnmappedOnly = false;
    @track productDrafts = [];
    @track isSavingProducts = false;
    @track productGroupMode = 'distributor';
    @track productLineFilter = '';
    @track productSearch = '';
    @track productNavKey = '';
    @track productNav = { distributors: [], productLines: [] };
    @track productPage = 1;
    @track productPageSize = 50;
    productSearchTimer;
    productPageSizeOptions = PRODUCT_PAGE_SIZE_OPTIONS;

    @track selloutRows = [];
    @track selloutStatusFilter = '';
    @track selloutNeedsReview = true;
    @track selectedSelloutId;
    @track pharmacyOptions = [];
    @track selectedPharmacyId;
    @track pharmacySearch = '';

    @track batchRows = [];

    sheetjsReady = false;
    leafletReady = false;
    map;
    markersLayer;

    distributorOptions = DISTRIBUTOR_OPTIONS;
    reportCadenceOptions = REPORT_CADENCE_OPTIONS;

    productColumns = [
        { label: 'Distributor', fieldName: 'distributorCode', type: 'text', initialWidth: 110 },
        { label: 'Product line', fieldName: 'productFamily', type: 'text', initialWidth: 120 },
        { label: 'Item code', fieldName: 'itemCode', type: 'text', initialWidth: 100 },
        {
            label: 'Item name',
            fieldName: 'itemName',
            type: 'text',
            editable: true,
            wrapText: true
        },
        {
            label: 'Zeta product',
            fieldName: 'productUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'productName' },
                target: '_blank',
                tooltip: 'Open Salesforce Product'
            }
        },
        {
            label: 'Zeta code',
            fieldName: 'zetaCode',
            type: 'text',
            editable: true,
            initialWidth: 110
        },
        {
            label: 'Confidence %',
            fieldName: 'confidence',
            type: 'number',
            editable: true,
            initialWidth: 110,
            cellAttributes: { alignment: 'left' }
        },
        { label: 'Method', fieldName: 'matchMethod', type: 'text', initialWidth: 90 },
        {
            label: 'Status',
            fieldName: 'status',
            type: 'text',
            editable: true,
            initialWidth: 110
        }
    ];

    selloutColumns = [
        {
            label: 'Alias',
            fieldName: 'recordUrl',
            type: 'url',
            typeAttributes: { label: { fieldName: 'clientName' }, target: '_blank' },
            initialWidth: 160
        },
        { label: 'Distributor', fieldName: 'distributorCode', type: 'text', initialWidth: 90 },
        { label: 'Client code', fieldName: 'clientCode', type: 'text', initialWidth: 90 },
        { label: 'Address', fieldName: 'address', type: 'text' },
        {
            label: 'Pharmacy Account',
            fieldName: 'pharmacyUrl',
            type: 'url',
            typeAttributes: { label: { fieldName: 'pharmacyName' }, target: '_blank' },
            initialWidth: 160
        },
        { label: 'Confidence %', fieldName: 'confidence', type: 'number', initialWidth: 100 },
        { label: 'Geo', fieldName: 'geocodeStatus', type: 'text', initialWidth: 90 },
        {
            label: 'Geo reason',
            fieldName: 'geocodeMessage',
            type: 'text',
            wrapText: true,
            initialWidth: 220
        },
        { label: 'Status', fieldName: 'status', type: 'text', initialWidth: 100 }
    ];

    batchColumns = [
        { label: 'File', fieldName: 'fileName', type: 'text' },
        { label: 'Distributor', fieldName: 'distributorCode', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text' },
        { label: 'Inserted', fieldName: 'rowsInserted', type: 'number' },
        { label: 'Updated', fieldName: 'rowsUpdated', type: 'number' },
        { label: 'Failed', fieldName: 'rowsFailed', type: 'number' },
        { label: 'Aliases', fieldName: 'aliasesCreated', type: 'number' },
        { label: 'Needs review', fieldName: 'needsReview', type: 'number' }
    ];

    statusFilterOptions = [
        { label: 'All statuses', value: '' },
        { label: 'Suggested', value: 'Suggested' },
        { label: 'Confirmed', value: 'Confirmed' },
        { label: 'Rejected', value: 'Rejected' },
        { label: 'Unmatched', value: 'Unmatched' }
    ];

    groupModeOptions = [
        { label: 'Distributor', value: 'distributor' },
        { label: 'Product line', value: 'productLine' },
        { label: 'Flat list', value: 'flat' }
    ];

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
        }));
    }

    get distributorFilterOptions() {
        return [{ label: 'All distributors', value: '' }, ...DISTRIBUTOR_OPTIONS];
    }

    get isImportTab() {
        return this.activeTab === 'import';
    }
    get isProductsTab() {
        return this.activeTab === 'products';
    }
    get isSelloutsTab() {
        return this.activeTab === 'sellouts';
    }
    get isBatchesTab() {
        return this.activeTab === 'batches';
    }

    get hasParsedRows() {
        return this.parsedRows.length > 0;
    }

    get parseSummary() {
        if (!this.hasParsedRows) return '';
        const products = new Set(this.parsedRows.map((r) => r.itemCode)).size;
        const sellouts = new Set(this.parsedRows.map((r) => r.clientCode)).size;
        let cover = '';
        if (this.coverage) {
            cover = ` | Products mapped ${this.coverage.productsMapped}/${this.coverage.distinctProducts} | Sellouts mapped ${this.coverage.selloutsMapped}/${this.coverage.distinctSellouts}`;
        }
        const cadence = this.reportCadence ? ` | ${this.reportCadence}` : '';
        const dist = this.distributorCode ? ` | ${this.distributorCode}` : '';
        return `${this.parsedRows.length} rows${dist}${cadence} | ${products} products | ${sellouts} sellouts | sheet ${this.sheetUsed || '-'}${cover}`;
    }

    get selectedSellout() {
        return this.selloutRows.find((r) => r.recordId === this.selectedSelloutId);
    }

    get linkedDistributorsLabel() {
        const s = this.selectedSellout;
        if (!s?.linkedDistributors?.length) return '';
        return `Also mapped from: ${s.linkedDistributors.join(', ')}`;
    }

    get selectedSelloutHasPharmacy() {
        return !!this.selectedSellout?.pharmacyUrl;
    }

    get selectedSelloutGeoStatus() {
        return this.selectedSellout?.geocodeStatus || '';
    }

    get selectedSelloutNeedsGeoHelp() {
        const status = this.selectedSelloutGeoStatus;
        return status === 'Failed' || status === 'Skipped' || status === 'Pending';
    }

    get selectedSelloutGeoReason() {
        return this.selectedSellout?.geocodeMessage || '';
    }

    get selectedSelloutGeoRecommendation() {
        return this.selectedSellout?.geocodeRecommendation || '';
    }

    get selectedSelloutRecordUrl() {
        return this.selectedSellout?.recordUrl || null;
    }

    get selectedSelloutPharmacyUrl() {
        return this.selectedSellout?.pharmacyUrl || null;
    }

    get selectedSelloutPharmacyLabel() {
        const s = this.selectedSellout;
        if (!s?.pharmacyName) return '';
        return s.pharmacyName;
    }

    get hasProductDrafts() {
        return (this.productDrafts || []).length > 0;
    }

    get pharmacyComboboxOptions() {
        return (this.pharmacyOptions || []).map((o) => ({ label: o.label, value: o.value }));
    }

    get showProductNav() {
        return this.productGroupMode !== 'flat';
    }

    get productLayoutClass() {
        return this.showProductNav ? 'product-layout product-layout--split' : 'product-layout';
    }

    get productNavSource() {
        if (this.productGroupMode === 'productLine') {
            return this.productNav?.productLines || [];
        }
        return this.productNav?.distributors || [];
    }

    get productNavItems() {
        return this.productNavSource.map((item) => {
            const label = displayDistributorLabel(item.label || item.key);
            const logoUrl = this.logoUrlFor(item.key) || this.logoUrlFor(label);
            return {
                ...item,
                label,
                logoUrl,
                hasLogo: !!logoUrl && this.productGroupMode === 'distributor',
                className: `nav-item${this.productNavKey === item.key ? ' nav-item--active' : ''}`
            };
        });
    }

    get allNavClass() {
        return `nav-item${this.productNavKey === '' ? ' nav-item--active' : ''}`;
    }

    get productTotalCount() {
        return this.productNavSource.reduce((sum, item) => sum + (item.count || 0), 0);
    }

    get productLineFilterOptions() {
        const lines = (this.productNav?.productLines || []).map((g) => ({
            label: `${g.label} (${g.count})`,
            value: g.key
        }));
        return [{ label: 'All product lines', value: '' }, ...lines];
    }

    get productFilterSummary() {
        const parts = [];
        if (this.distributorCode) parts.push(this.distributorCode);
        if (this.productNavKey) {
            const hit = this.productNavSource.find((g) => g.key === this.productNavKey);
            parts.push(hit?.label || this.productNavKey);
        } else if (this.productLineFilter) {
            const hit = (this.productNav?.productLines || []).find((g) => g.key === this.productLineFilter);
            parts.push(hit?.label || this.productLineFilter);
        }
        if (this.productSearch) parts.push(`"${this.productSearch}"`);
        const scope = parts.length ? parts.join(' | ') : 'All mappings';
        return `${scope} | ${this.productRows.length} row(s)`;
    }

    get productTotalPages() {
        return Math.max(1, Math.ceil((this.productRows || []).length / this.productPageSize));
    }

    get pagedProductRows() {
        const start = (this.productPage - 1) * this.productPageSize;
        return (this.productRows || []).slice(start, start + this.productPageSize);
    }

    get productPageLabel() {
        if (!this.productRows?.length) {
            return 'No rows';
        }
        const start = (this.productPage - 1) * this.productPageSize + 1;
        const end = Math.min(this.productPage * this.productPageSize, this.productRows.length);
        return `Showing ${start}-${end} of ${this.productRows.length}`;
    }

    get isProductPrevDisabled() {
        return this.productPage <= 1;
    }

    get isProductNextDisabled() {
        return this.productPage >= this.productTotalPages;
    }

    get productPageSizeValue() {
        return String(this.productPageSize);
    }

    logoUrlFor(code) {
        const file = logoFileFor(code);
        return file ? `${DISTRIBUTOR_LOGOS}/${file}` : null;
    }

    get allDistributorsLogoUrl() {
        return `${DISTRIBUTOR_LOGOS}/all.png`;
    }

    resetProductPage() {
        this.productPage = 1;
    }

    get geocodeProviderLabel() {
        return this.geocodeStatus?.providerLabel || 'Checking geocoder...';
    }

    get geocodeReadyMessage() {
        if (!this.geocodeStatus) return '';
        if (this.geocodeStatus.hasGoogleKey) {
            return `Using Google Geocoding. Proximity ${this.geocodeStatus.proximityMeters}m / auto-confirm ${this.geocodeStatus.autoConfirmThreshold}%.`;
        }
        return `No Google API key set - using OpenStreetMap Nominatim fallback (slower, sample imports only). Proximity ${this.geocodeStatus.proximityMeters}m.`;
    }

    connectedCallback() {
        this.loadProductRows();
        this.loadBatchRows();
        this.loadGeocodeStatus();
    }

    async loadGeocodeStatus() {
        try {
            this.geocodeStatus = await getGeocodeConfigStatus();
        } catch (e) {
            // non-blocking
        }
    }

    renderedCallback() {
        if (this.isSelloutsTab && this.leafletReady && this.selloutRows.length) {
            // map refresh handled after load
        }
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tabId;
        if (this.activeTab === 'products') {
            this.loadProductRows();
        } else if (this.activeTab === 'sellouts') {
            this.loadSelloutRows().then(() => this.initMap());
        } else if (this.activeTab === 'batches') {
            this.loadBatchRows();
        }
    }

    handleDistributorChange(event) {
        this.distributorCode = event.detail.value || '';
        this.productNavKey = '';
        if (this.activeTab === 'products') {
            this.loadProductRows();
        } else if (this.activeTab === 'sellouts') {
            this.loadSelloutRows();
        } else if (this.activeTab === 'batches') {
            this.loadBatchRows();
        }
    }

    handleReportMonthChange(event) {
        this.reportMonth = event.target.value;
    }

    async ensureSheetJs() {
        if (this.sheetjsReady) return;
        await loadScript(this, SHEETJS);
        this.sheetjsReady = true;
    }

    async handleFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) return;
        this.fileName = file.name;
        this.isParsing = true;
        this.parseWarnings = [];
        this.parsedRows = [];
        this.coverage = null;
        this.reportCadence = '';
        this.detectedFrom = '';
        try {
            await this.ensureSheetJs();
            const buffer = await file.arrayBuffer();
            const workbook = globalThis.XLSX.read(buffer, { type: 'array' });
            // Keep manual distributor override; otherwise detect from filename then workbook layout
            const preferred = this.distributorCode || detectDistributor(file.name);
            const parsed = parseDistributorWorkbook(workbook, preferred, file.name);
            this.distributorCode = parsed.distributorCode || this.distributorCode || '';
            let rows = parsed.rows || [];
            if (this.preferAddressedRows) {
                const addressed = rows.filter((r) => (r.address || '').trim());
                if (addressed.length) {
                    rows = addressed;
                    this.parseWarnings = [
                        ...(parsed.warnings || []),
                        `Prefer addressed rows: using ${addressed.length} of ${(parsed.rows || []).length} with an address (better for geocoding).`
                    ];
                } else {
                    this.parseWarnings = parsed.warnings || [];
                }
            } else {
                this.parseWarnings = parsed.warnings || [];
            }
            const maxRows = Number(this.importMaxRows) > 0 ? Number(this.importMaxRows) : 0;
            if (maxRows && rows.length > maxRows) {
                rows = rows.slice(0, maxRows);
                this.parseWarnings = [
                    ...this.parseWarnings,
                    `Import capped at ${maxRows} rows for a safe pilot (change Max rows to import more).`
                ];
            }
            this.parsedRows = rows;
            this.sheetUsed = parsed.sheetUsed || '';
            this.reportCadence = parsed.reportCadence || '';
            this.detectedFrom = parsed.detectedFrom || '';
            this.reportMonth = inferReportMonth(this.parsedRows);
            if (this.parsedRows.length) {
                const sample = this.parsedRows.slice(0, 800);
                this.coverage = await previewMappingCoverage({
                    distributorCode: this.distributorCode,
                    rowsJson: JSON.stringify(sample)
                });
                this.toast('Parsed', this.parseSummary, 'success');
            } else {
                const detail =
                    (this.parseWarnings && this.parseWarnings[0]) ||
                    'No rows. Select the distributor if auto-detect failed.';
                this.toast('Parsed', detail, 'warning');
            }
        } catch (e) {
            this.toast('Parse error', this.reduceError(e), 'error');
        } finally {
            this.isParsing = false;
        }
    }

    async handleImport() {
        if (!this.parsedRows.length) {
            this.toast('Import', 'Parse a distributor Excel file first.', 'warning');
            return;
        }
        if (!this.distributorCode) {
            this.toast('Import', 'Select a distributor.', 'warning');
            return;
        }
        this.isImporting = true;
        this.importMessage = '';
        try {
            let batchId = null;
            const total = this.parsedRows.length;
            for (let i = 0; i < total; i += CHUNK_SIZE) {
                const chunk = this.parsedRows.slice(i, i + CHUNK_SIZE);
                const isLast = i + CHUNK_SIZE >= total;
                const result = await ingestNormalizedRows({
                    distributorCode: this.distributorCode,
                    fileName: this.fileName,
                    reportMonth: this.reportMonth,
                    rowsJson: JSON.stringify(chunk),
                    existingBatchId: batchId,
                    finalize: isLast
                });
                batchId = result.batchId;
                this.importMessage = `Processed ${Math.min(i + CHUNK_SIZE, total)} / ${total}. ${result.message}`;
            }
            this.toast('Import queued', this.importMessage, 'success');
            this.loadBatchRows();
            this.loadProductRows();
            this.activeTab = 'batches';
        } catch (e) {
            this.toast('Import failed', this.reduceError(e), 'error');
        } finally {
            this.isImporting = false;
        }
    }

    handleImportMaxRowsChange(event) {
        this.importMaxRows = Number(event.target.value) || 0;
    }

    handlePreferAddressedToggle(event) {
        this.preferAddressedRows = event.target.checked;
    }

    handleGoogleApiKeyChange(event) {
        this.googleApiKeyInput = event.target.value;
    }

    async handleSaveGeocodeKey() {
        this.isSavingGeocode = true;
        try {
            this.geocodeStatus = await saveGeocodeApiKey({ apiKey: this.googleApiKeyInput });
            this.googleApiKeyInput = '';
            this.toast('Geocode config', this.geocodeReadyMessage, 'success');
        } catch (e) {
            this.toast('Geocode config', this.reduceError(e), 'error');
        } finally {
            this.isSavingGeocode = false;
        }
    }

    resolveProductQueryFilters() {
        let distributorCode = this.distributorCode || null;
        let productLineFilter = this.productLineFilter || null;

        if (this.productGroupMode === 'distributor' && this.productNavKey) {
            distributorCode = this.productNavKey;
        }
        if (this.productGroupMode === 'productLine' && this.productNavKey) {
            productLineFilter = this.productNavKey;
        }

        return { distributorCode, productLineFilter };
    }

    async loadProductRows() {
        try {
            const { distributorCode, productLineFilter } = this.resolveProductQueryFilters();
            const [rows, nav] = await Promise.all([
                getProductAliases({
                    distributorCode,
                    statusFilter: this.productStatusFilter || null,
                    unmappedOnly: this.productUnmappedOnly,
                    limitSize: 1000,
                    productLineFilter,
                    searchTerm: this.productSearch || null
                }),
                getProductMappingNav({
                    distributorCode: this.distributorCode || null,
                    statusFilter: this.productStatusFilter || null,
                    unmappedOnly: this.productUnmappedOnly
                })
            ]);
            this.productNav = nav || { distributors: [], productLines: [] };
            this.productRows = (rows || []).map((row) => ({
                ...row,
                productFamily: row.productFamily || 'Unassigned',
                productUrl: row.productUrl || (row.productId ? `/${row.productId}` : null),
                productName: row.productName || (row.productId ? 'Open product' : '')
            }));
            this.productDrafts = [];
            this.resetProductPage();
        } catch (e) {
            this.toast('Product aliases', this.reduceError(e), 'error');
        }
    }

    handleProductGroupModeChange(event) {
        this.productGroupMode = event.detail.value;
        this.productNavKey = '';
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductNavClick(event) {
        this.productNavKey = event.currentTarget.dataset.key || '';
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductLineFilterChange(event) {
        this.productLineFilter = event.detail.value || '';
        if (this.productGroupMode === 'productLine') {
            this.productNavKey = this.productLineFilter;
        }
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductFilterChange(event) {
        this.productStatusFilter = event.detail.value;
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductUnmappedToggle(event) {
        this.productUnmappedOnly = event.target.checked;
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductSearchChange(event) {
        this.productSearch = event.target.value || '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.clearTimeout(this.productSearchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.productSearchTimer = window.setTimeout(() => {
            this.resetProductPage();
            this.loadProductRows();
        }, 300);
    }

    handleProductPageSizeChange(event) {
        this.productPageSize = Number(event.detail.value) || 50;
        this.resetProductPage();
    }

    handleProductPrevPage() {
        if (this.productPage > 1) {
            this.productPage -= 1;
        }
    }

    handleProductNextPage() {
        if (this.productPage < this.productTotalPages) {
            this.productPage += 1;
        }
    }

    handleProductCellChange(event) {
        this.productDrafts = event.detail.draftValues || [];
    }

    handleCancelProductDrafts() {
        this.productDrafts = [];
        const table = this.template.querySelector('lightning-datatable');
        if (table) {
            table.draftValues = [];
        }
    }

    async handleSaveProductDrafts(event) {
        const drafts = event?.detail?.draftValues || this.productDrafts || [];
        if (!drafts.length) {
            return;
        }
        this.isSavingProducts = true;
        try {
            const n = await saveProductAliasDrafts({ draftsJson: JSON.stringify(drafts) });
            this.toast('Saved', `Updated ${n} product mapping(s).`, 'success');
            this.productDrafts = [];
            const table = this.template.querySelector('lightning-datatable');
            if (table) {
                table.draftValues = [];
            }
            await this.loadProductRows();
        } catch (e) {
            this.toast('Save failed', this.reduceError(e), 'error');
        } finally {
            this.isSavingProducts = false;
        }
    }

    async handleBulkConfirmProducts() {
        try {
            const { distributorCode } = this.resolveProductQueryFilters();
            const n = await bulkConfirmProductAliases({
                minConfidence: 90,
                distributorCode
            });
            this.toast('Bulk confirm', `Confirmed ${n} aliases with 90%+ confidence.`, 'success');
            this.loadProductRows();
        } catch (e) {
            this.toast('Bulk confirm failed', this.reduceError(e), 'error');
        }
    }

    async loadSelloutRows() {
        try {
            this.selloutRows = await getSelloutAliases({
                distributorCode: this.distributorCode || null,
                statusFilter: this.selloutStatusFilter || null,
                needsReviewOnly: this.selloutNeedsReview,
                limitSize: 500
            });
            this.renderMarkers();
        } catch (e) {
            this.toast('Sellout aliases', this.reduceError(e), 'error');
        }
    }

    handleSelloutFilterChange(event) {
        this.selloutStatusFilter = event.detail.value;
        this.loadSelloutRows();
    }

    handleSelloutReviewToggle(event) {
        this.selloutNeedsReview = event.target.checked;
        this.loadSelloutRows();
    }

    handleSelloutRowSelection(event) {
        const selected = event.detail.selectedRows?.[0];
        this.selectedSelloutId = selected?.recordId;
        this.focusMarker(selected);
    }

    handleOpenSelectedAlias() {
        const url = this.selectedSelloutRecordUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleOpenSelectedPharmacy() {
        const url = this.selectedSelloutPharmacyUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }

    async handlePharmacySearch(event) {
        this.pharmacySearch = event.target.value;
        if ((this.pharmacySearch || '').length < 2) {
            this.pharmacyOptions = [];
            return;
        }
        this.pharmacyOptions = await searchPharmacies({ searchTerm: this.pharmacySearch });
    }

    handlePharmacyOptionChange(event) {
        this.selectedPharmacyId = event.detail.value;
    }

    async handleLinkPharmacy() {
        if (!this.selectedSelloutId) {
            this.toast('Sellout', 'Select a sellout row.', 'warning');
            return;
        }
        try {
            await updateSelloutAlias({
                aliasId: this.selectedSelloutId,
                pharmacyId: this.selectedPharmacyId,
                status: 'Confirmed',
                confidence: 100,
                createPharmacy: false
            });
            this.toast('Linked', 'Sellout linked to pharmacy.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Link failed', this.reduceError(e), 'error');
        }
    }

    async handleCreatePharmacy() {
        if (!this.selectedSelloutId) return;
        try {
            await updateSelloutAlias({
                aliasId: this.selectedSelloutId,
                pharmacyId: null,
                status: 'Confirmed',
                confidence: 100,
                createPharmacy: true
            });
            this.toast('Created', 'Pharmacy account created and linked.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Create failed', this.reduceError(e), 'error');
        }
    }

    async handleRejectSellout() {
        if (!this.selectedSelloutId) return;
        try {
            await updateSelloutAlias({
                aliasId: this.selectedSelloutId,
                pharmacyId: null,
                status: 'Rejected',
                confidence: 0,
                createPharmacy: false
            });
            this.toast('Rejected', 'Sellout alias rejected.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Reject failed', this.reduceError(e), 'error');
        }
    }

    async handleMergeSellout() {
        if (!this.selectedSelloutId || !this.selectedPharmacyId) {
            this.toast('Merge', 'Select a sellout row and a target pharmacy.', 'warning');
            return;
        }
        try {
            await mergeSelloutAliases({
                sourceAliasId: this.selectedSelloutId,
                targetPharmacyId: this.selectedPharmacyId
            });
            this.toast('Merged', 'Alias mapped onto target pharmacy.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Merge failed', this.reduceError(e), 'error');
        }
    }

    async initMap() {
        const container = this.template.querySelector('.sellout-map');
        if (!container) return;
        try {
            const leaflet = await ensureLeaflet(this, LEAFLET);
            await loadStyle(this, `${LEAFLET}/leaflet.css`);
            this.leafletReady = true;
            if (this.map) {
                this.map.remove();
                this.map = null;
            }
            this.map = leaflet.map(container).setView([30.0444, 31.2357], 6);
            addOsmTileLayer(this.map, leaflet);
            this.markersLayer = leaflet.layerGroup().addTo(this.map);
            this.renderMarkers();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.map.invalidateSize(), 100);
        } catch (e) {
            this.toast('Map', this.reduceError(e), 'error');
        }
    }

    renderMarkers() {
        if (!this.map || !this.markersLayer || !globalThis.L) return;
        const leaflet = globalThis.L;
        this.markersLayer.clearLayers();
        const bounds = [];
        for (const row of this.selloutRows) {
            if (row.latitude == null || row.longitude == null) continue;
            const color = STATUS_COLORS[row.status] || '#0176d3';
            const marker = leaflet.circleMarker([row.latitude, row.longitude], {
                radius: 7,
                color,
                fillColor: color,
                fillOpacity: 0.85
            });
            marker.bindPopup(
                `<strong>${row.clientName || row.clientCode}</strong><br/>${row.distributorCode}<br/>${row.address || ''}<br/>${row.pharmacyName || row.status}`
            );
            marker.on('click', () => {
                this.selectedSelloutId = row.recordId;
            });
            marker.addTo(this.markersLayer);
            bounds.push([row.latitude, row.longitude]);
        }
        if (bounds.length) {
            this.map.fitBounds(bounds, { padding: [24, 24], maxZoom: 14 });
        }
    }

    focusMarker(row) {
        if (!this.map || !row || row.latitude == null) return;
        this.map.setView([row.latitude, row.longitude], 15);
    }

    async loadBatchRows() {
        try {
            this.batchRows = await getImportBatches({ limitSize: 50 });
        } catch (e) {
            this.toast('Batches', this.reduceError(e), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error.body?.message || error.message || String(error);
    }
}