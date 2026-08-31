import { LightningElement, track } from 'lwc';
import getTeamKpis from '@salesforce/apex/ManagementKpiController.getTeamKpis';
import getTeamClmDrillDown from '@salesforce/apex/ManagementKpiController.getTeamClmDrillDown';
import getProductPerformanceDrillDown from '@salesforce/apex/ManagementKpiController.getProductPerformanceDrillDown';
import getCoachingTrendDrillDown from '@salesforce/apex/ManagementKpiController.getCoachingTrendDrillDown';
import getWorkforceRoster from '@salesforce/apex/ManagementKpiController.getWorkforceRoster';
import getExecutiveBuProductPerformance from '@salesforce/apex/ManagementKpiController.getExecutiveBuProductPerformance';
import getBusinessUnitOptions from '@salesforce/apex/ManagementKpiController.getBusinessUnitOptions';
import getLineOptions from '@salesforce/apex/ManagementKpiController.getLineOptions';
import getDistrictOptions from '@salesforce/apex/ManagementKpiController.getDistrictOptions';
import publishHomeOfficeMessage from '@salesforce/apex/HomeOfficeMessageController.publishMessage';

const RING_CIRCUMFERENCE = 2 * Math.PI * 22;
const DONUT_CIRCUMFERENCE = 2 * Math.PI * 18;

function pctNumber(value) {
    if (value == null) {
        return 0;
    }
    const n = Number(value);
    return n <= 1 ? Math.round(n * 100) : Math.round(n);
}

function pctDisplay(value) {
    return `${pctNumber(value)}%`;
}

function numDisplay(value, digits = 0) {
    if (value == null) {
        return '0';
    }
    return Number(value).toFixed(digits);
}

function ringStroke(percent) {
    const p = Math.min(100, Math.max(0, pctNumber(percent)));
    const offset = RING_CIRCUMFERENCE - (p / 100) * RING_CIRCUMFERENCE;
    return `stroke-dasharray: ${RING_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`;
}

function donutStroke(percent) {
    const p = Math.min(100, Math.max(0, pctNumber(percent)));
    const offset = DONUT_CIRCUMFERENCE - (p / 100) * DONUT_CIRCUMFERENCE;
    return `stroke-dasharray: ${DONUT_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`;
}

function statusClass(percent, thresholds = { good: 80, warn: 60 }) {
    const p = pctNumber(percent);
    if (p >= thresholds.good) {
        return 'status-good';
    }
    if (p >= thresholds.warn) {
        return 'status-warn';
    }
    return 'status-low';
}

function barColor(percent, thresholds = { good: 80, warn: 60 }) {
    const p = pctNumber(percent);
    if (p >= thresholds.good) {
        return '#2e844a';
    }
    if (p >= thresholds.warn) {
        return '#fe9339';
    }
    return '#ea001e';
}

function modalBarFillStyle(percent, format, maxVal) {
    let widthPct;
    if (format === 'pct') {
        widthPct = Math.min(100, Math.max(0, pctNumber(percent)));
    } else {
        const raw = Number(percent) || 0;
        widthPct = Math.min(100, Math.round((raw / Math.max(maxVal, 1)) * 100));
    }
    const color = format === 'pct' ? barColor(percent) : '#0176d3';
    const minWidth = widthPct > 0 ? 'min-width: 6px;' : '';
    return `width: ${widthPct}%; ${minWidth} background-color: ${color};`;
}

function barHeight(value, maxValue) {
    const max = Math.max(maxValue, 1);
    const pct = Math.min(100, Math.round((pctNumber(value) / max) * 100));
    return `height: ${Math.max(pct, 4)}%;`;
}

function ratioPctDisplay(value) {
    return `${Math.round((Number(value) || 0) * 100)}%`;
}

function sentimentPctDisplay(value) {
    return `${Math.round((Number(value) || 0) * 100)}%`;
}

function sentimentClass(label) {
    const normalized = (label || '').toLowerCase();
    if (normalized === 'positive') {
        return 'sentiment-positive';
    }
    if (normalized === 'negative') {
        return 'sentiment-negative';
    }
    return 'sentiment-neutral';
}

function coachingScoreDisplay(value) {
    if (value == null) {
        return '—';
    }
    return `${Number(value).toFixed(1)}%`;
}

function coachingDeltaDisplay(delta) {
    if (delta == null) {
        return '';
    }
    const sign = Number(delta) > 0 ? '+' : '';
    return `${sign}${Number(delta).toFixed(1)}%`;
}

function coachingTrendArrow(trend) {
    if (trend === 'growing') {
        return '▲';
    }
    if (trend === 'declining') {
        return '▼';
    }
    if (trend === 'flat') {
        return '■';
    }
    return '';
}

function coachingTrendClass(trend) {
    if (trend === 'growing') {
        return 'coaching-trend-up';
    }
    if (trend === 'declining') {
        return 'coaching-trend-down';
    }
    if (trend === 'flat') {
        return 'coaching-trend-flat';
    }
    return 'coaching-trend-none';
}

function mapSectionTrend(section) {
    const shortName =
        section.sectionName === 'Core Values'
            ? 'Core'
            : section.sectionName === 'Selling Skills'
              ? 'Selling'
              : section.sectionName;
    return {
        ...section,
        key: section.sectionName,
        shortName,
        latestDisplay: coachingScoreDisplay(section.latestScore),
        deltaDisplay: coachingDeltaDisplay(section.delta),
        arrow: coachingTrendArrow(section.trend),
        trendClass: coachingTrendClass(section.trend)
    };
}

function mapCoachingRepRow(rep, index) {
    const monthlyScores = (rep.monthlyScores || []).map((point, pointIndex) => {
        const score = Number(point.avgScore) || 0;
        return {
            ...point,
            key: `${rep.repId}-${point.monthKey || pointIndex}`,
            scoreLabel: score > 0 ? `${score.toFixed(0)}%` : '',
            barStyle: `height: ${Math.max(Math.round(score), score > 0 ? 6 : 0)}%;`
        };
    });
    const sectionTrends = (rep.sectionTrends || []).map(mapSectionTrend);
    return {
        ...rep,
        key: rep.repId,
        rank: index + 1,
        latestDisplay: coachingScoreDisplay(rep.latestScore),
        deltaDisplay: coachingDeltaDisplay(rep.scoreDelta),
        arrow: coachingTrendArrow(rep.trend),
        trendClass: coachingTrendClass(rep.trend),
        monthlyScores,
        sectionTrends,
        hasSectionTrends: sectionTrends.length > 0,
        barFillStyle: modalBarFillStyle(rep.latestScore, 'pct', 100)
    };
}

function mapMessageRow(message, index) {
    const pos = Math.round((Number(message.positivePercent) || 0) * 100);
    const neu = Math.round((Number(message.neutralPercent) || 0) * 100);
    const neg = Math.max(0, 100 - pos - neu);
    return {
        key: message.messageKey || `message-${index}`,
        messageName: message.messageName,
        productName: message.productName,
        responseCount: message.responseCount || 0,
        sentimentLabel: message.sentimentLabel,
        positiveDisplay: sentimentPctDisplay(message.positivePercent),
        neutralDisplay: sentimentPctDisplay(message.neutralPercent),
        negativeDisplay: sentimentPctDisplay(message.negativePercent),
        positiveBarStyle: `width: ${pos}%;`,
        neutralBarStyle: `width: ${neu}%;`,
        negativeBarStyle: `width: ${neg}%;`,
        pieStyle: `background: conic-gradient(#2e844a 0 ${pos}%, #706e6b ${pos}% ${pos + neu}%, #ea001e ${pos + neu}% 100%);`,
        hasAggregateSentiment: !message.sentimentLabel,
        sentimentClass: sentimentClass(message.sentimentLabel),
        showProduct: Boolean(message.productName)
    };
}

const KPI_MODAL_CONFIG = {
    coverage: { label: 'Coverage %', summaryField: 'coveragePercent', repField: 'coveragePercent', format: 'pct' },
    visitRate: { label: 'Call Rate', summaryField: 'actualVisitRate', repField: 'actualVisitRate', format: 'pct' },
    amRate: { label: 'AM Visit Rate', summaryField: 'amVisitRate', repField: null, format: 'pct' },
    pmRate: { label: 'PM Visit Rate', summaryField: 'pmVisitRate', repField: null, format: 'pct' },
    single: { label: 'Single Visits', summaryField: 'singleVisitRate', repField: 'singleVisits', format: 'count' },
    double: { label: 'Double Visits', summaryField: 'doubleVisitRate', repField: 'doubleVisits', format: 'count' },
    coaching: { label: 'Coaching Days', summaryField: 'coachingDays', repField: 'coachingDays', format: 'num' },
    kol: { label: 'KOL Coverage', summaryField: 'kolCoveragePercent', repField: 'kolCoveragePercent', format: 'pct' },
    coached: { label: 'Reps Coached', summaryField: null, repField: 'coachingDays', format: 'num' }
};

export default class ManagementTeamKpiDashboard extends LightningElement {
    @track buOptions = [];
    @track lineOptions = [];
    @track districtOptions = [];
    @track selectedBu = 'ALL';
    @track selectedLine = 'ALL';
    @track selectedDistrict = 'ALL';
    @track summary;
    @track productPerformance = [];
    @track expandedKeys = new Set();
    @track isLoading = true;
    @track isProductLoading = false;
    @track errorMessage;
    @track activeKpiModal = null;
    @track isModalLoading = false;
    @track showBroadcastModal = false;
    @track broadcastSubject = '';
    @track broadcastBody = '';
    @track broadcastPriority = 'Normal';
    @track broadcastScope = 'All Business Units';
    @track broadcastError = null;
    @track broadcastSuccess = null;
    @track isPublishing = false;
    @track animateKey = 0;

    chartMax = { coverage: 100, callRate: 100, kol: 100 };

    async connectedCallback() {
        await Promise.all([this.loadBuOptions(), this.loadLineOptions(), this.loadDistrictOptions()]);
        await this.refreshKpis();
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

    get workforceTiles() {
        const s = this.summary || {};
        return [
            {
                id: 'reps',
                label: 'Field Reps',
                value: String(s.totalReps || 0),
                hint: 'Active reps in scope',
                icon: 'utility:user',
                tileClass: 'workforce-tile workforce-tile-clickable'
            },
            {
                id: 'managers',
                label: 'Managers',
                value: String(s.totalManagers || 0),
                hint: 'Managers in scope',
                icon: 'utility:groups',
                tileClass: 'workforce-tile workforce-tile-clickable'
            },
            {
                id: 'visits',
                label: 'Visits MTD',
                value: String(s.visitsThisMonth || 0),
                hint: 'Completed visits this month',
                icon: 'utility:event',
                tileClass: 'workforce-tile workforce-tile-clickable'
            },
            {
                id: 'clmLibrary',
                label: 'CLM Decks',
                value: `${s.clmPresentationsUsed || 0}/${s.totalClmPresentations || 0}`,
                hint: 'Unique decks used in library',
                icon: 'utility:file',
                tileClass: 'workforce-tile workforce-tile-clickable workforce-tile-clm'
            },
            {
                id: 'clmSessions',
                label: 'CLM Sessions',
                value: String(s.clmSessionsThisMonth || 0),
                hint: 'Completed CLM sessions MTD',
                icon: 'utility:play',
                tileClass: 'workforce-tile workforce-tile-clickable workforce-tile-clm'
            },
            {
                id: 'clmRoi',
                label: 'CLM Adoption',
                value: ratioPctDisplay(s.clmUsageRate),
                hint: `${s.clmSessionsThisMonth || 0} sessions on ${s.visitsThisMonth || 0} visits`,
                icon: 'utility:metrics',
                tileClass: 'workforce-tile workforce-tile-clickable workforce-tile-clm'
            }
        ];
    }

    get monthlyChartMeta() {
        const points = this.summary?.monthlyVisits || [];
        const max = Math.max(...points.map((p) => p.visitCount || 0), 1);
        return {
            max,
            yMaxLabel: String(max),
            yMidLabel: String(Math.round(max / 2)),
            yZeroLabel: '0'
        };
    }

    get monthlyVisitChart() {
        const points = this.summary?.monthlyVisits || [];
        const max = Math.max(...points.map((p) => p.visitCount || 0), 1);
        return points.map((point) => {
            const count = point.visitCount || 0;
            const heightPct = Math.max(Math.round((count / max) * 100), count > 0 ? 4 : 0);
            return {
                ...point,
                barStyle: `height: ${heightPct}%;`,
                countLabel: String(count),
                tooltip: `${count} visits · ${point.monthYearLabel || point.monthLabel}`
            };
        });
    }

    get hasMonthlyVisitChart() {
        return (this.summary?.monthlyVisits || []).length > 0;
    }

    get hasCoachingScoreChart() {
        return (this.summary?.coachingRepTrends || []).length > 0;
    }

    get primaryRings() {
        const s = this.summary || {};
        return [
            {
                id: 'coverage',
                label: 'Coverage',
                hint: 'Actual vs target visits',
                value: pctDisplay(s.coveragePercent),
                ringStroke: ringStroke(s.coveragePercent),
                ringClass: 'kpi-ring-fill kpi-ring-fill-blue',
                statusClass: statusClass(s.coveragePercent),
                cardClass: 'kpi-card kpi-card-ring kpi-card-clickable'
            },
            {
                id: 'visitRate',
                label: 'Call Rate',
                hint: 'Visits per working day',
                value: pctDisplay(s.actualVisitRate),
                ringStroke: ringStroke(s.actualVisitRate),
                ringClass: 'kpi-ring-fill kpi-ring-fill-green',
                statusClass: statusClass(s.actualVisitRate),
                cardClass: 'kpi-card kpi-card-ring kpi-card-clickable'
            },
            {
                id: 'kol',
                label: 'KOL Coverage',
                hint: 'Key opinion leader reach',
                value: pctDisplay(s.kolCoveragePercent),
                ringStroke: ringStroke(s.kolCoveragePercent),
                ringClass: 'kpi-ring-fill kpi-ring-fill-orange',
                statusClass: statusClass(s.kolCoveragePercent),
                cardClass: 'kpi-card kpi-card-ring kpi-card-clickable'
            }
        ];
    }

    get teamLatestCoachingScoreDisplay() {
        const points = this.summary?.coachingScoreTrend || [];
        const withData = [...points].reverse().find((point) => (Number(point.avgScore) || 0) > 0);
        return withData ? coachingScoreDisplay(withData.avgScore) : '—';
    }

    get secondaryStats() {
        const s = this.summary || {};
        return [
            {
                id: 'coaching',
                label: 'Coaching Score',
                value: this.teamLatestCoachingScoreDisplay,
                icon: 'utility:education',
                cardClass: 'stat-card stat-card-clickable'
            },
            {
                id: 'coached',
                label: 'Reps Coached',
                value: `${s.coachedReps || 0} / ${s.totalReps || 0}`,
                icon: 'utility:metrics',
                cardClass: 'stat-card stat-card-clickable'
            },
            {
                id: 'totalReps',
                label: 'Active Reps',
                value: String(s.totalReps || 0),
                icon: 'utility:groups',
                cardClass: 'stat-card'
            }
        ];
    }

    get visitMix() {
        const s = this.summary || {};
        const am = pctNumber(s.amVisitRate);
        const pm = pctNumber(s.pmVisitRate);
        const single = pctNumber(s.singleVisitRate);
        const double = pctNumber(s.doubleVisitRate);
        const amPmTotal = Math.max(am + pm, 1);
        return {
            am,
            pm,
            single,
            double,
            amBarStyle: `width: ${Math.round((am / amPmTotal) * 100)}%;`,
            pmBarStyle: `width: ${Math.round((pm / amPmTotal) * 100)}%;`,
            singleDonutStroke: donutStroke(single),
            doubleDonutStroke: donutStroke(double),
            singleDisplay: pctDisplay(s.singleVisitRate),
            doubleDisplay: pctDisplay(s.doubleVisitRate),
            amDisplay: pctDisplay(s.amVisitRate),
            pmDisplay: pctDisplay(s.pmVisitRate)
        };
    }

    get hierarchyChartRows() {
        const rows = this.summary?.drillDown || [];
        if (!rows.length) {
            return [];
        }
        this.computeChartMax(rows);
        return rows.map((row) => ({
            key: row.key,
            label: row.label,
            level: row.level,
            coverage: pctDisplay(row.coveragePercent),
            callRate: pctDisplay(row.actualVisitRate),
            coverageBarStyle: barHeight(row.coveragePercent, this.chartMax.coverage),
            callRateBarStyle: barHeight(row.actualVisitRate, this.chartMax.callRate),
            kolBarStyle: barHeight(row.kolCoveragePercent, this.chartMax.kol),
            cardClass: 'hierarchy-bar-group'
        }));
    }

    get hasHierarchyChart() {
        return this.hierarchyChartRows.length > 0;
    }

    get chartLegend() {
        return [
            { id: 'coverage', label: 'Coverage', swatchClass: 'legend-swatch coverage' },
            { id: 'callRate', label: 'Call Rate', swatchClass: 'legend-swatch call-rate' },
            { id: 'kol', label: 'KOL', swatchClass: 'legend-swatch kol' }
        ];
    }

    get drillDownRows() {
        return this.flattenDrillDown(this.summary?.drillDown || [], 0);
    }

    get hasDrillDown() {
        return this.drillDownRows.length > 0;
    }

    get probationByUserId() {
        const map = new Map();
        (this.summary?.probationReps || []).forEach((rep) => {
            map.set(rep.userId, rep);
        });
        return map;
    }

    get probationReps() {
        return (this.summary?.probationReps || []).map((r) => {
            const daysLeft = r.daysRemaining || 0;
            const progress = Math.min(100, Math.round(((90 - daysLeft) / 90) * 100));
            return {
                ...r,
                hireDateDisplay: r.hireDate,
                daysLabel: `${daysLeft} days left`,
                progressStyle: `width: ${progress}%;`,
                urgencyClass: daysLeft <= 14 ? 'probation-urgent' : daysLeft <= 30 ? 'probation-warn' : 'probation-ok'
            };
        });
    }

    get hasProbationReps() {
        return this.probationReps.length > 0;
    }

    get probationCountLabel() {
        const count = this.probationReps.length;
        return count === 1 ? '1 on probation' : `${count} on probation`;
    }

    get showProductSection() {
        return this.selectedBu !== 'ALL';
    }

    get hasProductPerformance() {
        return this.productPerformanceRows.length > 0;
    }

    get productPerformanceRows() {
        const maxVisits = Math.max(...(this.productPerformance || []).map((r) => r.visitCount || 0), 1);
        return (this.productPerformance || []).slice(0, 6).map((row) => {
            const visitPct = Math.round(((row.visitCount || 0) / maxVisits) * 100);
            return {
                ...row,
                visitBarStyle: `width: ${Math.max(visitPct, 4)}%;`,
                positiveDisplay: pctDisplay(row.positiveRate),
                cardClass: `${row.topBadge ? 'product-card product-card-highlight' : 'product-card'} product-card-clickable`
            };
        });
    }

    get showKpiModal() {
        return Boolean(this.activeKpiModal);
    }

    get kpiModalTitle() {
        return this.activeKpiModal?.title || '';
    }

    get kpiModalRows() {
        return this.activeKpiModal?.rows || [];
    }

    get kpiModalHasRows() {
        return this.kpiModalRows.length > 0;
    }

    get kpiModalMode() {
        return this.activeKpiModal?.mode || 'kpi';
    }

    get isClmModal() {
        return this.kpiModalMode === 'clm';
    }

    get isProductModal() {
        return this.kpiModalMode === 'product';
    }

    get productMessageRows() {
        return this.activeKpiModal?.messageSentiments || [];
    }

    get productTopReps() {
        return (this.activeKpiModal?.topReps || []).map((row, index) => ({
            ...row,
            key: row.repId,
            rank: index + 1,
            positiveDisplay: pctDisplay(row.positiveRate),
            detailLabel: `${row.detailCount || 0} details · ${row.clmSessionCount || 0} CLM`
        }));
    }

    get hasProductMessageRows() {
        return this.productMessageRows.length > 0;
    }

    get hasProductTopReps() {
        return this.productTopReps.length > 0;
    }

    get broadcastScopeOptions() {
        return [
            { label: 'All Business Units', value: 'All Business Units' },
            { label: 'Current Business Unit', value: 'Business Unit' },
            { label: 'Current Line', value: 'Line' },
            { label: 'Current District', value: 'District' }
        ];
    }

    get broadcastPriorityOptions() {
        return [
            { label: 'Normal', value: 'Normal' },
            { label: 'High', value: 'High' }
        ];
    }

    get isWorkforceModal() {
        return this.kpiModalMode === 'workforce';
    }

    get isCoachingModal() {
        return this.kpiModalMode === 'coaching';
    }

    get coachingModalRows() {
        return this.activeKpiModal?.repRows || [];
    }

    get hasCoachingModalRows() {
        return this.coachingModalRows.length > 0;
    }

    get kpiModalClass() {
        if (this.isClmModal || this.isProductModal || this.isCoachingModal) {
            return 'kpi-modal kpi-modal-wide';
        }
        return 'kpi-modal';
    }

    get clmDeckRows() {
        return this.activeKpiModal?.deckRows || [];
    }

    get clmSessionRows() {
        return this.activeKpiModal?.sessionRows || [];
    }

    get clmRepRows() {
        return this.activeKpiModal?.repRows || [];
    }

    get clmMessageSummary() {
        return this.activeKpiModal?.messageSummary || [];
    }

    get hasClmDeckRows() {
        return this.clmDeckRows.length > 0;
    }

    get hasClmSessionRows() {
        return this.clmSessionRows.length > 0;
    }

    get hasClmRepRows() {
        return this.clmRepRows.length > 0;
    }

    get hasClmMessageSummary() {
        return this.clmMessageSummary.length > 0;
    }

    get showClmDeckDrill() {
        return this.activeKpiModal?.id === 'clmLibrary';
    }

    get showClmSessionDrill() {
        return this.activeKpiModal?.id === 'clmSessions';
    }

    get showClmAdoptionDrill() {
        return this.activeKpiModal?.id === 'clmRoi';
    }

    get dashboardBodyClass() {
        return `dashboard-body animate-in-${this.animateKey}`;
    }

    computeChartMax(rows) {
        const max = { coverage: 100, callRate: 100, kol: 100 };
        rows.forEach((row) => {
            max.coverage = Math.max(max.coverage, pctNumber(row.coveragePercent));
            max.callRate = Math.max(max.callRate, pctNumber(row.actualVisitRate));
            max.kol = Math.max(max.kol, pctNumber(row.kolCoveragePercent));
        });
        this.chartMax = max;
    }

    async loadBuOptions() {
        try {
            const data = await getBusinessUnitOptions();
            this.buOptions = data.map((o) => ({ label: o.label, value: o.value }));
        } catch (e) {
            this.errorMessage = e.body?.message || 'Failed to load filters';
        }
    }

    async loadLineOptions() {
        try {
            const data = await getLineOptions({ buTerritoryId: this.selectedBu });
            this.lineOptions = data.map((o) => ({ label: o.label, value: o.value }));
        } catch (e) {
            this.lineOptions = [{ label: 'All Lines', value: 'ALL' }];
        }
    }

    async loadDistrictOptions() {
        try {
            const data = await getDistrictOptions({ lineTerritoryId: this.selectedLine });
            this.districtOptions = data.map((o) => ({ label: o.label, value: o.value }));
        } catch (e) {
            this.districtOptions = [{ label: 'All Districts', value: 'ALL' }];
        }
    }

    async refreshKpis() {
        this.isLoading = true;
        this.errorMessage = null;
        this.expandedKeys = new Set();
        try {
            this.summary = await getTeamKpis({
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
            const rootKeys = (this.summary?.drillDown || []).map((row) => row.key);
            this.expandedKeys = new Set(rootKeys);
            this.animateKey += 1;
            if (this.selectedBu !== 'ALL') {
                await this.refreshProductPerformance();
            } else {
                this.productPerformance = [];
            }
        } catch (e) {
            this.errorMessage = e.body?.message || 'Failed to load team KPIs';
        } finally {
            this.isLoading = false;
        }
    }

    async refreshProductPerformance() {
        this.isProductLoading = true;
        try {
            this.productPerformance = await getExecutiveBuProductPerformance({
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
        } catch (e) {
            this.productPerformance = [];
        } finally {
            this.isProductLoading = false;
        }
    }

    handleBuChange(event) {
        this.selectedBu = event.detail.value;
        this.selectedLine = 'ALL';
        this.selectedDistrict = 'ALL';
        this.loadLineOptions();
        this.loadDistrictOptions();
        this.refreshKpis();
    }

    handleLineChange(event) {
        this.selectedLine = event.detail.value;
        this.selectedDistrict = 'ALL';
        this.loadDistrictOptions();
        this.refreshKpis();
    }

    handleDistrictChange(event) {
        this.selectedDistrict = event.detail.value;
        this.refreshKpis();
    }

    handleKpiClick(event) {
        const kpiId = event.currentTarget.dataset.kpi;
        if (!kpiId || kpiId === 'totalReps') {
            return;
        }
        if (kpiId === 'coaching' || kpiId === 'coached') {
            this.openCoachingTrendModal();
            return;
        }
        this.openKpiModal(kpiId);
    }

    handleWorkforceTileClick(event) {
        const tileId = event.currentTarget.dataset.tile;
        if (!tileId) {
            return;
        }
        if (tileId === 'clmLibrary' || tileId === 'clmSessions' || tileId === 'clmRoi') {
            this.openClmModal(tileId);
            return;
        }
        if (tileId === 'reps' || tileId === 'managers') {
            this.openWorkforceModal(tileId);
            return;
        }
        if (tileId === 'visits') {
            this.openVisitsModal();
        }
    }

    handleHierarchyBarClick(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) {
            return;
        }
        const next = new Set(this.expandedKeys);
        next.add(key);
        this.expandedKeys = next;
        const drillSection = this.template.querySelector('.drill-section');
        if (drillSection) {
            drillSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    handleToggleRow(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.expandedKeys);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this.expandedKeys = next;
    }

    handleCloseModal() {
        this.activeKpiModal = null;
        this.isModalLoading = false;
    }

    handleCloseBroadcastModal() {
        this.showBroadcastModal = false;
        this.broadcastError = null;
        this.broadcastSuccess = null;
    }

    openBroadcastModal() {
        this.broadcastSubject = '';
        this.broadcastBody = '';
        this.broadcastPriority = 'Normal';
        this.broadcastScope = 'All Business Units';
        this.broadcastError = null;
        this.broadcastSuccess = null;
        this.showBroadcastModal = true;
    }

    handleBroadcastSubjectChange(event) {
        this.broadcastSubject = event.detail.value;
    }

    handleBroadcastBodyChange(event) {
        this.broadcastBody = event.detail.value;
    }

    handleBroadcastPriorityChange(event) {
        this.broadcastPriority = event.detail.value;
    }

    handleBroadcastScopeChange(event) {
        this.broadcastScope = event.detail.value;
    }

    async handlePublishBroadcast() {
        this.isPublishing = true;
        this.broadcastError = null;
        this.broadcastSuccess = null;
        try {
            const buId = this.broadcastScope === 'Business Unit' ? this.selectedBu : null;
            const lineId = this.broadcastScope === 'Line' ? this.selectedLine : null;
            const districtId = this.broadcastScope === 'District' ? this.selectedDistrict : null;
            const result = await publishHomeOfficeMessage({
                subject: this.broadcastSubject,
                body: this.broadcastBody,
                audienceScope: this.broadcastScope,
                buTerritoryId: buId === 'ALL' ? null : buId,
                lineTerritoryId: lineId === 'ALL' ? null : lineId,
                districtTerritoryId: districtId === 'ALL' ? null : districtId,
                priority: this.broadcastPriority
            });
            this.broadcastSuccess = result.message;
            this.broadcastSubject = '';
            this.broadcastBody = '';
        } catch (e) {
            this.broadcastError = e.body?.message || 'Failed to publish message';
        } finally {
            this.isPublishing = false;
        }
    }

    async handleProductClick(event) {
        const productId = event.currentTarget.dataset.productId;
        if (!productId) {
            return;
        }
        const product = (this.productPerformance || []).find((row) => row.productId === productId);
        this.activeKpiModal = {
            id: productId,
            mode: 'product',
            title: product?.productName || 'Product Performance',
            teamLabel: 'Loading product insights…',
            productId,
            imageUrl: product?.imageUrl,
            messageSentiments: [],
            topReps: []
        };
        this.isModalLoading = true;
        try {
            const data = await getProductPerformanceDrillDown({
                productId,
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
            this.activeKpiModal = {
                id: productId,
                mode: 'product',
                title: data.productName,
                teamLabel: data.summaryLabel,
                productId: data.productId,
                imageUrl: data.imageUrl,
                visitCount: data.visitCount,
                clmSessionCount: data.clmSessionCount,
                positiveDisplay: pctDisplay(data.positiveRate),
                messageSentiments: (data.messageSentiments || []).map(mapMessageRow),
                topReps: data.topReps || []
            };
        } catch (e) {
            this.activeKpiModal = {
                id: productId,
                mode: 'product',
                title: product?.productName || 'Product Performance',
                teamLabel: e.body?.message || 'Failed to load product drill-down',
                messageSentiments: [],
                topReps: []
            };
        } finally {
            this.isModalLoading = false;
        }
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }

    async openCoachingTrendModal() {
        this.activeKpiModal = {
            id: 'coaching',
            mode: 'coaching',
            title: 'Coaching Score Trends',
            teamLabel: 'Loading coaching trends…',
            teamLatestScore: null,
            teamScoreDelta: null,
            repRows: []
        };
        this.isModalLoading = true;
        try {
            const data = await getCoachingTrendDrillDown({
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
            this.activeKpiModal = {
                id: 'coaching',
                mode: 'coaching',
                title: 'Coaching Score Trends',
                teamLabel: data.summaryLabel,
                teamLatestScore: data.teamLatestScore,
                teamScoreDelta: data.teamScoreDelta,
                teamTrendLabel: coachingDeltaDisplay(data.teamScoreDelta),
                teamTrendClass: coachingTrendClass(data.teamTrend),
                teamTrendArrow: coachingTrendArrow(data.teamTrend),
                teamLatestDisplay: coachingScoreDisplay(data.teamLatestScore),
                repRows: (data.repRows || []).map(mapCoachingRepRow)
            };
        } catch (e) {
            this.activeKpiModal = {
                id: 'coaching',
                mode: 'coaching',
                title: 'Coaching Score Trends',
                teamLabel: e.body?.message || 'Failed to load coaching trends',
                repRows: []
            };
        } finally {
            this.isModalLoading = false;
        }
    }

    openKpiModal(kpiId) {
        const config = KPI_MODAL_CONFIG[kpiId];
        if (!config) {
            return;
        }

        const s = this.summary || {};
        let teamValue;
        if (kpiId === 'coached') {
            teamValue = `${s.coachedReps || 0} / ${s.totalReps || 0}`;
        } else if (config.format === 'pct') {
            teamValue = pctDisplay(s[config.summaryField]);
        } else if (config.format === 'count') {
            teamValue = pctDisplay(s[config.summaryField]);
        } else {
            teamValue = numDisplay(s[config.summaryField], 0);
        }

        if (!config.repField) {
            this.activeKpiModal = {
                id: kpiId,
                mode: 'kpi',
                title: `${config.label} — Team View`,
                teamLabel: `Team average: ${teamValue}`,
                rows: []
            };
            return;
        }

        const repRows = this.collectRepRows(this.summary?.drillDown || []);
        const sorted = [...repRows].sort((a, b) => {
            const av = a[config.repField] || 0;
            const bv = b[config.repField] || 0;
            return bv - av;
        });

        const maxVal = Math.max(...sorted.map((r) => Number(r[config.repField]) || 0), 1);

        const probationByUserId = this.probationByUserId;
        const rows = sorted.map((row, index) => {
            const raw = row[config.repField];
            let display;
            if (config.format === 'pct') {
                display = pctDisplay(raw);
            } else if (config.format === 'count') {
                display = String(raw || 0);
            } else {
                display = numDisplay(raw, 0);
            }
            const probation = probationByUserId.get(row.employeeId);
            const daysLeft = probation?.daysRemaining;
            return {
                key: row.key,
                rank: index + 1,
                label: row.label,
                level: row.level,
                value: display,
                barFillStyle: modalBarFillStyle(raw, config.format, maxVal),
                showBar: config.format === 'pct' || config.format === 'count' || config.format === 'num',
                isOnProbation: Boolean(probation),
                probationLabel: daysLeft != null ? `Probation · ${daysLeft}d left` : '',
                probationClass:
                    daysLeft != null && daysLeft <= 14
                        ? 'probation-badge probation-badge-urgent'
                        : 'probation-badge'
            };
        });

        this.activeKpiModal = {
            id: kpiId,
            mode: 'kpi',
            title: `${config.label} — Rep Breakdown`,
            teamLabel: `Team average: ${teamValue}`,
            rows
        };
    }

    async openClmModal(tileId) {
        const titles = {
            clmLibrary: 'CLM Deck Utilization',
            clmSessions: 'CLM Sessions',
            clmRoi: 'CLM Adoption by Rep'
        };
        this.activeKpiModal = {
            id: tileId,
            mode: 'clm',
            title: titles[tileId] || 'CLM Drill-Down',
            teamLabel: 'Loading CLM details…',
            deckRows: [],
            sessionRows: [],
            repRows: [],
            messageSummary: []
        };
        this.isModalLoading = true;
        try {
            const data = await getTeamClmDrillDown({
                drillType: tileId,
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
            this.activeKpiModal = {
                id: tileId,
                mode: 'clm',
                title: titles[tileId] || 'CLM Drill-Down',
                teamLabel: data.summaryLabel,
                deckRows: (data.deckRows || []).map((row) => ({
                    ...row,
                    key: row.presentationId,
                    statusLabel: row.isUsed ? 'Used' : 'Unused',
                    statusClass: row.isUsed ? 'clm-status-used' : 'clm-status-unused',
                    messages: (row.messages || []).map(mapMessageRow),
                    hasMessages: (row.messages || []).length > 0
                })),
                sessionRows: (data.sessionRows || []).map((row) => ({
                    ...row,
                    key: row.sessionId,
                    metaLabel: [row.visitDateLabel, row.repName, row.accountName].filter(Boolean).join(' · '),
                    messages: (row.messages || []).map(mapMessageRow),
                    hasMessages: (row.messages || []).length > 0
                })),
                repRows: (data.repRows || []).map((row, index) => ({
                    ...row,
                    key: row.repId,
                    rank: index + 1,
                    adoptionDisplay: ratioPctDisplay(row.adoptionPercent),
                    messages: (row.messages || []).map(mapMessageRow),
                    hasMessages: (row.messages || []).length > 0
                })),
                messageSummary: (data.messageSummary || []).map(mapMessageRow)
            };
        } catch (e) {
            this.activeKpiModal = {
                id: tileId,
                mode: 'clm',
                title: titles[tileId] || 'CLM Drill-Down',
                teamLabel: e.body?.message || 'Failed to load CLM drill-down',
                deckRows: [],
                sessionRows: [],
                repRows: [],
                messageSummary: []
            };
        } finally {
            this.isModalLoading = false;
        }
    }

    async openWorkforceModal(tileId) {
        const isManagers = tileId === 'managers';
        this.activeKpiModal = {
            id: tileId,
            mode: 'workforce',
            title: isManagers ? 'Managers in Scope' : 'Field Reps in Scope',
            teamLabel: 'Loading roster…',
            rows: []
        };
        this.isModalLoading = true;
        try {
            const roster = await getWorkforceRoster({
                workforceType: isManagers ? 'managers' : 'reps',
                buTerritoryId: this.selectedBu,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
            const rows = (roster || []).map((row, index) => ({
                key: row.employeeUserId,
                rank: index + 1,
                label: row.employeeName,
                sublabel: [row.roleLabel, row.territoryLabel].filter(Boolean).join(' · '),
                value: pctDisplay(row.clmAdoptionPercent),
                metricHint: 'CLM adoption',
                coverageDisplay: pctDisplay(row.coveragePercent),
                callRateDisplay: pctDisplay(row.actualVisitRate)
            }));
            this.activeKpiModal = {
                id: tileId,
                mode: 'workforce',
                title: isManagers ? 'Managers in Scope' : 'Field Reps in Scope',
                teamLabel: `${rows.length} ${isManagers ? 'managers' : 'reps'} in selected scope`,
                rows
            };
        } catch (e) {
            this.activeKpiModal = {
                id: tileId,
                mode: 'workforce',
                title: isManagers ? 'Managers in Scope' : 'Field Reps in Scope',
                teamLabel: e.body?.message || 'Failed to load roster',
                rows: []
            };
        } finally {
            this.isModalLoading = false;
        }
    }

    openVisitsModal() {
        const repRows = this.collectRepRows(this.summary?.drillDown || []);
        const sorted = [...repRows].sort((a, b) => {
            const av = (a.singleVisits || 0) + (a.doubleVisits || 0);
            const bv = (b.singleVisits || 0) + (b.doubleVisits || 0);
            return bv - av;
        });
        const maxVal = Math.max(
            ...sorted.map((row) => (row.singleVisits || 0) + (row.doubleVisits || 0)),
            1
        );
        const rows = sorted.map((row, index) => {
            const totalVisits = (row.singleVisits || 0) + (row.doubleVisits || 0);
            return {
                key: row.key,
                rank: index + 1,
                label: row.label,
                sublabel: `${row.singleVisits || 0} single · ${row.doubleVisits || 0} double`,
                value: String(totalVisits),
                barFillStyle: modalBarFillStyle(totalVisits, 'count', maxVal),
                showBar: true
            };
        });
        this.activeKpiModal = {
            id: 'visits',
            mode: 'workforce',
            title: 'Visits MTD by Rep',
            teamLabel: `${this.summary?.visitsThisMonth || 0} completed visits across team`,
            rows
        };
    }

    collectRepRows(rows, output = []) {
        rows.forEach((row) => {
            if (row.level === 'Rep') {
                output.push(row);
            }
            if (row.children?.length) {
                this.collectRepRows(row.children, output);
            }
        });
        return output;
    }

    flattenDrillDown(rows, depth) {
        const output = [];
        rows.forEach((row) => {
            const hasChildren = Array.isArray(row.children) && row.children.length > 0;
            const isExpanded = this.expandedKeys.has(row.key);
            const products = row.products || [];
            const visibleProducts = products.slice(0, 4);
            const overflowCount = Math.max(products.length - visibleProducts.length, 0);

            output.push({
                key: row.key,
                label: row.label,
                level: row.level,
                depth,
                indentStyle: `padding-left: ${0.75 + depth * 1.25}rem;`,
                coverageDisplay: pctDisplay(row.coveragePercent),
                callRateDisplay: pctDisplay(row.actualVisitRate),
                kolDisplay: pctDisplay(row.kolCoveragePercent),
                coachingDisplay: numDisplay(row.coachingDays, 0),
                hasCoachingScore: row.latestCoachingScore != null,
                coachingScoreDisplay: coachingScoreDisplay(row.latestCoachingScore),
                coachingDeltaDisplay: coachingDeltaDisplay(row.coachingScoreDelta),
                coachingTrendClass: coachingTrendClass(row.coachingTrend),
                coachingTrendArrow: coachingTrendArrow(row.coachingTrend),
                coachingSectionChips: (row.coachingSectionTrends || []).map(mapSectionTrend),
                hasCoachingSections: (row.coachingSectionTrends || []).length > 0,
                coverageBarStyle: `width: ${Math.min(100, pctNumber(row.coveragePercent))}%;`,
                callRateBarStyle: `width: ${Math.min(100, pctNumber(row.actualVisitRate))}%;`,
                coverageStatus: statusClass(row.coveragePercent),
                callRateStatus: statusClass(row.actualVisitRate),
                hasChildren,
                isExpanded,
                toggleIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                rowClass: `drill-row drill-row-${(row.level || 'node').toLowerCase()}`,
                visibleProducts,
                overflowCount,
                hasProducts: products.length > 0,
                showOverflow: overflowCount > 0
            });

            if (hasChildren && isExpanded) {
                output.push(...this.flattenDrillDown(row.children, depth + 1));
            }
        });
        return output;
    }
}