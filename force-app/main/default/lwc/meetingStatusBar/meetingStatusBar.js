import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import evaluateMeeting from '@salesforce/apex/MeetingWorkflowAdminController.evaluateMeeting';
import applyMeetingAction from '@salesforce/apex/MeetingWorkflowAdminController.applyMeetingAction';

export default class MeetingStatusBar extends LightningElement {
    @api recordId;
    @track evaluation;
    @track reason = '';
    @track selectedActionKey;
    @track showReasonModal = false;
    busy = false;
    errorMessage;

    connectedCallback() {
        this.refreshEvaluation();
    }

    @api
    async refreshEvaluation() {
        if (!this.recordId) {
            return;
        }
        this.busy = true;
        this.errorMessage = undefined;
        try {
            this.evaluation = await evaluateMeeting({ meetingId: this.recordId });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.busy = false;
        }
    }

    get statusLabel() {
        return this.evaluation?.status || '�';
    }

    get rolesLabel() {
        const roles = this.evaluation?.roles || [];
        return roles.length ? roles.join(', ') : 'No meeting role';
    }

    get pathSteps() {
        const path = this.evaluation?.statusPath || [];
        return path.map((step) => {
            let itemClass = 'slds-path__item slds-is-incomplete';
            if (step.isCurrent) {
                itemClass = 'slds-path__item slds-is-current slds-is-active';
                if (step.value === 'Cancelled') {
                    itemClass += ' path-cancelled';
                }
            } else if (step.isComplete) {
                itemClass = 'slds-path__item slds-is-complete';
            }
            return {
                ...step,
                itemClass,
                assistiveText: step.isCurrent
                    ? `Current status: ${step.label}`
                    : step.isComplete
                      ? `Completed: ${step.label}`
                      : step.label
            };
        });
    }

    get hasPath() {
        return this.pathSteps.length > 0;
    }

    get actions() {
        const raw = this.evaluation?.actions || [];
        return raw.map((action, index) => ({
            ...action,
            buttonVariant: index === 0 ? 'brand' : 'neutral'
        }));
    }

    get hasActions() {
        return this.actions.length > 0;
    }

    get canEditMeeting() {
        return this.evaluation?.canEditMeeting === true;
    }

    get workflowMessage() {
        return this.evaluation?.message;
    }

    handleActionClick(event) {
        const actionKey = event.currentTarget.dataset.actionKey;
        const action = this.actions.find((item) => item.actionKey === actionKey);
        if (!action) {
            return;
        }
        if (action.requiresReason) {
            this.selectedActionKey = actionKey;
            this.reason = '';
            this.showReasonModal = true;
            return;
        }
        this.runAction(actionKey, null);
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    handleReasonCancel() {
        this.showReasonModal = false;
        this.selectedActionKey = undefined;
        this.reason = '';
    }

    async handleReasonConfirm() {
        if (!(this.reason || '').trim()) {
            this.toast('Reason required', 'Enter a reason for this action.', 'error');
            return;
        }
        const actionKey = this.selectedActionKey;
        this.showReasonModal = false;
        await this.runAction(actionKey, this.reason.trim());
        this.selectedActionKey = undefined;
        this.reason = '';
    }

    async runAction(actionKey, reason) {
        this.busy = true;
        try {
            const result = await applyMeetingAction({
                meetingId: this.recordId,
                actionKey,
                reason
            });
            if (result.success) {
                this.toast('Status updated', result.message, 'success');
                this.dispatchEvent(new RefreshEvent());
                await this.refreshEvaluation();
            } else {
                this.toast('Action blocked', result.message, 'error');
            }
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}