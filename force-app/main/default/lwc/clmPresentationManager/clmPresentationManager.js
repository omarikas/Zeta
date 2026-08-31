import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPresentations from '@salesforce/apex/ClmAdminController.getPresentations';
import deactivatePresentation from '@salesforce/apex/ClmAdminController.deactivatePresentation';

export default class ClmPresentationManager extends LightningElement {
    statusFilter = 'All';
    presentations = [];
    wiredResult;
    showWizard = false;
    selectedPresentationId;

    statusOptions = [
        { label: 'All', value: 'All' },
        { label: 'Available', value: 'Available' },
        { label: 'Draft', value: 'Draft' },
        { label: 'Deactivated', value: 'Deactivated' }
    ];

    @wire(getPresentations, { statusFilter: '$statusFilter' })
    wiredPresentations(result) {
        this.wiredResult = result;
        this.presentations = result.data || [];
    }

    get rows() {
        return this.presentations;
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
    }

    handleNew() {
        this.selectedPresentationId = null;
        this.showWizard = true;
    }

    handleEdit(event) {
        this.selectedPresentationId = event.currentTarget.dataset.id;
        this.showWizard = true;
    }

    async handleDeactivate(event) {
        const presentationId = event.currentTarget.dataset.id;
        try {
            await deactivatePresentation({ presentationId });
            await refreshApex(this.wiredResult);
            this.toast('Presentation deactivated', 'The presentation is no longer available to reps.', 'success');
        } catch (error) {
            this.toast('Deactivate failed', error?.body?.message || error?.message, 'error');
        }
    }

    handleWizardClose() {
        this.showWizard = false;
        this.selectedPresentationId = null;
        refreshApex(this.wiredResult);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}