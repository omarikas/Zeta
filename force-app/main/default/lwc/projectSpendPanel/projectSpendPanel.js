import { LightningElement, api, wire } from 'lwc';
import getProjectSummary from '@salesforce/apex/ProjectManagementService.getProjectSummary';
import { formatCurrency } from 'c/projectTypeUtils';

export default class ProjectSpendPanel extends LightningElement {
    @api recordId;
    summary;
    error;
    isLoading = true;

    @wire(getProjectSummary, { projectId: '$recordId' })
    wiredSummary({ data, error }) {
        this.isLoading = false;
        if (data) {
            const budgetPercent = Math.min(100, Math.max(0, Math.round(data.budgetUtilizationPercent || 0)));
            const spent = data.budgetSpent || 0;
            const total = data.totalBudget || 0;
            const remaining = Math.max(0, total - spent);
            const budgetTrackingAvailable = data.budgetTrackingAvailable !== false;
            const hasBudget = budgetTrackingAvailable && total > 0;

            const gaugeTone = budgetPercent >= 90 ? 'high' : budgetPercent >= 70 ? 'mid' : 'low';
            const gaugeColor = gaugeTone === 'high' ? '#ef4444' : gaugeTone === 'mid' ? '#f59e0b' : '#14b8a6';

            this.summary = {
                ...data,
                budgetPercent,
                spentDisplay: formatCurrency(spent),
                totalDisplay: formatCurrency(total),
                remainingDisplay: formatCurrency(remaining),
                budgetBarStyle: `width: ${budgetPercent}%`,
                gaugeStyle: `--proj-spend-angle: ${budgetPercent * 3.6}deg; --proj-spend-color: ${gaugeColor};`,
                gaugeClass: `proj-spend-gauge proj-spend-gauge--${gaugeTone}`,
                hasBudget,
                budgetTrackingAvailable,
                budgetTrackingLabel: data.budgetTrackingLabel || 'Budget tracking coming soon',
                meetingsPercent: this.calcPercent(data.meetingsDone, data.meetingsTarget),
                visitsPercent: this.calcPercent(data.visitsDone, data.visitsTarget),
                roundTablesPercent: this.calcPercent(data.roundTablesDone, data.roundTableTarget),
                meetingsDisplay: this.formatProgress(data.meetingsDone, data.meetingsTarget),
                visitsDisplay: this.formatProgress(data.visitsDone, data.visitsTarget),
                roundTablesDisplay: this.formatProgress(data.roundTablesDone, data.roundTableTarget),
                meetingsBarStyle: `width: ${this.calcPercent(data.meetingsDone, data.meetingsTarget)}%`,
                visitsBarStyle: `width: ${this.calcPercent(data.visitsDone, data.visitsTarget)}%`,
                roundTablesBarStyle: `width: ${this.calcPercent(data.roundTablesDone, data.roundTableTarget)}%`
            };
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unable to load budget data.';
            this.summary = undefined;
        }
    }

    calcPercent(done, target) {
        const d = done || 0;
        const t = target || 0;
        return t > 0 ? Math.min(100, Math.round((d / t) * 100)) : 0;
    }

    formatProgress(done, target) {
        const d = done || 0;
        const t = target || 0;
        return t > 0 ? `${d} / ${t}` : `${d}`;
    }

    get hasSummary() {
        return this.summary != null;
    }

    get showPlaceholder() {
        return this.hasSummary && !this.summary.hasBudget;
    }

    get utilizationLabel() {
        if (!this.hasSummary) {
            return '';
        }
        if (this.summary.hasBudget) {
            return `${this.summary.budgetPercent}% of budget utilized`;
        }
        return this.summary.budgetTrackingLabel;
    }
}