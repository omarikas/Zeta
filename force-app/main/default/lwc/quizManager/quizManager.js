import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMaterialSummaries from '@salesforce/apex/LearningAdminController.getMaterialSummaries';
import createMaterial from '@salesforce/apex/LearningAdminController.createMaterial';

export default class QuizManager extends NavigationMixin(LightningElement) {
    searchTerm = '';
    activeFilter = 'All';
    materials = [];
    wiredResult;
    showNewModal = false;
    isSaving = false;
    newTitle = '';
    selectedQuizId;

    activeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];

    @wire(getMaterialSummaries, {
        searchTerm: '$searchTerm',
        typeFilter: 'Quiz',
        activeFilter: '$activeFilter'
    })
    wiredMaterials(result) {
        this.wiredResult = result;
        if (result.data) {
            this.materials = result.data.map((row) => ({
                ...row,
                activeLabel: row.isActive ? 'Active' : 'Inactive',
                parentLabel: row.parentTitle || '�'
            }));
        } else {
            this.materials = [];
        }
    }

    get rows() {
        return this.materials;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isNewDisabled() {
        return this.isSaving || !this.newTitle?.trim();
    }

    get hasSelectedQuiz() {
        return !!this.selectedQuizId;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleActiveFilter(event) {
        this.activeFilter = event.detail.value;
    }

    handleNew() {
        this.newTitle = '';
        this.showNewModal = true;
    }

    handleNewTitle(event) {
        this.newTitle = event.target.value;
    }

    handleCloseNew() {
        this.showNewModal = false;
    }

    async handleCreate() {
        const title = this.newTitle?.trim();
        if (!title) {
            return;
        }
        this.isSaving = true;
        try {
            const materialId = await createMaterial({
                title,
                materialType: 'Quiz',
                parentMaterialId: null,
                active: true
            });
            this.showNewModal = false;
            await refreshApex(this.wiredResult);
            this.selectedQuizId = materialId;
            this.toast('Quiz created', 'Use the editor below to refine questions.', 'success');
        } catch (error) {
            this.toast('Create failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleEdit(event) {
        this.selectedQuizId = event.currentTarget.dataset.id;
    }

    handleOpenRecord(event) {
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: id,
                objectApiName: 'Learning_Material__c',
                actionName: 'view'
            }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}