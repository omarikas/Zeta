import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getPendingPlanApprovals from '@salesforce/apex/VisitValidationController.getPendingPlanApprovals';
import approvePlanVisit from '@salesforce/apex/FieldPlannerController.approvePlanVisit';
import rejectPlanVisit from '@salesforce/apex/VisitValidationController.rejectPlanVisit';

export default class VisitPlanApprovalQueue extends LightningElement {
    wiredResult;
    rows = [];
    rejectionReasonByVisitId = {};

    @wire(getPendingPlanApprovals)
    wiredApprovals(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((row) => ({
                ...row,
                startLabel: row.startDateTime
                    ? new Date(row.startDateTime).toLocaleString([], {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
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

    handleRejectionChange(event) {
        this.rejectionReasonByVisitId = {
            ...this.rejectionReasonByVisitId,
            [event.target.dataset.visitId]: event.detail.value
        };
    }

    async handleApprove(event) {
        const visitId = event.target.dataset.visitId;
        try {
            await approvePlanVisit({ visitId });
            this.showToast('Approved', 'Visit plan is now scheduled.', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        }
    }

    async handleReject(event) {
        const visitId = event.target.dataset.visitId;
        const rejectionReason = (this.rejectionReasonByVisitId[visitId] || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        try {
            await rejectPlanVisit({ visitId, rejectionReason });
            this.showToast('Rejected', 'Visit returned to Draft for the rep.', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Reject failed', this.reduceError(error), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
