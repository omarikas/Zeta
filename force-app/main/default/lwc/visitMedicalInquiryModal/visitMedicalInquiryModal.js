import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMedicalInquiryContext from '@salesforce/apex/VisitMedicalInquiryController.getMedicalInquiryContext';
import createMedicalInquiry from '@salesforce/apex/VisitMedicalInquiryController.createMedicalInquiry';

function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    return new Date(value).toLocaleString([], {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

export default class VisitMedicalInquiryModal extends NavigationMixin(LightningElement) {
    @api visitId;

    context;
    isLoading = true;
    isSubmitting = false;
    errorMessage;

    selectedInquirerId;
    selectedProductId;
    selectedCategory;
    questionText = '';

    connectedCallback() {
        this.loadContext();
    }

    get visitName() {
        return this.context?.visitName || '—';
    }

    get accountName() {
        return this.context?.accountName || '—';
    }

    get assignedToName() {
        return this.context?.assignedToName || '—';
    }

    get isLocked() {
        return this.context?.isLocked === true;
    }

    get inquirerOptions() {
        return (this.context?.inquirerOptions || []).map((row) => ({
            label: row.role ? `${row.accountName} (${row.role})` : row.accountName,
            value: row.accountId
        }));
    }

    get productOptions() {
        return (this.context?.products || []).map((row) => ({
            label: row.productName,
            value: row.productId
        }));
    }

    get categoryOptions() {
        return (this.context?.questionCategories || []).map((value) => ({
            label: value,
            value
        }));
    }

    get existingInquiries() {
        return (this.context?.existingInquiries || []).map((row) => ({
            ...row,
            createdLabel: formatDateTime(row.createdDate)
        }));
    }

    get hasExistingInquiries() {
        return this.existingInquiries.length > 0;
    }

    get submitDisabled() {
        return (
            this.isLoading ||
            this.isSubmitting ||
            this.isLocked ||
            !this.selectedInquirerId ||
            !this.selectedProductId ||
            !this.selectedCategory ||
            !this.questionText?.trim()
        );
    }

    get showIntakeForm() {
        return !this.isLocked && !this.errorMessage;
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.context = await getMedicalInquiryContext({ visitId: this.visitId });
            this.selectedInquirerId = this.context.defaultInquirerAccountId;
            if (!this.selectedInquirerId && this.context.inquirerOptions?.length) {
                this.selectedInquirerId = this.context.inquirerOptions[0].accountId;
            }
            if (this.context.products?.length) {
                this.selectedProductId = this.context.products[0].productId;
            }
            if (this.context.questionCategories?.length) {
                this.selectedCategory = this.context.questionCategories[0];
            }
            if (!this.context.products?.length && !this.isLocked) {
                this.errorMessage = 'No territory products are available for this visit.';
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleInquirerChange(event) {
        this.selectedInquirerId = event.detail.value;
    }

    handleProductChange(event) {
        this.selectedProductId = event.detail.value;
    }

    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
    }

    handleQuestionChange(event) {
        this.questionText = event.detail.value;
    }

    async handleSubmit() {
        this.isSubmitting = true;
        try {
            const result = await createMedicalInquiry({
                request: {
                    visitId: this.visitId,
                    inquirerAccountId: this.selectedInquirerId,
                    productId: this.selectedProductId,
                    questionCategory: this.selectedCategory,
                    questionText: this.questionText
                }
            });
            this.dispatchEvent(
                new CustomEvent('inquirycreated', {
                    detail: { caseId: result.caseId, caseNumber: result.caseNumber }
                })
            );
            this.showToast(
                'Medical inquiry recorded',
                `Case ${result.caseNumber} was routed to Medical Affairs.`,
                'success'
            );
            this.questionText = '';
            await this.loadContext();
        } catch (error) {
            this.showToast('Submit failed', this.reduceError(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleOpenCase(event) {
        const caseId = event.currentTarget.dataset.caseId;
        if (!caseId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
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