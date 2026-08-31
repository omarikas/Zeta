import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class PendingPaymentModal extends LightningModal {
    @api message =
        'Salesforce invoice pending payment, your org is at risk of being shut-down, please share proof of payment with your account manager';

    handleAcknowledge() {
        this.close('acknowledge');
    }
}