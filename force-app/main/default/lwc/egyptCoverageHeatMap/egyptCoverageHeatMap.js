import { LightningElement, api, track } from 'lwc';
import getEgyptCoverageHeatMap from '@salesforce/apex/ManagementKpiController.getEgyptCoverageHeatMap';
import egyptGeoUrl from '@salesforce/resourceUrl/egyptGovernoratesGeoJson';

const MAP_WIDTH = 640;
const MAP_HEIGHT = 720;
const BOUNDS = { minLng: 25.0, maxLng: 36.0, minLat: 23.5, maxLat: 32.0 };

const METRICS = {
    coverage: { label: 'Coverage', legendLow: 'Low coverage', legendHigh: 'High coverage' },
    sales: { label: 'Sales', legendLow: 'Low sell-out', legendHigh: 'High sell-out' },
    gap: { label: 'Gap', legendLow: 'Over-covered', legendHigh: 'Under-covered' }
};

function project(lng, lat) {
    const x = ((lng - BOUNDS.minLng) / (BOUNDS.maxLng - BOUNDS.minLng)) * MAP_WIDTH;
    const y = ((BOUNDS.maxLat - lat) / (BOUNDS.maxLat - BOUNDS.minLat)) * MAP_HEIGHT;
    return [x, y];
}

function ringToPath(ring) {
    if (!ring || !ring.length) {
        return '';
    }
    return ring.map((coord, index) => {
        const [x, y] = project(coord[0], coord[1]);
        return `${index === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`;
    }).join(' ') + ' Z';
}

function pctDisplay(value) {
    if (value == null || value === '') {
        return '—';
    }
    return `${Number(value).toFixed(1)}%`;
}

function egpDisplay(value) {
    if (value == null || value === '') {
        return '—';
    }
    const n = Number(value);
    if (n >= 1000000) {
        return `EGP ${(n / 1000000).toFixed(1)}M`;
    }
    if (n >= 1000) {
        return `EGP ${(n / 1000).toFixed(0)}K`;
    }
    return `EGP ${n.toFixed(0)}`;
}

function numDisplay(value) {
    if (value == null) {
        return '0';
    }
    return Number(value).toLocaleString();
}

function metricValue(row, metric) {
    if (!row) {
        return 0;
    }
    if (metric === 'sales') {
        return Number(row.salesActualEgp) || 0;
    }
    if (metric === 'gap') {
        return Number(row.gapScore) || 0;
    }
    return Number(row.coveragePercent) || 0;
}

function interpolateColor(min, max, value, metric) {
    if (metric === 'gap') {
        if (value > 15) return '#dc2626';
        if (value > 5) return '#f59e0b';
        if (value < -15) return '#2563eb';
        if (value < -5) return '#06b6d4';
        return '#94a3b8';
    }
    const range = max - min;
    const t = range <= 0 ? 0.5 : (value - min) / range;
    const r = Math.round(254 - t * 196);
    const g = Math.round(243 - t * 83);
    const b = Math.round(199 - t * 119);
    return `rgb(${r}, ${g}, ${b})`;
}

export default class EgyptCoverageHeatMap extends LightningElement {
    @api buTerritoryId;
    @api lineTerritoryId;
    @api districtTerritoryId;

    @track selectedMetric = 'coverage';
    @track mapPaths = [];
    @track rowByKey = {};
    @track nationalCoverageDisplay = '—';
    @track nationalSalesDisplay = '—';
    @track nationalVisitsDisplay = '0';
    @track monthLabel = '';
    @track isLoading = true;
    @track errorMessage = '';
    @track hoveredKey = null;
    @track selectedKey = null;
    @track tooltipStyle = '';
    @track ariaLiveMessage = '';

    _geoLoaded = false;
    _geoFeatures = [];
    _filterKey = '';

    connectedCallback() {
        this.loadGeoJson();
    }

    renderedCallback() {
        const filterKey = `${this.buTerritoryId || ''}|${this.lineTerritoryId || ''}|${this.districtTerritoryId || ''}`;
        if (filterKey !== this._filterKey && this._geoLoaded) {
            this._filterKey = filterKey;
            this.loadHeatMapData();
        }
    }

    get viewBox() {
        return `0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`;
    }

    get hasMap() {
        return this.mapPaths.length > 0;
    }

    get metricOptions() {
        return Object.keys(METRICS).map((key) => ({
            key,
            label: METRICS[key].label,
            buttonClass: key === this.selectedMetric ? 'ech-metric-pill ech-metric-active' : 'ech-metric-pill'
        }));
    }

    get legendLowLabel() {
        return METRICS[this.selectedMetric]?.legendLow || '';
    }

    get legendHighLabel() {
        return METRICS[this.selectedMetric]?.legendHigh || '';
    }

    get selectedRow() {
        return this.selectedKey ? this.rowByKey[this.selectedKey] : null;
    }

    get hasSelectedTopBricks() {
        return (this.selectedRow?.topBricks || []).length > 0;
    }

    get hoveredRow() {
        return this.hoveredKey ? this.rowByKey[this.hoveredKey] : null;
    }

    get showTooltip() {
        return this.hoveredRow != null && !this.selectedKey;
    }

    async loadGeoJson() {
        try {
            const response = await fetch(egyptGeoUrl);
            const geo = await response.json();
            this._geoFeatures = geo.features || [];
            this._geoLoaded = true;
            this._filterKey = `${this.buTerritoryId || ''}|${this.lineTerritoryId || ''}|${this.districtTerritoryId || ''}`;
            await this.loadHeatMapData();
        } catch (error) {
            this.errorMessage = 'Failed to load Egypt map geometry.';
            this.isLoading = false;
        }
    }

    async loadHeatMapData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getEgyptCoverageHeatMap({
                buTerritoryId: this.buTerritoryId,
                lineTerritoryId: this.lineTerritoryId,
                districtTerritoryId: this.districtTerritoryId
            });
            this.monthLabel = data.monthLabel || '';
            this.nationalCoverageDisplay = pctDisplay(data.nationalCoveragePercent);
            this.nationalSalesDisplay = egpDisplay(data.nationalSalesEgp);
            this.nationalVisitsDisplay = numDisplay(data.nationalVisitCount);

            const rows = data.rows || [];
            const rowMap = {};
            rows.forEach((row) => {
                rowMap[row.governorateKey] = {
                    ...row,
                    coverageDisplay: pctDisplay(row.coveragePercent),
                    salesDisplay: egpDisplay(row.salesActualEgp),
                    visitIntensityDisplay: pctDisplay(row.visitIntensity),
                    gapDisplay: row.gapScore != null ? `${Number(row.gapScore) > 0 ? '+' : ''}${Number(row.gapScore).toFixed(1)}` : '—',
                    gapClass: this.gapClass(row.gapScore),
                    topBricks: (row.topBricks || []).map((brick) => ({
                        ...brick,
                        key: brick.brickName,
                        salesDisplay: egpDisplay(brick.salesEgp)
                    }))
                };
            });
            this.rowByKey = rowMap;
            this.buildMapPaths();
            this.selectedKey = null;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Failed to load coverage map.';
        } finally {
            this.isLoading = false;
        }
    }

    buildMapPaths() {
        const metric = this.selectedMetric;
        const dataRows = Object.values(this.rowByKey).filter((row) => row.hasData);
        let min = Infinity;
        let max = -Infinity;
        dataRows.forEach((row) => {
            const val = metricValue(row, metric);
            min = Math.min(min, val);
            max = Math.max(max, val);
        });
        if (!Number.isFinite(min)) {
            min = 0;
            max = 100;
        }

        this.mapPaths = this._geoFeatures.map((feature) => {
            const key = feature.properties?.key;
            const label = feature.properties?.label || key;
            const row = this.rowByKey[key];
            const hasData = row?.hasData === true;
            const value = metricValue(row, metric);
            const fill = hasData ? interpolateColor(min, max, value, metric) : '#e2e8f0';
            const ring = feature.geometry?.coordinates?.[0] || [];
            const pathClass = this.pathClass(key, hasData);
            return {
                key,
                label,
                d: ringToPath(ring),
                fill,
                pathClass,
                hasData,
                ariaLabel: `${label}: ${hasData ? (metric === 'sales' ? row.salesDisplay : row.coverageDisplay) : 'No data'}`
            };
        });
    }

    pathClass(key, hasData) {
        let cls = 'ech-region';
        if (!hasData) {
            cls += ' ech-region-empty';
        }
        if (key === this.hoveredKey) {
            cls += ' ech-region-hover';
        }
        if (key === this.selectedKey) {
            cls += ' ech-region-selected';
        }
        return cls;
    }

    gapClass(gapScore) {
        const gap = Number(gapScore) || 0;
        if (gap > 5) return 'ech-gap-up';
        if (gap < -5) return 'ech-gap-down';
        return 'ech-gap-flat';
    }

    handleMetricClick(event) {
        const metric = event.currentTarget.dataset.metric;
        if (!metric || metric === this.selectedMetric) {
            return;
        }
        this.selectedMetric = metric;
        this.buildMapPaths();
        this.ariaLiveMessage = `Showing ${METRICS[metric].label} layer`;
    }

    handleRegionEnter(event) {
        const key = event.currentTarget.dataset.key;
        this.hoveredKey = key;
        this.updateTooltipPosition(event);
        this.buildMapPaths();
        const row = this.rowByKey[key];
        if (row) {
            this.ariaLiveMessage = `${row.governorateLabel}: coverage ${row.coverageDisplay}, sales ${row.salesDisplay}`;
        }
    }

    handleRegionMove(event) {
        this.updateTooltipPosition(event);
    }

    handleRegionLeave() {
        this.hoveredKey = null;
        this.tooltipStyle = '';
        this.buildMapPaths();
    }

    handleRegionClick(event) {
        const key = event.currentTarget.dataset.key;
        this.selectedKey = this.selectedKey === key ? null : key;
        this.buildMapPaths();
        const row = this.rowByKey[key];
        if (row) {
            this.ariaLiveMessage = this.selectedKey
                ? `Selected ${row.governorateLabel}`
                : 'Selection cleared';
        }
    }

    handleCloseDetail() {
        this.selectedKey = null;
        this.buildMapPaths();
    }

    updateTooltipPosition(event) {
        const shell = this.template.querySelector('.ech-map-shell');
        if (!shell) {
            return;
        }
        const rect = shell.getBoundingClientRect();
        const x = event.clientX - rect.left + 12;
        const y = event.clientY - rect.top + 12;
        const maxX = rect.width - 180;
        const maxY = rect.height - 120;
        const left = Math.min(Math.max(8, x), maxX);
        const top = Math.min(Math.max(8, y), maxY);
        this.tooltipStyle = `left:${left}px;top:${top}px;`;
    }
}