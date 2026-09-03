import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
import getMyRequests from '@salesforce/apex/TimeOffRequestController.getMyRequests';

import TIME_OFF_OBJECT from '@salesforce/schema/Time_Off_Request__c';
import TYPE_FIELD from '@salesforce/schema/Time_Off_Request__c.Type__c';
import SPAN_TYPE_FIELD from '@salesforce/schema/Time_Off_Request__c.Span_Type__c';
import SPAN_DURATION_SELECT_FIELD from '@salesforce/schema/Time_Off_Request__c.Span_Duration_Select__c';
import START_DATE_TIME_FIELD from '@salesforce/schema/Time_Off_Request__c.Start_Date_Time__c';
import COMMENTS_FIELD from '@salesforce/schema/Time_Off_Request__c.Comments__c';
import STAGE_FIELD from '@salesforce/schema/Time_Off_Request__c.Stage__c';

const STAGE_DRAFT = 'Draft';
const STAGE_SUBMITTED = 'Submitted for Approval';
const SPAN_FULL_DAY = 'Full_Day';
const SPAN_HOURS = 'Hours';

const TYPE_OPTIONS = [
    { label: 'Holiday', value: 'Holiday' },
    { label: 'Sick Leave', value: 'Sick Leave' },
    { label: 'Training', value: 'Training' },
    { label: 'Event', value: 'Event' },
    { label: 'Travelling', value: 'Travelling' }
];

const SPAN_TYPE_OPTIONS = [
    { label: 'Full Day', value: SPAN_FULL_DAY },
    { label: 'Partial (Hours)', value: SPAN_HOURS }
];

const DURATION_OPTIONS = Array.from({ length: 8 }, (_, index) => {
    const value = String(index + 1);
    return { label: `${value} hour${index === 0 ? '' : 's'}`, value };
});

const STAGE_VARIANT = {
    Draft: 'base',
    'Submitted for Approval': 'warning',
    Approved: 'success',
    Rejected: 'error'
};

export default class TimeOffSubmission extends NavigationMixin(LightningElement) {
    typeValue = '';
    spanTypeValue = '';
    durationValue = '';
    startDateValue = '';
    startDateTimeValue = '';
    commentsValue = '';
    isSaving = false;

    typeOptions = TYPE_OPTIONS;
    spanTypeOptions = SPAN_TYPE_OPTIONS;
    durationOptions = DURATION_OPTIONS;

    myRequests = [];
    requestsError;

    connectedCallback() {
        this.loadRequests();
    }

    async loadRequests() {
        try {
            const data = await getMyRequests({ limitSize: 10 });
            this.myRequests = (data || []).map((request) => this.mapRequestRow(request));
            this.requestsError = undefined;
        } catch (error) {
            this.myRequests = [];
            this.requestsError = this.reduceError(error);
        }
    }

    columns = [
        { label: 'Request', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'name' }, target: '_self' } },
        { label: 'Type', fieldName: 'typeLabel' },
        { label: 'Span', fieldName: 'spanTypeLabel' },
        { label: 'Start', fieldName: 'startDateLabel', type: 'text' },
        { label: 'End', fieldName: 'endDateLabel', type: 'text' },
        { label: 'Days', fieldName: 'workingDays', type: 'number', cellAttributes: { alignment: 'left' } },
        { label: 'Stage', fieldName: 'stage', type: 'text', cellAttributes: { class: { fieldName: 'stageClass' } } }
    ];

    get isHoursSpan() {
        return this.spanTypeValue === SPAN_HOURS;
    }

    get isFullDaySpan() {
        return this.spanTypeValue === SPAN_FULL_DAY;
    }

    get showScheduleFields() {
        return Boolean(this.spanTypeValue);
    }

    get hasRequests() {
        return this.myRequests.length > 0;
    }

    handleTypeChange(event) {
        this.typeValue = event.detail.value;
    }

    handleSpanTypeChange(event) {
        this.spanTypeValue = event.detail.value;
        this.durationValue = '';
    }

    handleDurationChange(event) {
        this.durationValue = event.detail.value;
    }

    handleStartDateChange(event) {
        this.startDateValue = event.detail.value;
    }

    handleStartDateTimeChange(event) {
        this.startDateTimeValue = event.detail.value;
    }

    handleCommentsChange(event) {
        this.commentsValue = event.detail.value;
    }

    handleSaveDraft() {
        this.saveRequest(STAGE_DRAFT);
    }

    handleSubmit() {
        this.saveRequest(STAGE_SUBMITTED);
    }

    async saveRequest(stage) {
        const validationMessage = this.validateForm();
        if (validationMessage) {
            this.showToast('Validation Error', validationMessage, 'error');
            return;
        }

        this.isSaving = true;
        try {
            const fields = {};
            fields[TYPE_FIELD.fieldApiName] = this.typeValue;
            fields[SPAN_TYPE_FIELD.fieldApiName] = this.spanTypeValue;
            fields[START_DATE_TIME_FIELD.fieldApiName] = this.buildStartDateTime();
            fields[COMMENTS_FIELD.fieldApiName] = this.commentsValue || null;
            fields[STAGE_FIELD.fieldApiName] = stage;

            if (this.isHoursSpan) {
                fields[SPAN_DURATION_SELECT_FIELD.fieldApiName] = this.durationValue;
            }

            const recordInput = {
                apiName: TIME_OFF_OBJECT.objectApiName,
                fields
            };

            const created = await createRecord(recordInput);
            const successTitle = stage === STAGE_SUBMITTED ? 'Submitted for Approval' : 'Draft Saved';
            const successMessage =
                stage === STAGE_SUBMITTED
                    ? 'Your time off request was submitted to your manager.'
                    : 'Your time off request was saved as a draft.';

            this.resetForm();
            await this.loadRequests();
            this.showToast(successTitle, successMessage, 'success');
            this.navigateToRecord(created.id);
        } catch (error) {
            this.showToast('Save Failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    validateForm() {
        if (!this.typeValue) {
            return 'Select a time off type.';
        }
        if (!this.spanTypeValue) {
            return 'Select a span type.';
        }
        if (this.isHoursSpan) {
            if (!this.durationValue) {
                return 'Select how many hours (1–8) for partial time off.';
            }
            if (!this.startDateTimeValue) {
                return 'Select a start date and time.';
            }
        }
        if (this.isFullDaySpan && !this.startDateValue) {
            return 'Select the date for your full day off.';
        }
        return null;
    }

    buildStartDateTime() {
        if (this.isFullDaySpan) {
            return `${this.startDateValue}T09:00:00`;
        }
        return this.startDateTimeValue.length === 16
            ? `${this.startDateTimeValue}:00`
            : this.startDateTimeValue;
    }

    resetForm() {
        this.typeValue = '';
        this.spanTypeValue = '';
        this.durationValue = '';
        this.startDateValue = '';
        this.startDateTimeValue = '';
        this.commentsValue = '';
    }

    mapRequestRow(request) {
        const spanTypeLabel = request.spanType === SPAN_FULL_DAY ? 'Full Day' : 'Partial (Hours)';
        const stageKey = request.stage || 'Draft';
        return {
            ...request,
            recordUrl: `/lightning/r/Time_Off_Request__c/${request.id}/view`,
            spanTypeLabel,
            startDateLabel: this.formatDate(request.startDate),
            endDateLabel: this.formatDate(request.endDate),
            stageClass: `slds-text-color_${STAGE_VARIANT[stageKey] || 'default'}`
        };
    }

    formatDate(value) {
        if (!value) {
            return '—';
        }
        return new Date(value).toLocaleDateString();
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: TIME_OFF_OBJECT.objectApiName,
                actionName: 'view'
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error?.body?.output?.errors?.length) {
            return error.body.output.errors.map((item) => item.message).join(', ');
        }
        if (error?.body?.output?.fieldErrors) {
            return Object.values(error.body.output.fieldErrors)
                .flat()
                .map((item) => item.message)
                .join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}