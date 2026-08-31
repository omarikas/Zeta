import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplateSummaries from '@salesforce/apex/CoachingAdminController.getTemplateSummaries';
import createTemplate from '@salesforce/apex/CoachingAdminController.createTemplate';
import cloneTemplate from '@salesforce/apex/CoachingAdminController.cloneTemplate';

export default class CoachingTemplateManager extends NavigationMixin(LightningElement) {
    searchTerm = '';
    activeFilter = 'All';
    templates = [];
    wiredResult;
    showNewModal = false;
    newTitle = '';
    newType = 'Field Coaching';
    isSaving = false;

    activeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];

    typeOptions = [{ label: 'Field Coaching', value: 'Field Coaching' }];

    @wire(getTemplateSummaries, { searchTerm: '$searchTerm', activeFilter: '$activeFilter' })
    wiredTemplates(result) {
        this.wiredResult = result;
        if (result.data) {
            this.templates = result.data.map((row) => ({
                ...row,
                activeLabel: row.isActive ? 'Active' : 'Inactive',
                startDateLabel: row.startDate || '—',
                endDateLabel: row.endDate || '—'
            }));
        } else {
            this.templates = [];
        }
    }

    get rows() {
        return this.templates;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isNewDisabled() {
        return this.isSaving || !this.newTitle?.trim();
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleActiveFilter(event) {
        this.activeFilter = event.detail.value;
    }

    handleNew() {
        this.newTitle = '';
        this.newType = 'Field Coaching';
        this.showNewModal = true;
    }

    handleNewTitle(event) {
        this.newTitle = event.target.value;
    }

    handleNewType(event) {
        this.newType = event.detail.value;
    }

    handleCloseNew() {
        this.showNewModal = false;
        this.newTitle = '';
    }

    async handleCreate() {
        const title = this.newTitle?.trim();
        if (!title) {
            return;
        }
        this.isSaving = true;
        try {
            const templateId = await createTemplate({ title, templateType: this.newType });
            this.showNewModal = false;
            this.newTitle = '';
            await refreshApex(this.wiredResult);
            this.toast('Template created', 'Opening the template editor.', 'success');
            this.navigateToTemplate(templateId);
        } catch (error) {
            this.toast('Create failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpen(event) {
        const templateId = event.currentTarget.dataset.id;
        this.navigateToTemplate(templateId);
    }

    async handleClone(event) {
        const templateId = event.currentTarget.dataset.id;
        if (!templateId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        try {
            const cloneId = await cloneTemplate({ templateId });
            await refreshApex(this.wiredResult);
            this.toast('Template cloned', 'Opening the copied template.', 'success');
            this.navigateToTemplate(cloneId);
        } catch (error) {
            this.toast('Clone failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    navigateToTemplate(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Coaching_Template__c',
                actionName: 'view'
            }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}