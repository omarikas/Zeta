import { LightningElement, track } from 'lwc';
import getExecutiveBuComparison from '@salesforce/apex/ManagementKpiController.getExecutiveBuComparison';
import getExecutiveOrgSnapshot from '@salesforce/apex/ManagementKpiController.getExecutiveOrgSnapshot';
import getExecutiveBuProductPerformance from '@salesforce/apex/ManagementKpiController.getExecutiveBuProductPerformance';
import getTeamKpis from '@salesforce/apex/ManagementKpiController.getTeamKpis';
import getLineOptions from '@salesforce/apex/ManagementKpiController.getLineOptions';
import getDistrictOptions from '@salesforce/apex/ManagementKpiController.getDistrictOptions';
import getWorkforceRoster from '@salesforce/apex/ManagementKpiController.getWorkforceRoster';
import getEmployeeAttendanceDetail from '@salesforce/apex/ManagementKpiController.getEmployeeAttendanceDetail';

const WORKFORCE_TILE_IDS = new Set(['reps', 'managers']);
const RING_CIRCUMFERENCE = 2 * Math.PI * 22;
const PRODUCT_SORT_OPTIONS = [
    { label: 'Top Performance', value: 'performance' },
    { label: 'Most Visits', value: 'visits' },
    { label: 'Most CLM', value: 'clm' },
    { label: 'Best Feedback', value: 'feedback' }
];

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

function ratioPctDisplay(value) {
    return `${Math.round((Number(value) || 0) * 100)}%`;
}

function numDisplay(value, digits = 0) {
    if (value == null) {
        return '0';
    }
    return Number(value).toFixed(digits);
}

function formatCurrency(value) {
    if (value == null || value === '') {
        return '—';
    }
    return new Intl.NumberFormat('en-EG', {
        style: 'currency',
        currency: 'EGP',
        maximumFractionDigits: 0
    }).format(Number(value));
}

function eligibilityBadgeClass(isEligible) {
    return isEligible ? 'eligibility-pill eligibility-pill-eligible' : 'eligibility-pill eligibility-pill-ineligible';
}

function eligibilitySummary(effective, suggested, overrideValue) {
    if (overrideValue && overrideValue !== 'Use Suggested') {
        return effective ? 'Eligible (override)' : 'Ineligible (override)';
    }
    if (effective) {
        return 'Eligible';
    }
    return suggested ? 'Eligible' : 'Not eligible';
}

function ringStroke(percent) {
    const p = Math.min(100, Math.max(0, pctNumber(percent)));
    const offset = RING_CIRCUMFERENCE - (p / 100) * RING_CIRCUMFERENCE;
    return `stroke-dasharray: ${RING_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`;
}

function employeeInitials(name) {
    if (!name) {
        return '?';
    }
    return name
        .trim()
        .split(/\s+/)
        .filter(Boolean)
        .map((part) => part.charAt(0))
        .slice(0, 2)
        .join('')
        .toUpperCase();
}

function findDimensionLeader(rows, getValue, minValue = 0) {
    let leader = null;
    let leaderValue = minValue;
    (rows || []).forEach((row) => {
        const value = getValue(row);
        if (value < minValue) {
            return;
        }
        if (
            leader == null ||
            value > leaderValue ||
            (value === leaderValue && row.employeeName < leader.employeeName)
        ) {
            leader = row;
            leaderValue = value;
        }
    });
    return leader == null ? null : { row: leader, value: leaderValue };
}

const REP_TOP_PERFORMER_DIMENSIONS = [
    {
        id: 'coverage',
        icon: 'utility:target',
        accentClass: 'top-performer-accent-coverage',
        dimensionLabel: 'Visit Coverage',
        leadingLabel: 'Leading in Visit Coverage',
        getValue: (row) => pctNumber(row.coveragePercent),
        formatValue: (value) => `${value}%`,
        minValue: 1
    },
    {
        id: 'callRate',
        icon: 'utility:call',
        accentClass: 'top-performer-accent-call-rate',
        dimensionLabel: 'Call Rate',
        leadingLabel: 'Leading in Call Rate',
        getValue: (row) => Number(row.actualVisitRate) || 0,
        formatValue: (value) => `${Number(value).toFixed(1)} calls/day`,
        minValue: 0.1
    },
    {
        id: 'callAchievement',
        icon: 'utility:metrics',
        accentClass: 'top-performer-accent-achievement',
        dimensionLabel: 'Call Plan Achievement',
        leadingLabel: 'Leading in Call Plan Achievement',
        getValue: (row) => Math.round(Number(row.callAchievementPercent) || 0),
        formatValue: (value) => `${value}% of plan`,
        minValue: 1
    },
    {
        id: 'kolCoverage',
        icon: 'utility:people',
        accentClass: 'top-performer-accent-kol',
        dimensionLabel: 'KOL Coverage',
        leadingLabel: 'Leading in KOL Coverage',
        getValue: (row) => pctNumber(row.kolCoveragePercent),
        formatValue: (value) => `${value}%`,
        minValue: 1
    },
    {
        id: 'clmAdoption',
        icon: 'utility:file',
        accentClass: 'top-performer-accent-clm',
        dimensionLabel: 'CLM Adoption',
        leadingLabel: 'Leading in CLM Adoption',
        getValue: (row) => pctNumber(row.clmAdoptionPercent),
        formatValue: (value) => `${value}%`,
        minValue: 1
    }
];

const MANAGER_TOP_PERFORMER_DIMENSIONS = [
    {
        id: 'coaching',
        icon: 'utility:groups',
        accentClass: 'top-performer-accent-coaching',
        dimensionLabel: 'Coaching Days',
        leadingLabel: 'Leading in Coaching Days',
        getValue: (row) => Number(row.coachingDays) || 0,
        formatValue: (value) => `${Math.round(value)} days`,
        minValue: 1
    },
    {
        id: 'coverage',
        icon: 'utility:target',
        accentClass: 'top-performer-accent-coverage',
        dimensionLabel: 'Visit Coverage',
        leadingLabel: 'Leading in Visit Coverage',
        getValue: (row) => pctNumber(row.coveragePercent),
        formatValue: (value) => `${value}%`,
        minValue: 1
    },
    {
        id: 'kolCoverage',
        icon: 'utility:people',
        accentClass: 'top-performer-accent-kol',
        dimensionLabel: 'KOL Coverage',
        leadingLabel: 'Leading in KOL Coverage',
        getValue: (row) => pctNumber(row.kolCoveragePercent),
        formatValue: (value) => `${value}%`,
        minValue: 1
    },
    {
        id: 'callRate',
        icon: 'utility:call',
        accentClass: 'top-performer-accent-call-rate',
        dimensionLabel: 'Call Rate',
        leadingLabel: 'Leading in Call Rate',
        getValue: (row) => Number(row.actualVisitRate) || 0,
        formatValue: (value) => `${Number(value).toFixed(1)} calls/day`,
        minValue: 0.1
    }
];

function buildTopPerformers(rows, workforceType, selectedEmployeeId) {
    if (!rows || rows.length === 0) {
        return [];
    }
    const dimensions =
        workforceType === 'managers' ? MANAGER_TOP_PERFORMER_DIMENSIONS : REP_TOP_PERFORMER_DIMENSIONS;
    const output = [];
    dimensions.forEach((dimension) => {
        const result = findDimensionLeader(rows, dimension.getValue, dimension.minValue);
        if (!result) {
            return;
        }
        const isSelected = result.row.employeeUserId === selectedEmployeeId;
        output.push({
            key: dimension.id,
            employeeUserId: result.row.employeeUserId,
            employeeName: result.row.employeeName,
            initials: employeeInitials(result.row.employeeName),
            roleLabel: result.row.roleLabel,
            icon: dimension.icon,
            cardClass: `top-performer-card ${dimension.accentClass}${
                isSelected ? ' top-performer-card-selected' : ''
            }`,
            dimensionLabel: dimension.dimensionLabel,
            leadingLabel: dimension.leadingLabel,
            metricDisplay: dimension.formatValue(result.value),
            isSelected
        });
    });
    return output.slice(0, 5);
}

function barHeight(value, maxValue) {
    const max = Math.max(maxValue, 1);
    const pct = Math.min(100, Math.round((pctNumber(value) / max) * 100));
    return `height: ${Math.max(pct, 4)}%;`;
}

export default class CLevelsExecutiveHome extends LightningElement {
    @track buComparison = [];
    @track orgSnapshot;
    @track selectedBuId;
    @track selectedBuName = 'All Business Units';
    @track selectedLine = 'ALL';
    @track selectedDistrict = 'ALL';
    @track lineOptions = [];
    @track districtOptions = [];
    @track summary;
    @track productPerformance = [];
    @track productSort = 'performance';
    @track expandedKeys = new Set();
    @track isLoading = true;
    @track isDrillLoading = false;
    @track isProductLoading = false;
    @track errorMessage;
    @track activeWorkforceType;
    @track workforceRows = [];
    @track selectedWorkforceEmployeeId;
    @track attendanceDetail;
    @track isWorkforceLoading = false;
    @track isAttendanceLoading = false;

    productSortOptions = PRODUCT_SORT_OPTIONS;
    chartMax = { coverage: 100, callRate: 100, kol: 100, coaching: 1 };

    async connectedCallback() {
        await this.loadComparison();
    }

    get hasBuData() {
        return this.buComparison.length > 0;
    }

    get orgStatTiles() {
        const s = this.orgSnapshot || {};
        return [
            {
                id: 'reps',
                label: 'Field Reps',
                value: String(s.totalReps || 0),
                hint: 'Medical reps in territory — click to drill down',
                icon: 'utility:user',
                tileClass: 'org-stat-tile org-stat-reps org-stat-clickable',
                isClickable: true
            },
            {
                id: 'managers',
                label: 'Managers',
                value: String(s.totalManagers || 0),
                hint: 'District & region managers — click to drill down',
                icon: 'utility:groups',
                tileClass: 'org-stat-tile org-stat-managers org-stat-clickable',
                isClickable: true
            },
            {
                id: 'visits',
                label: 'Visits This Month',
                value: String(s.visitsThisMonth || 0),
                hint: 'Completed field visits MTD',
                icon: 'utility:event',
                tileClass: 'org-stat-tile org-stat-visits',
                isClickable: false
            },
            {
                id: 'clmLibrary',
                label: 'CLM Decks',
                value: String(s.totalClmPresentations || 0),
                hint: 'Active CLM presentations in library',
                icon: 'utility:file',
                tileClass: 'org-stat-tile org-stat-clm',
                isClickable: false
            },
            {
                id: 'clmUsage',
                label: 'CLM Adoption',
                value: ratioPctDisplay(s.clmUsageRate),
                hint: `${s.clmSessionsThisMonth || 0} sessions on ${s.visitsThisMonth || 0} visits`,
                icon: 'utility:metrics',
                tileClass: 'org-stat-tile org-stat-roi',
                isClickable: false
            },
            {
                id: 'coachingDoubleVisits',
                label: 'Coaching Double Visits',
                value: String(s.coachingDoubleVisits || 0),
                hint: 'Completed coaching double visits MTD',
                icon: 'utility:groups',
                tileClass: 'org-stat-tile org-stat-double-visits',
                isClickable: false
            }
        ];
    }

    get monthlyChartMeta() {
        const points = this.orgSnapshot?.monthlyVisits || [];
        const max = Math.max(...points.map((p) => p.visitCount || 0), 1);
        return {
            max,
            yMaxLabel: String(max),
            yMidLabel: String(Math.round(max / 2)),
            yZeroLabel: '0'
        };
    }

    get monthlyVisitChart() {
        const points = this.orgSnapshot?.monthlyVisits || [];
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
        return (this.orgSnapshot?.monthlyVisits || []).length > 0;
    }

    get showWorkforcePanel() {
        return Boolean(this.activeWorkforceType);
    }

    get workforcePanelTitle() {
        const label = this.activeWorkforceType === 'managers' ? 'Managers' : 'Field Reps';
        return `${label} — ${this.workforceScopeLabel}`;
    }

    get workforceScopeLabel() {
        const parts = [this.selectedBuName];
        const lineLabel = this.lineOptions.find((opt) => opt.value === this.selectedLine)?.label;
        const districtLabel = this.districtOptions.find((opt) => opt.value === this.selectedDistrict)?.label;
        if (lineLabel && this.selectedLine !== 'ALL') {
            parts.push(lineLabel);
        }
        if (districtLabel && this.selectedDistrict !== 'ALL') {
            parts.push(districtLabel);
        }
        return parts.filter(Boolean).join(' · ');
    }

    get hasWorkforceRows() {
        return this.decoratedWorkforceRows.length > 0;
    }

    get hasTopPerformers() {
        return this.topPerformers.length > 0;
    }

    get topPerformers() {
        return buildTopPerformers(
            this.workforceRows,
            this.activeWorkforceType,
            this.selectedWorkforceEmployeeId
        );
    }

    get showWorkforceSalaryTotal() {
        const rows = this.workforceRows || [];
        return rows.length > 0 && rows[0].canViewSalary;
    }

    get workforceSalaryTotalDisplay() {
        const total = (this.workforceRows || []).reduce(
            (sum, row) => sum + (Number(row.baseSalary) || 0),
            0
        );
        return formatCurrency(total);
    }

    get decoratedWorkforceRows() {
        return (this.workforceRows || []).map((row) => ({
            ...row,
            rowKey: row.employeeUserId,
            rowClass:
                row.employeeUserId === this.selectedWorkforceEmployeeId
                    ? 'workforce-row workforce-row-selected'
                    : 'workforce-row',
            coverageDisplay: pctDisplay(row.coveragePercent),
            callRateDisplay: numDisplay(row.actualVisitRate, 1),
            coachingDisplay: numDisplay(row.coachingDays, 0),
            salaryDisplay: row.canViewSalary ? formatCurrency(row.baseSalary) : 'Restricted',
            bonusClass: eligibilityBadgeClass(row.effectiveBonusEligible),
            bonusLabel: eligibilitySummary(
                row.effectiveBonusEligible,
                row.suggestedBonusEligible,
                row.bonusOverride
            ),
            commissionClass: eligibilityBadgeClass(row.effectiveCommissionEligible),
            commissionLabel: eligibilitySummary(
                row.effectiveCommissionEligible,
                row.suggestedCommissionEligible,
                row.commissionOverride
            )
        }));
    }

    get attendanceCriteria() {
        const criteria = this.attendanceDetail?.compensation?.bonus?.criteria || [];
        return criteria.map((item, index) => ({
            ...item,
            key: `criterion-${index}`,
            statusClass: item.passed ? 'criterion-pass' : 'criterion-fail',
            statusIcon: item.passed ? 'utility:success' : 'utility:close'
        }));
    }

    get attendanceDayRows() {
        return (this.attendanceDetail?.dayRows || []).map((row, index) => ({
            ...row,
            key: `day-${index}`,
            rowClass: row.noActivityDays > 0 ? 'attendance-day attendance-day-no-activity' : 'attendance-day',
            workingDayDisplay: row.calendarWorkingDay ? 'Yes' : 'No',
            checkInDisplay: row.checkInLabel || '—',
            checkOutDisplay: row.checkOutLabel || '—',
            hoursWorkedDisplay: row.hoursWorkedLabel || '—',
            compliantDisplay: row.isCompliant ? 'Yes' : (row.hoursWorked != null ? 'No' : '—'),
            compliantClass: row.isCompliant
                ? 'attendance-compliant attendance-compliant-yes'
                : (row.hoursWorked != null ? 'attendance-compliant attendance-compliant-no' : 'attendance-compliant')
        }));
    }

    get attendanceCompensation() {
        const comp = this.attendanceDetail?.compensation;
        if (!comp) {
            return null;
        }
        const bonus = comp.bonus || {};
        return {
            salaryDisplay: comp.canViewSalary ? formatCurrency(comp.baseSalary) : 'Restricted',
            bonusClass: eligibilityBadgeClass(bonus.effectiveBonusEligible),
            bonusLabel: eligibilitySummary(
                bonus.effectiveBonusEligible,
                bonus.suggestedBonusEligible,
                bonus.bonusOverride
            ),
            commissionClass: eligibilityBadgeClass(bonus.effectiveCommissionEligible),
            commissionLabel: eligibilitySummary(
                bonus.effectiveCommissionEligible,
                bonus.suggestedCommissionEligible,
                bonus.commissionOverride
            )
        };
    }

    get hasAttendanceDetail() {
        return Boolean(this.attendanceDetail?.employeeUserId);
    }

    get selectedBuSummary() {
        if (!this.selectedBuId) {
            return null;
        }
        return this.buComparison.find((bu) => bu.id === this.selectedBuId);
    }

    get kpiRings() {
        const s = this.summary || this.selectedBuSummary || {};
        return [
            {
                id: 'coverage',
                label: 'Coverage',
                value: pctDisplay(s.coveragePercent),
                ringStroke: ringStroke(s.coveragePercent),
                ringClass: 'kpi-ring-fill-blue'
            },
            {
                id: 'callRate',
                label: 'Call Rate',
                value: pctDisplay(s.actualVisitRate),
                ringStroke: ringStroke(s.actualVisitRate),
                ringClass: 'kpi-ring-fill-green'
            },
            {
                id: 'kol',
                label: 'KOL Coverage',
                value: pctDisplay(s.kolCoveragePercent),
                ringStroke: ringStroke(s.kolCoveragePercent),
                ringClass: 'kpi-ring-fill-orange'
            }
        ];
    }

    get coachingSummary() {
        const s = this.summary || this.selectedBuSummary || {};
        return {
            days: numDisplay(s.coachingDays, 0),
            repsCoached: `${s.coachedReps || 0} / ${s.totalReps || 0}`
        };
    }

    get chartLegend() {
        return [
            { id: 'coverage', label: 'Coverage', swatchClass: 'legend-swatch coverage' },
            { id: 'callRate', label: 'Call Rate', swatchClass: 'legend-swatch call-rate' },
            { id: 'kol', label: 'KOL Coverage', swatchClass: 'legend-swatch kol' }
        ];
    }

    get hasProductPerformance() {
        return this.productPerformanceRows.length > 0;
    }

    get productPerformanceRows() {
        const rows = [...(this.productPerformance || [])];
        rows.sort((left, right) => {
            if (this.productSort === 'visits') {
                return (right.visitCount || 0) - (left.visitCount || 0);
            }
            if (this.productSort === 'clm') {
                return (right.clmSessionCount || 0) - (left.clmSessionCount || 0);
            }
            if (this.productSort === 'feedback') {
                return (right.positiveRate || 0) - (left.positiveRate || 0);
            }
            return (right.performanceScore || 0) - (left.performanceScore || 0);
        });

        const maxVisits = Math.max(...rows.map((row) => row.visitCount || 0), 1);
        return rows.map((row) => {
            const visitPct = Math.round(((row.visitCount || 0) / maxVisits) * 100);
            const sentimentTotal = (row.positiveCount || 0) + (row.neutralCount || 0) + (row.negativeCount || 0);
            return {
                ...row,
                visitBarStyle: `width: ${Math.max(visitPct, 4)}%;`,
                positiveDisplay: pctDisplay(row.positiveRate),
                metaLabel: [row.family, row.therapyArea].filter(Boolean).join(' · '),
                hasMeta: Boolean(row.family || row.therapyArea),
                cardClass: `product-performance-card${row.topBadge ? ' product-performance-card-highlight' : ''}`,
                badgeClass: `product-badge product-badge-${(row.topBadge || 'default').replace(/\s+/g, '-').toLowerCase()}`,
                sentimentSummary:
                    sentimentTotal > 0
                        ? `${row.positiveCount || 0}+ / ${row.neutralCount || 0}○ / ${row.negativeCount || 0}-`
                        : 'No feedback yet'
            };
        });
    }

    get drillDownRows() {
        return this.flattenDrillDown(this.summary?.drillDown || [], 0);
    }

    get hasDrillDown() {
        return this.drillDownRows.length > 0;
    }

    get showDrillPanel() {
        return Boolean(this.selectedBuId);
    }

    async loadComparison() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const [rows, snapshot] = await Promise.all([
                getExecutiveBuComparison(),
                getExecutiveOrgSnapshot()
            ]);
            this.orgSnapshot = snapshot;
            this.chartMax = this.computeChartMax(rows);
            this.buComparison = rows.map((row) => this.decorateBuRow(row));
            if (this.buComparison.length > 0 && !this.selectedBuId) {
                await this.selectBu(this.buComparison[0].id);
            }
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load executive overview';
            this.buComparison = [];
            this.orgSnapshot = null;
        } finally {
            this.isLoading = false;
        }
    }

    computeChartMax(rows) {
        const max = { coverage: 100, callRate: 100, kol: 100, coaching: 1 };
        rows.forEach((row) => {
            max.coverage = Math.max(max.coverage, pctNumber(row.coveragePercent));
            max.callRate = Math.max(max.callRate, pctNumber(row.actualVisitRate));
            max.kol = Math.max(max.kol, pctNumber(row.kolCoveragePercent));
            max.coaching = Math.max(max.coaching, Number(row.coachingDays || 0));
        });
        return max;
    }

    decorateBuRow(row) {
        const id = row.territoryId;
        return {
            id,
            name: row.name,
            coverage: pctDisplay(row.coveragePercent),
            callRate: pctDisplay(row.actualVisitRate),
            kolCoverage: pctDisplay(row.kolCoveragePercent),
            coachingDays: numDisplay(row.coachingDays, 0),
            repsCoached: `${row.coachedReps || 0}/${row.totalReps || 0}`,
            workforceLabel: `${row.totalReps || 0} reps · ${row.totalManagers || 0} mgrs`,
            visitsLabel: `${row.visitsThisMonth || 0} visits MTD`,
            clmLabel: `${row.clmSessionsThisMonth || 0} CLM sessions`,
            clmUsageLabel: ratioPctDisplay(row.clmUsageRate),
            clmLibraryLabel: `${row.clmPresentationsUsed || 0}/${row.totalClmPresentations || 0} decks used`,
            coveragePercent: row.coveragePercent,
            actualVisitRate: row.actualVisitRate,
            kolCoveragePercent: row.kolCoveragePercent,
            coachingDaysRaw: row.coachingDays,
            coachedReps: row.coachedReps,
            totalReps: row.totalReps,
            cardClass: this.selectedBuId === id ? 'bu-card slds-box bu-card-selected' : 'bu-card slds-box',
            coverageBarStyle: barHeight(row.coveragePercent, this.chartMax.coverage),
            callRateBarStyle: barHeight(row.actualVisitRate, this.chartMax.callRate),
            kolBarStyle: barHeight(row.kolCoveragePercent, this.chartMax.kol),
            coachingBarStyle: `height: ${Math.max(
                4,
                Math.round(((Number(row.coachingDays) || 0) / this.chartMax.coaching) * 100)
            )}%;`
        };
    }

    async handleOrgStatClick(event) {
        const tileId = event.currentTarget.dataset.tileId;
        if (!WORKFORCE_TILE_IDS.has(tileId)) {
            return;
        }
        if (this.activeWorkforceType === tileId) {
            this.activeWorkforceType = null;
            this.selectedWorkforceEmployeeId = null;
            this.attendanceDetail = null;
            return;
        }
        this.activeWorkforceType = tileId;
        this.selectedWorkforceEmployeeId = null;
        this.attendanceDetail = null;
        await this.refreshWorkforceRoster();
        const panel = this.template.querySelector('.workforce-section');
        if (panel) {
            panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    async handleWorkforceRowClick(event) {
        const employeeId = event.currentTarget.dataset.employeeId;
        if (!employeeId) {
            return;
        }
        if (this.selectedWorkforceEmployeeId === employeeId) {
            this.selectedWorkforceEmployeeId = null;
            this.attendanceDetail = null;
            return;
        }
        this.selectedWorkforceEmployeeId = employeeId;
        await this.loadAttendanceDetail(employeeId);
    }

    async handleTopPerformerClick(event) {
        const employeeId = event.currentTarget.dataset.employeeId;
        if (!employeeId) {
            return;
        }
        if (this.selectedWorkforceEmployeeId === employeeId) {
            this.selectedWorkforceEmployeeId = null;
            this.attendanceDetail = null;
            return;
        }
        this.selectedWorkforceEmployeeId = employeeId;
        await this.loadAttendanceDetail(employeeId);
    }

    async handleCloseWorkforcePanel() {
        this.activeWorkforceType = null;
        this.selectedWorkforceEmployeeId = null;
        this.attendanceDetail = null;
        this.workforceRows = [];
    }

    async handleBuCardClick(event) {
        const buId = event.currentTarget.dataset.id;
        await this.selectBu(buId);
    }

    async handleChartGroupClick(event) {
        const buId = event.currentTarget.dataset.id;
        await this.selectBu(buId);
    }

    async selectBu(buId) {
        const bu = this.buComparison.find((row) => row.id === buId);
        if (!bu) {
            return;
        }
        this.selectedBuId = buId;
        this.selectedBuName = bu.name;
        this.selectedLine = 'ALL';
        this.selectedDistrict = 'ALL';
        this.expandedKeys = new Set();
        this.buComparison = this.buComparison.map((row) => ({
            ...row,
            cardClass: row.id === buId ? 'bu-card slds-box bu-card-selected' : 'bu-card slds-box'
        }));
        await this.loadLineOptions();
        await this.loadDistrictOptions();
        await Promise.all([
            this.refreshDrillDown(),
            this.refreshProductPerformance(),
            this.refreshWorkforceRosterIfActive()
        ]);
    }

    async handleProductSortChange(event) {
        this.productSort = event.detail.value;
    }

    async handleLineChange(event) {
        this.selectedLine = event.detail.value;
        this.selectedDistrict = 'ALL';
        this.expandedKeys = new Set();
        await this.loadDistrictOptions();
        await Promise.all([
            this.refreshDrillDown(),
            this.refreshProductPerformance(),
            this.refreshWorkforceRosterIfActive()
        ]);
    }

    async handleDistrictChange(event) {
        this.selectedDistrict = event.detail.value;
        this.expandedKeys = new Set();
        await Promise.all([
            this.refreshDrillDown(),
            this.refreshProductPerformance(),
            this.refreshWorkforceRosterIfActive()
        ]);
    }

    async loadLineOptions() {
        try {
            const data = await getLineOptions({ buTerritoryId: this.selectedBuId });
            this.lineOptions = data.map((option) => ({ label: option.label, value: option.value }));
        } catch (error) {
            this.lineOptions = [{ label: 'All Lines', value: 'ALL' }];
        }
    }

    async loadDistrictOptions() {
        try {
            const data = await getDistrictOptions({ lineTerritoryId: this.selectedLine });
            this.districtOptions = data.map((option) => ({ label: option.label, value: option.value }));
        } catch (error) {
            this.districtOptions = [{ label: 'All Districts', value: 'ALL' }];
        }
    }

    async refreshWorkforceRosterIfActive() {
        if (!this.activeWorkforceType) {
            return;
        }
        this.selectedWorkforceEmployeeId = null;
        this.attendanceDetail = null;
        await this.refreshWorkforceRoster();
    }

    async refreshWorkforceRoster() {
        if (!this.activeWorkforceType) {
            this.workforceRows = [];
            return;
        }
        this.isWorkforceLoading = true;
        try {
            this.workforceRows = await getWorkforceRoster({
                workforceType: this.activeWorkforceType,
                buTerritoryId: this.selectedBuId,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
        } catch (error) {
            this.workforceRows = [];
            this.errorMessage = error.body?.message || 'Failed to load workforce roster';
        } finally {
            this.isWorkforceLoading = false;
        }
    }

    async loadAttendanceDetail(employeeUserId) {
        this.isAttendanceLoading = true;
        try {
            this.attendanceDetail = await getEmployeeAttendanceDetail({
                employeeUserId,
                buTerritoryId: this.selectedBuId,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
        } catch (error) {
            this.attendanceDetail = null;
            this.errorMessage = error.body?.message || 'Failed to load attendance detail';
        } finally {
            this.isAttendanceLoading = false;
        }
    }

    async refreshDrillDown() {
        if (!this.selectedBuId) {
            this.summary = null;
            return;
        }
        this.isDrillLoading = true;
        this.errorMessage = null;
        try {
            this.summary = await getTeamKpis({
                buTerritoryId: this.selectedBuId,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
            const rootKeys = (this.summary?.drillDown || []).map((row) => row.key);
            this.expandedKeys = new Set(rootKeys);
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load drill-down data';
            this.summary = null;
        } finally {
            this.isDrillLoading = false;
        }
    }

    async refreshProductPerformance() {
        if (!this.selectedBuId) {
            this.productPerformance = [];
            return;
        }
        this.isProductLoading = true;
        try {
            this.productPerformance = await getExecutiveBuProductPerformance({
                buTerritoryId: this.selectedBuId,
                lineTerritoryId: this.selectedLine,
                districtTerritoryId: this.selectedDistrict
            });
        } catch (error) {
            this.productPerformance = [];
            this.errorMessage = error.body?.message || this.errorMessage || 'Failed to load product performance';
        } finally {
            this.isProductLoading = false;
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

    flattenDrillDown(rows, depth) {
        const output = [];
        rows.forEach((row) => {
            const hasChildren = Array.isArray(row.children) && row.children.length > 0;
            const isExpanded = this.expandedKeys.has(row.key);
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
                salaryDisplay:
                    row.level === 'Rep'
                        ? row.canViewSalary
                            ? formatCurrency(row.baseSalary)
                            : 'Restricted'
                        : '—',
                hasChildren,
                isExpanded,
                toggleIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                rowClass: `drill-row drill-row-${(row.level || 'node').toLowerCase()}`
            });
            if (hasChildren && isExpanded) {
                output.push(...this.flattenDrillDown(row.children, depth + 1));
            }
        });
        return output;
    }
}