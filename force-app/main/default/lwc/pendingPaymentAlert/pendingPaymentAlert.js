import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import isPendingPaymentNow from '@salesforce/apex/PendingPaymentController.isPendingPaymentNow';
import PendingPaymentModal from 'c/pendingPaymentModal';

const WARNING_MESSAGE =
    'Salesforce invoice pending payment, your org is at risk of being shut-down, please share proof of payment with your account manager';

// Shared across all hosts (Utility Bar + flexipages) so only one modal opens.
let globalModalPromise = null;
let globalEvaluatePromise = null;

export default class PendingPaymentAlert extends LightningElement {
    enabled = false;
    _lastPageKey;

    connectedCallback() {
        this.evaluateAndShow(true);
    }

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (!pageRef) {
            return;
        }
        const key = JSON.stringify(pageRef);
        if (this._lastPageKey && this._lastPageKey !== key) {
            this.evaluateAndShow(true);
        }
        this._lastPageKey = key;
    }

    async evaluateAndShow(forceOpen) {
        if (globalEvaluatePromise) {
            await globalEvaluatePromise;
            if (forceOpen && this.enabled) {
                await this.openModal();
            }
            return;
        }
        globalEvaluatePromise = this._runEvaluate(forceOpen);
        try {
            await globalEvaluatePromise;
        } finally {
            globalEvaluatePromise = null;
        }
    }

    async _runEvaluate(forceOpen) {
        try {
            const enabled = await isPendingPaymentNow();
            this.enabled = enabled === true;
            if (this.enabled && forceOpen) {
                await this.openModal();
            }
        } catch (e) {
            this.enabled = false;
            // eslint-disable-next-line no-console
            console.error('PendingPaymentAlert: failed to read org switch', e);
        }
    }

    async openModal() {
        if (globalModalPromise) {
            return;
        }
        globalModalPromise = PendingPaymentModal.open({
            size: 'small',
            label: 'Pending Payment',
            description: 'Pending payment warning',
            message: WARNING_MESSAGE
        });
        try {
            await globalModalPromise;
        } finally {
            globalModalPromise = null;
        }
    }
}