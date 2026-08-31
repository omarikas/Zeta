import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getVisitDetail from '@salesforce/apex/FieldPlannerController.getVisitDetail';
import getPlannerProducts from '@salesforce/apex/FieldPlannerController.getPlannerProducts';
import saveVisitWorkspace from '@salesforce/apex/FieldPlannerController.saveVisitWorkspace';
import { getVisitStatusOptions, validateVisitStatusChange } from 'c/visitStatusUtils';

const NAV_ITEMS = [
    { key: 'details', label: 'Details' },
    { key: 'presentations', label: 'Presentations' },
    { key: 'samples', label: 'Dispense' },
    { key: 'items', label: 'Items' },
    { key: 'attachments', label: 'Attachments' }
];

const HCP_RECORD_TYPES = new Set(['SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount', 'Business_Contact']);

function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    const date = new Date(value);
    return date.toLocaleString([], {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

function formatDate(value) {
    if (!value) {
        return '';
    }
    return new Date(value).toISOString().slice(0, 10);
}

function parseProductSelection(value) {
    if (!value) {
        return [];
    }
    return value
        .split(';')
        .map((item) => item.trim())
        .filter(Boolean);
}

export default class VisitWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;

    visit;
    wiredVisitResult;
    isSaving = false;
    statusValue = 'Draft';
    visitObjective = '';
    visitNotes = '';
    productsDiscussed = '';
    productDetails = '';
    clmPresentation = '';
    selectedProducts = [];
    nextVisitDate = '';
    cancellationReason = '';
    productOptions = [];
    activeNav = 'details';

    @wire(getPlannerProducts)
    wiredProducts({ data, error }) {
        if (data) {
            this.productOptions = data;
        } else if (error) {
            this.productOptions = [];
        }
    }

    @wire(getVisitDetail, { visitId: '$recordId' })
    wiredVisit(result) {
        this.wiredVisitResult = result;
        if (result.data) {
            this.applyVisit(result.data);
        }
    }

    get isLoading() {
        return !this.wiredVisitResult || this.wiredVisitResult.loading;
    }

    get errorMessage() {
        return this.wiredVisitResult?.error?.body?.message || this.wiredVisitResult?.error?.message;
    }

    get statusOptions() {
        return getVisitStatusOptions(
            this.visit?.startDateTime,
            this.visit?.visitType,
            this.visit?.status
        );
    }

    get clmOptions() {
        return [];
    }

    get navItems() {
        return NAV_ITEMS.map((item) => ({
            ...item,
            className: item.key === this.activeNav ? 'nav-item nav-item-active' : 'nav-item'
        }));
    }

    get showDetails() {
        return this.activeNav === 'details';
    }

    get showPresentations() {
        return this.activeNav === 'presentations';
    }

    get showPlaceholderTab() {
        return ['samples', 'items', 'attachments'].includes(this.activeNav);
    }

    get placeholderLabel() {
        const item = NAV_ITEMS.find((nav) => nav.key === this.activeNav);
        return item ? item.label : 'Section';
    }

    get isLocked() {
        return this.visit?.isLocked;
    }

    get showCancellationReason() {
        return this.statusValue === 'Cancelled';
    }

    get accountBadgeLabel() {
        const devName = this.visit?.accountRecordTypeDeveloperName || '';
        if (HCP_RECORD_TYPES.has(devName)) {
            return 'HCP';
        }
        if (devName === 'Institution_HCO' || (this.visit?.accountRecordTypeName || '').toLowerCase().includes('hco')) {
            return 'HCO';
        }
        return this.visit?.accountRecordTypeName || 'Account';
    }

    get accountBadgeClass() {
        return HCP_RECORD_TYPES.has(this.visit?.accountRecordTypeDeveloperName || '')
            ? 'account-badge account-badge-hcp'
            : 'account-badge account-badge-hco';
    }

    get statusBadgeClass() {
        const status = this.visit?.status || 'Draft';
        return `status-badge status-badge-${status.toLowerCase()}`;
    }

    get accountMetaLine() {
        return [this.visit?.accountSpecialty, this.visit?.accountCity].filter(Boolean).join(' · ');
    }

    get startLabel() {
        return formatDateTime(this.visit?.startDateTime);
    }

    get endLabel() {
        return formatDateTime(this.visit?.endDateTime);
    }

    get pathSteps() {
        const current = this.visit?.status || 'Draft';
        const isUnplanned = (this.visit?.visitType || '') === 'Unplanned';
        const steps = isUnplanned
            ? [
                  { key: 'Scheduled', label: 'Scheduled' },
                  { key: 'Completed', label: 'Completed' }
              ]
            : [
                  { key: 'Draft', label: 'Draft' },
                  { key: 'Submitted', label: 'Submitted' },
                  { key: 'Scheduled', label: 'Scheduled' },
                  { key: 'Completed', label: 'Completed' }
              ];
        if (current === 'Cancelled') {
            return steps
                .map((step) => ({
                    ...step,
                    stepClass: 'path-step path-step-cancelled',
                    isCurrent: false,
                    isComplete: false
                }))
                .concat({
                    key: 'Cancelled',
                    label: 'Cancelled',
                    stepClass: 'path-step path-step-current path-step-cancelled',
                    isCurrent: true,
                    isComplete: false
                });
        }
        const order = steps.map((step) => step.key);
        const currentIndex = order.indexOf(current);
        return steps.map((step, index) => {
            const isCurrent = step.key === current;
            const isComplete = currentIndex > index;
            let stepClass = 'path-step';
            if (isCurrent) {
                stepClass += ' path-step-current';
            } else if (isComplete) {
                stepClass += ' path-step-complete';
            }
            return { ...step, stepClass, isCurrent, isComplete };
        });
    }

    get isPendingApproval() {
        return (this.visit?.status || '') === 'Submitted';
    }

    get planRejectionReason() {
        return this.visit?.planRejectionReason || '';
    }

    applyVisit(data) {
        this.visit = data;
        this.statusValue = data.status || 'Draft';
        this.visitObjective = data.visitObjective || '';
        this.visitNotes = data.visitNotes || '';
        this.productsDiscussed = data.productsDiscussed || '';
        this.productDetails = data.productDetails || '';
        this.clmPresentation = data.clmPresentation || '';
        this.selectedProducts = parseProductSelection(data.productsDiscussed);
        this.nextVisitDate = formatDate(data.nextVisitDate);
        this.cancellationReason = data.cancellationReason || '';
    }

    handleStatusChange(event) {
        this.statusValue = event.detail.value;
        if (this.statusValue !== 'Cancelled') {
            this.cancellationReason = '';
        }
    }

    handleObjectiveChange(event) {
        this.visitObjective = event.detail.value;
    }

    handleNotesChange(event) {
        this.visitNotes = event.detail.value;
    }

    handleProductsChange(event) {
        this.selectedProducts = event.detail.value;
        this.productsDiscussed = this.selectedProducts.join('; ');
    }

    handleProductDetailsChange(event) {
        this.productDetails = event.detail.value;
    }

    handleClmChange(event) {
        this.clmPresentation = event.detail.value;
    }

    handleNavClick(event) {
        this.activeNav = event.currentTarget.dataset.key;
    }

    handleNextVisitChange(event) {
        this.nextVisitDate = event.detail.value;
    }

    handleCancellationChange(event) {
        this.cancellationReason = event.detail.value;
    }

    async handleSave() {
        const validationMessage = validateVisitStatusChange(
            this.statusValue,
            this.visit?.startDateTime,
            this.cancellationReason
        );
        if (validationMessage) {
            this.showToast('Validation', validationMessage, 'error');
            return;
        }
        this.isSaving = true;
        try {
            const saved = await saveVisitWorkspace({
                visitId: this.recordId,
                status: this.statusValue,
                visitObjective: this.visitObjective,
                visitNotes: this.visitNotes,
                productsDiscussed: this.selectedProducts.join('; '),
                productDetails: this.productDetails,
                clmPresentation: this.clmPresentation,
                nextVisitDate: this.nextVisitDate || null,
                cancellationReason: this.cancellationReason || null
            });
            this.applyVisit(saved);
            await refreshApex(this.wiredVisitResult);
            this.showToast('Visit saved', saved.accountName, 'success');
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    get isPwaContext() {
        const p = window?.location?.pathname || '';
        return p === '/' || p.endsWith('/index.html') || p.endsWith('/accounts.html') || p.endsWith('/visits.html');
    }

    handleOpenAccount() {
        if (!this.visit?.accountId) {
            return;
        }
        if (this.isPwaContext) {
            window.location.href = `/accounts.html?accountId=${this.visit.accountId}`;
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.visit.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    handleOpenPlanner() {
        if (this.isPwaContext) {
            window.location.href = '/index.html';
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Field_Rep_Planner'
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}