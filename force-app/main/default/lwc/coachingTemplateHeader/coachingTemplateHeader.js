import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import cloneTemplate from '@salesforce/apex/CoachingAdminController.cloneTemplate';
import TEMPLATE_TITLE from '@salesforce/schema/Coaching_Template__c.Template_Title__c';
import TEMPLATE_ID from '@salesforce/schema/Coaching_Template__c.Name';
import TEMPLATE_TYPE from '@salesforce/schema/Coaching_Template__c.Template_Type__c';
import IS_ACTIVE from '@salesforce/schema/Coaching_Template__c.Is_Active__c';

const FIELDS = [TEMPLATE_TITLE, TEMPLATE_ID, TEMPLATE_TYPE, IS_ACTIVE];

export default class CoachingTemplateHeader extends NavigationMixin(LightningElement) {
    @api recordId;

    title;
    templateId;
    templateType;
    isActive;
    isCloning = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        if (data) {
            this.title = data.fields.Template_Title__c?.value;
            this.templateId = data.fields.Name?.value;
            this.templateType = data.fields.Template_Type__c?.value;
            this.isActive = data.fields.Is_Active__c?.value;
        }
    }

    get displayTitle() {
        return this.title || this.templateId || 'Coaching Template';
    }

    get statusLabel() {
        return this.isActive ? 'Active' : 'Inactive';
    }

    get statusClass() {
        return this.isActive ? 'status-pill active' : 'status-pill inactive';
    }

    async handleClone() {
        if (!this.recordId || this.isCloning) {
            return;
        }
        this.isCloning = true;
        try {
            const cloneId = await cloneTemplate({ templateId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Template cloned',
                    message: 'Opening the copied template.',
                    variant: 'success'
                })
            );
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: cloneId,
                    objectApiName: 'Coaching_Template__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Clone failed',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isCloning = false;
        }
    }
}