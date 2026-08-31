import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getPendingUnplannedReviews from '@salesforce/apex/VisitValidationController.getPendingUnplannedReviews';
import validateUnplannedVisit from '@salesforce/apex/VisitValidationController.validateUnplannedVisit';

export default class VisitUnplannedValidationQueue extends LightningElement {
    wiredResult;
    rows = [];

    @wire(getPendingUnplannedReviews)
    wiredReviews(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((row) => ({
                ...row,
                completedLabel: row.completedAt
                    ? new Date(row.completedAt).toLocaleString([], {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
                      })
                    : '—',
                dueLabel: row.validationDueDate
                    ? new Date(row.validationDueDate).toLocaleDateString([], {
                          month: 'short',
                          day: 'numeric',
                          year: 'numeric'
                      })
                    : '—'
            }));
        } else if (result.error) {
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    async handleValidate(event) {
        const visitId = event.target.dataset.visitId;
        const validationStatus = event.target.dataset.status;
        try {
            await validateUnplannedVisit({ visitId, validationStatus });
            this.showToast(
                validationStatus === 'Valid' ? 'Marked valid' : 'Marked invalid',
                'Unplanned visit validation updated.',
                'success'
            );
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Validation failed', this.reduceError(error), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
