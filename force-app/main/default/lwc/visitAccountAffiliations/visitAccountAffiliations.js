import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_FIELD from '@salesforce/schema/Visit__c.Account__c';

const VISIT_FIELDS = [ACCOUNT_FIELD];

export default class VisitAccountAffiliations extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: VISIT_FIELDS })
    visit;

    get accountId() {
        return getFieldValue(this.visit.data, ACCOUNT_FIELD);
    }

    get isLoading() {
        return !this.visit.data && !this.visit.error;
    }

    get errorMessage() {
        return this.visit.error?.body?.message || this.visit.error?.message;
    }

    get hasAccount() {
        return !!this.accountId;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasAccount;
    }
}