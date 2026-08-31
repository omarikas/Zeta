import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getProjectSummary from '@salesforce/apex/ProjectManagementService.getProjectSummary';
import getEligibleVisits from '@salesforce/apex/ProjectManagementService.getEligibleVisits';
import linkVisitsToProject from '@salesforce/apex/ProjectManagementService.linkVisitsToProject';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const FIELDS = ['Pharma_Project__c.Id'];

function formatApexError(error) {
    if (!error) {
        return 'An unexpected error occurred.';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body?.message) {
        return error.body.message;
    }
    if (typeof error.message === 'string') {
        return error.message;
    }
    return 'An unexpected error occurred.';
}

export default class ProjectSummaryPanel extends LightningElement {
    @api recordId;
    summary;
    eligibleVisits = [];
    selectedVisitIds = [];
    showLinkVisits = false;
    isLoadingVisits = false;
    visitsLoadError;
    isLinking = false;
    error;

    wiredSummaryResult;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error }) {
        if (error) {
            this.error = formatApexError(error);
        }
    }

    @wire(getProjectSummary, { projectId: '$recordId' })
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        const { data, error } = result;
        if (data) {
            this.summary = {
                ...data,
                budgetDisplay: this.formatCurrency(data.budgetSpent, data.totalBudget),
                budgetPercent: Math.round(data.budgetUtilizationPercent || 0),
                budgetBarStyle: `width: ${Math.min(100, Math.round(data.budgetUtilizationPercent || 0))}%`,
                meetingsPercent: this.calcPercent(data.meetingsDone, data.meetingsTarget),
                visitsPercent: this.calcPercent(data.visitsDone, data.visitsTarget),
                roundTablesPercent: this.calcPercent(data.roundTablesDone, data.roundTableTarget),
                meetingsDisplay: this.formatProgress(data.meetingsDone, data.meetingsTarget),
                roundTablesDisplay: this.formatProgress(data.roundTablesDone, data.roundTableTarget),
                visitsDisplay: this.formatProgress(data.visitsDone, data.visitsTarget),
                meetingsBarStyle: `width: ${this.calcPercent(data.meetingsDone, data.meetingsTarget)}%`,
                visitsBarStyle: `width: ${this.calcPercent(data.visitsDone, data.visitsTarget)}%`,
                roundTablesBarStyle: `width: ${this.calcPercent(data.roundTablesDone, data.roundTableTarget)}%`,
                kpis: (data.kpis || []).map((kpi) => {
                    const attainment = Math.round(kpi.attainmentPercent || 0);
                    const tone = attainment >= 90 ? 'high' : attainment >= 70 ? 'mid' : 'low';
                    return {
                        ...kpi,
                        metricsDisplay: `${kpi.actualValue ?? 0} / ${kpi.targetValue ?? 0}`,
                        attainmentDisplay: `${attainment}%`,
                        attainmentPercent: attainment,
                        barStyle: `width: ${Math.min(100, attainment)}%`,
                        cardClass: `proj-kpi-card proj-kpi-card--${tone}`
                    };
                }),
                workItems: (data.workItems || []).map((item) => ({
                    ...item,
                    dueDateDisplay: item.dueDate || '—'
                }))
            };
            this.error = undefined;
        } else if (error) {
            this.error = formatApexError(error);
            this.summary = undefined;
        }
    }

    get hasSummary() {
        return this.summary != null;
    }

    get hasKpis() {
        return this.summary?.kpis?.length > 0;
    }

    get hasWorkItems() {
        return this.summary?.workItems?.length > 0;
    }

    get hasEligibleVisits() {
        return (this.eligibleVisits || []).length > 0;
    }

    get showVisitsEmptyState() {
        return !this.isLoadingVisits && !this.visitsLoadError && !this.hasEligibleVisits;
    }

    formatProgress(done, target) {
        const d = done || 0;
        const t = target || 0;
        return t > 0 ? `${d} / ${t}` : `${d}`;
    }

    calcPercent(done, target) {
        const d = done || 0;
        const t = target || 0;
        return t > 0 ? Math.min(100, Math.round((d / t) * 100)) : 0;
    }

    formatCurrency(spent, total) {
        const s = spent || 0;
        const t = total || 0;
        return t > 0 ? `${s.toLocaleString()} / ${t.toLocaleString()}` : `${s.toLocaleString()}`;
    }

    formatVisitLabel(visit) {
        const parts = [
            visit.accountName,
            visit.visitDateDisplay,
            visit.status
        ].filter((part) => part);
        const detail = parts.length ? ` — ${parts.join(' · ')}` : '';
        return `${visit.name || 'Visit'}${detail}`;
    }

    async handleOpenLinkVisits() {
        this.showLinkVisits = true;
        this.isLoadingVisits = true;
        this.visitsLoadError = undefined;
        this.eligibleVisits = [];
        this.selectedVisitIds = [];

        try {
            this.eligibleVisits = await getEligibleVisits({ projectId: this.recordId });
        } catch (e) {
            this.visitsLoadError = formatApexError(e);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading visits',
                message: this.visitsLoadError,
                variant: 'error',
                mode: 'sticky'
            }));
        } finally {
            this.isLoadingVisits = false;
        }
    }

    handleCloseLinkVisits() {
        this.showLinkVisits = false;
        this.selectedVisitIds = [];
        this.eligibleVisits = [];
        this.visitsLoadError = undefined;
        this.isLoadingVisits = false;
    }

    handleVisitSelection(event) {
        this.selectedVisitIds = event.detail.value || [];
    }

    get visitOptions() {
        return (this.eligibleVisits || []).map((visit) => ({
            label: this.formatVisitLabel(visit),
            value: visit.id
        }));
    }

    get linkDisabled() {
        return this.isLinking || this.isLoadingVisits || !this.selectedVisitIds.length;
    }

    async handleLinkVisits() {
        this.isLinking = true;
        try {
            const count = await linkVisitsToProject({
                projectId: this.recordId,
                visitIds: this.selectedVisitIds
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Visits linked',
                message: `${count} visit(s) linked to this project.`,
                variant: 'success'
            }));
            this.handleCloseLinkVisits();
            await refreshApex(this.wiredSummaryResult);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Link failed',
                message: formatApexError(e),
                variant: 'error',
                mode: 'sticky'
            }));
        } finally {
            this.isLinking = false;
        }
    }
}