import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getBudgets from '@salesforce/apex/PromoBudgetController.getBudgets';

const SORT_FIELDS = {
    BU: 'businessUnit',
    DEPARTMENT: 'department',
    ALLOCATED: 'allocated',
    SPENT: 'spent',
    REMAINING: 'remaining',
    UTILIZATION: 'utilizationPercent'
};

function formatCurrency(value) {
    const num = Number(value) || 0;
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
    }).format(num);
}

function utilizationToneClass(pct) {
    if (pct >= 85) {
        return 'pb-util--danger';
    }
    if (pct >= 70) {
        return 'pb-util--warning';
    }
    return 'pb-util--healthy';
}

function utilizationBadgeClass(pct) {
    if (pct >= 85) {
        return 'pb-badge--danger';
    }
    if (pct >= 70) {
        return 'pb-badge--warning';
    }
    return 'pb-badge--healthy';
}

function mapBudgetRow(budget, isExpanded) {
    const utilization = Math.min(100, Math.max(0, budget.utilizationPercent || 0));
    const lineCount = (budget.lines || []).length;
    return {
        ...budget,
        detailKey: `${budget.id}-detail`,
        isExpanded,
        lineCount,
        lineCountLabel: lineCount === 1 ? '1 line' : `${lineCount} lines`,
        hasLines: lineCount > 0,
        allocatedDisplay: formatCurrency(budget.allocated),
        spentDisplay: formatCurrency(budget.spent),
        remainingDisplay: formatCurrency(budget.remaining),
        utilizationRounded: Math.round(utilization),
        utilizationDisplay: `${Math.round(utilization)}%`,
        utilizationBarStyle: `width: ${utilization}%`,
        utilizationToneClass: utilizationToneClass(utilization),
        utilizationBadgeClass: utilizationBadgeClass(utilization),
        expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
        ariaExpanded: isExpanded ? 'true' : 'false',
        lines: (budget.lines || []).map((line, index) => ({
            ...line,
            key: `${budget.id}-line-${index}`,
            amountDisplay: formatCurrency(line.amount)
        }))
    };
}

export default class PromoBudgetDashboard extends LightningElement {
    selectedBu = 'ALL';
    rawBudgets = [];
    budgets = [];
    error;
    expandedIds = new Set();
    sortField = SORT_FIELDS.UTILIZATION;
    sortDirection = 'desc';
    wiredBudgetsResult;
    isRefreshing = false;

    buOptions = [
        { label: 'All BUs', value: 'ALL' },
        { label: 'GIT', value: 'GIT' },
        { label: 'Diabetes', value: 'Diabetes' },
        { label: 'Cluster', value: 'Cluster' },
        { label: 'CHC', value: 'CHC' }
    ];

    @wire(getBudgets, { businessUnit: '$selectedBu' })
    wiredBudgets(result) {
        this.wiredBudgetsResult = result;
        const { data, error } = result;
        if (data) {
            this.rawBudgets = data;
            this.error = undefined;
            this.applyViewState();
        } else if (error) {
            this.rawBudgets = [];
            this.budgets = [];
            this.error = error.body?.message || 'Unable to load promo budgets.';
        }
    }

    get isLoading() {
        return !this.wiredBudgetsResult || (!this.wiredBudgetsResult.data && !this.wiredBudgetsResult.error);
    }

    get hasBudgets() {
        return this.budgets.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.error && !this.hasBudgets;
    }

    get budgetCountLabel() {
        const count = this.budgets.length;
        return count === 1 ? '1 budget' : `${count} budgets`;
    }

    get summary() {
        const totals = this.budgets.reduce(
            (acc, row) => {
                acc.allocated += Number(row.allocated) || 0;
                acc.spent += Number(row.spent) || 0;
                acc.remaining += Number(row.remaining) || 0;
                acc.utilizationSum += Number(row.utilizationPercent) || 0;
                return acc;
            },
            { allocated: 0, spent: 0, remaining: 0, utilizationSum: 0 }
        );
        const count = this.budgets.length || 1;
        const avgUtilization = this.budgets.length
            ? Math.round(totals.utilizationSum / this.budgets.length)
            : 0;
        const overallUtilization =
            totals.allocated > 0 ? Math.round((totals.spent / totals.allocated) * 100) : 0;

        return {
            allocatedDisplay: formatCurrency(totals.allocated),
            spentDisplay: formatCurrency(totals.spent),
            remainingDisplay: formatCurrency(totals.remaining),
            avgUtilizationDisplay: `${avgUtilization}%`,
            overallUtilizationDisplay: `${overallUtilization}%`,
            overallUtilizationBarStyle: `width: ${Math.min(100, overallUtilization)}%`,
            overallUtilizationToneClass: utilizationToneClass(overallUtilization),
            hasData: this.budgets.length > 0
        };
    }

    get sortIconBu() {
        return this.getSortIcon(SORT_FIELDS.BU);
    }

    get sortIconDepartment() {
        return this.getSortIcon(SORT_FIELDS.DEPARTMENT);
    }

    get sortIconAllocated() {
        return this.getSortIcon(SORT_FIELDS.ALLOCATED);
    }

    get sortIconSpent() {
        return this.getSortIcon(SORT_FIELDS.SPENT);
    }

    get sortIconRemaining() {
        return this.getSortIcon(SORT_FIELDS.REMAINING);
    }

    get sortIconUtilization() {
        return this.getSortIcon(SORT_FIELDS.UTILIZATION);
    }

    applyViewState() {
        const sorted = [...this.rawBudgets].sort((a, b) => this.compareRows(a, b));
        this.budgets = sorted.map((row) => mapBudgetRow(row, this.expandedIds.has(row.id)));
    }

    compareRows(a, b) {
        const field = this.sortField;
        const direction = this.sortDirection === 'asc' ? 1 : -1;
        const left = a[field];
        const right = b[field];

        if (typeof left === 'number' && typeof right === 'number') {
            return (left - right) * direction;
        }

        const leftText = (left || '').toString().toLowerCase();
        const rightText = (right || '').toString().toLowerCase();
        if (leftText < rightText) {
            return -1 * direction;
        }
        if (leftText > rightText) {
            return 1 * direction;
        }
        return 0;
    }

    getSortIcon(field) {
        if (this.sortField !== field) {
            return 'utility:arrowdown';
        }
        return this.sortDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }

    handleBuChange(event) {
        this.selectedBu = event.detail.value;
        this.expandedIds = new Set();
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) {
            return;
        }
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = field === SORT_FIELDS.BU ? 'asc' : 'desc';
        }
        this.applyViewState();
    }

    handleRowToggle(event) {
        const budgetId = event.currentTarget.dataset.id;
        if (!budgetId) {
            return;
        }
        const next = new Set(this.expandedIds);
        if (next.has(budgetId)) {
            next.delete(budgetId);
        } else {
            next.add(budgetId);
        }
        this.expandedIds = next;
        this.applyViewState();
    }

    handleRowKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleRowToggle(event);
        }
    }

    async handleRefresh() {
        if (!this.wiredBudgetsResult) {
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredBudgetsResult);
        } finally {
            this.isRefreshing = false;
        }
    }
}