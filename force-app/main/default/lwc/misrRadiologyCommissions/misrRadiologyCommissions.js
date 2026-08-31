import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getFilterOptions from '@salesforce/apex/MisrRadiologyCommissionController.getFilterOptions';
import getCommissionDetail from '@salesforce/apex/MisrRadiologyCommissionController.getCommissionDetail';

const CURRENCY_CODE = 'EGP';
const CURRENCY_LOCALE = 'en-EG';

const STATUS_LABELS = {
    ahead: 'Ahead',
    on_track: 'On track',
    behind: 'Behind',
    critical: 'Critical'
};

const STATUS_CLASS = {
    ahead: 'mr-status mr-status--ahead',
    on_track: 'mr-status mr-status--on-track',
    behind: 'mr-status mr-status--behind',
    critical: 'mr-status mr-status--critical'
};

function formatCurrency(value) {
    const num = Number(value) || 0;
    return new Intl.NumberFormat(CURRENCY_LOCALE, {
        style: 'currency',
        currency: CURRENCY_CODE,
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
    }).format(num);
}

function formatCompactCurrency(value) {
    const num = Number(value) || 0;
    if (num >= 1000000) {
        return `${(num / 1000000).toFixed(1)}M`;
    }
    if (num >= 1000) {
        return `${Math.round(num / 1000)}k`;
    }
    return String(Math.round(num));
}

function formatPercent(value) {
    const num = Number(value) || 0;
    return `${Math.round(num)}%`;
}

function barStyle(percent) {
    const clamped = Math.min(100, Math.max(0, Number(percent) || 0));
    return `width: ${clamped}%`;
}

function mapServiceRow(row, expandedKeys) {
    const achievement = Number(row.achievementPercent) || 0;
    const projectedAchievement = Number(row.projectedAchievementPercent) || 0;
    const statusKey = row.paceStatus || 'behind';
    const isOpen = expandedKeys.has(row.serviceKey);
    return {
        ...row,
        soldDisplay: formatCurrency(row.sold),
        targetDisplay: formatCurrency(row.target),
        achievementDisplay: formatPercent(achievement),
        projectedSoldDisplay: formatCurrency(row.projectedSold),
        projectedAchievementDisplay: formatPercent(projectedAchievement),
        commissionDisplay: formatCurrency(row.commission),
        projectedCommissionDisplay: formatCurrency(row.projectedCommission),
        rateDisplay: `${Number(row.commissionRate) || 0}%`,
        barStyle: barStyle(achievement),
        statusLabel: STATUS_LABELS[statusKey] || statusKey,
        statusClass: STATUS_CLASS[statusKey] || STATUS_CLASS.behind,
        rowKey: row.serviceKey,
        isOpen,
        rowClass: isOpen ? 'mr-row mr-row--open' : 'mr-row',
        chevronClass: isOpen ? 'mr-row-chevron mr-row-chevron--open' : 'mr-row-chevron',
        inlineSummary: `${formatCompactCurrency(row.sold)}/${formatCompactCurrency(row.target)}`
    };
}

export default class MisrRadiologyCommissions extends LightningElement {
    filterOptions;
    selectedMonth;
    detail;
    isLoading = false;
    errorMessage;
    wiredFilterResult;
    detailRequestId = 0;
    panelExpanded = false;
    servicesExpanded = false;
    expandedServiceKeys = new Set();

    @wire(getFilterOptions)
    wiredFilters(result) {
        this.wiredFilterResult = result;
        if (result.data) {
            this.filterOptions = result.data;
            if (!this.selectedMonth) {
                this.selectedMonth = result.data.defaultMonthValue;
                this.loadCommissionDetail();
            }
        } else if (result.error) {
            this.errorMessage = this.reduceError(result.error);
        }
    }

    get monthOptions() {
        return this.filterOptions?.monthOptions ?? [];
    }

    get monthOptionIndex() {
        return this.monthOptions.findIndex((opt) => opt.value === this.selectedMonth);
    }

    get isPrevMonthDisabled() {
        const idx = this.monthOptionIndex;
        return idx < 0 || idx >= this.monthOptions.length - 1;
    }

    get isNextMonthDisabled() {
        return this.monthOptionIndex <= 0;
    }

    get hasTimeCard() {
        return this.detail?.hasTimeCard === true;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && this.detail && !this.hasTimeCard;
    }

    get serviceRows() {
        return (this.detail?.services ?? []).map((row) => mapServiceRow(row, this.expandedServiceKeys));
    }

    get serviceCount() {
        return this.serviceRows.length;
    }

    get servicesToggleLabel() {
        const count = this.serviceCount;
        const commission = this.totals.currentCommissionDisplay;
        return `${count} service${count === 1 ? '' : 's'} · ${commission} earned`;
    }

    get totals() {
        const t = this.detail?.totals ?? {};
        return {
            soldDisplay: formatCurrency(t.totalSold),
            targetDisplay: formatCurrency(t.totalTarget),
            achievementDisplay: formatPercent(t.totalAchievementPercent),
            currentCommissionDisplay: formatCurrency(t.currentCommission),
            projectedSoldDisplay: formatCurrency(t.projectedSold),
            projectedAchievementDisplay: formatPercent(t.projectedAchievementPercent),
            projectedCommissionDisplay: formatCurrency(t.projectedCommission),
            totalBarStyle: barStyle(t.totalAchievementPercent)
        };
    }

    get projectedRevenueShort() {
        const t = this.detail?.totals;
        if (!t) {
            return '';
        }
        return `~${formatCurrency(t.projectedSold)} revenue (${formatPercent(t.projectedAchievementPercent)})`;
    }

    get projectedCommissionPayrollLabel() {
        const projected = this.detail?.totals?.projectedCommission;
        const payrollMonth = this.detail?.payrollMonthName;
        if (projected == null) {
            return '';
        }
        const value = formatCurrency(projected);
        return payrollMonth ? `${value} · ${payrollMonth} payroll` : value;
    }

    get workingDaysLabel() {
        const elapsed = this.detail?.elapsedWorkingDays ?? 0;
        const total = this.detail?.totalWorkingDays ?? 0;
        if (!total) {
            return '';
        }
        return `Day ${elapsed}/${total}`;
    }

    get panelToggleIcon() {
        return this.panelExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get servicesToggleIcon() {
        return this.servicesExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    handleTogglePanel() {
        this.panelExpanded = !this.panelExpanded;
    }

    handleToggleServices() {
        this.servicesExpanded = !this.servicesExpanded;
    }

    handleToggleServiceRow(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) {
            return;
        }
        const next = new Set(this.expandedServiceKeys);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this.expandedServiceKeys = next;
    }

    async loadCommissionDetail() {
        if (!this.selectedMonth) {
            return;
        }

        const requestId = ++this.detailRequestId;
        this.isLoading = true;
        this.errorMessage = null;

        try {
            const detail = await getCommissionDetail({ monthValue: this.selectedMonth });
            if (requestId !== this.detailRequestId) {
                return;
            }
            this.detail = detail;
            this.expandedServiceKeys = new Set();
        } catch (error) {
            if (requestId !== this.detailRequestId) {
                return;
            }
            this.errorMessage = this.reduceError(error);
            this.detail = null;
        } finally {
            if (requestId === this.detailRequestId) {
                this.isLoading = false;
            }
        }
    }

    handlePrevMonth() {
        const idx = this.monthOptionIndex;
        if (idx < 0 || idx >= this.monthOptions.length - 1) {
            return;
        }
        this.selectedMonth = this.monthOptions[idx + 1].value;
        this.loadCommissionDetail();
    }

    handleNextMonth() {
        const idx = this.monthOptionIndex;
        if (idx <= 0) {
            return;
        }
        this.selectedMonth = this.monthOptions[idx - 1].value;
        this.loadCommissionDetail();
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
        this.loadCommissionDetail();
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredFilterResult);
            await this.loadCommissionDetail();
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return 'Unable to load Misr Radiology commission data.';
    }
}