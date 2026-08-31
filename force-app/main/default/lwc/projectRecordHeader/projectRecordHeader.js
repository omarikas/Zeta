import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getProjectLeadInfo from '@salesforce/apex/ProjectManagementService.getProjectLeadInfo';
import NAME from '@salesforce/schema/Pharma_Project__c.Name';
import RECORD_TYPE_NAME from '@salesforce/schema/Pharma_Project__c.RecordType.Name';
import STATUS from '@salesforce/schema/Pharma_Project__c.Status__c';
import BUSINESS_UNIT from '@salesforce/schema/Pharma_Project__c.Business_Unit__c';
import CAMPAIGN_TYPE from '@salesforce/schema/Pharma_Project__c.Campaign_Type__c';
import START_DATE from '@salesforce/schema/Pharma_Project__c.Start_Date__c';
import END_DATE from '@salesforce/schema/Pharma_Project__c.End_Date__c';
import {
    getProjectTypeConfig,
    getStatusClass,
    formatDisplayDate
} from 'c/projectTypeUtils';

const FIELDS = [
    NAME,
    RECORD_TYPE_NAME,
    STATUS,
    BUSINESS_UNIT,
    CAMPAIGN_TYPE,
    START_DATE,
    END_DATE
];

export default class ProjectRecordHeader extends LightningElement {
    @api recordId;
    record;
    error;
    projectLeadInfo;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message;
            this.record = undefined;
        }
    }

    @wire(getProjectLeadInfo, { projectId: '$recordId' })
    wiredProjectLead({ data }) {
        this.projectLeadInfo = data;
    }

    get hasRecord() {
        return this.record != null;
    }

    get showProjectLead() {
        return this.projectLeadInfo?.fieldAvailable === true;
    }

    get projectName() {
        return getFieldValue(this.record, NAME) || 'Project';
    }

    get projectType() {
        return getFieldValue(this.record, RECORD_TYPE_NAME) || 'Project';
    }

    get status() {
        return getFieldValue(this.record, STATUS) || 'Planning';
    }

    get statusClass() {
        return getStatusClass(this.status);
    }

    get businessUnit() {
        return getFieldValue(this.record, BUSINESS_UNIT) || '—';
    }

    get campaignType() {
        return getFieldValue(this.record, CAMPAIGN_TYPE);
    }

    get projectLead() {
        return this.projectLeadInfo?.leadName || '—';
    }

    get startDate() {
        return getFieldValue(this.record, START_DATE);
    }

    get endDate() {
        return getFieldValue(this.record, END_DATE);
    }

    get startDateDisplay() {
        return formatDisplayDate(this.startDate);
    }

    get endDateDisplay() {
        return formatDisplayDate(this.endDate);
    }

    get typeConfig() {
        return getProjectTypeConfig(this.projectType);
    }

    get typeIconName() {
        return this.typeConfig.iconName;
    }

    get typeIconClass() {
        return `proj-header-type-icon ${this.typeConfig.cssClass}`;
    }

    get headerStyle() {
        const accent = this.typeConfig.accent || '#0176d3';
        return `--proj-accent: ${accent}; --proj-accent-soft: ${accent}22;`;
    }

    get headerShellClass() {
        return `proj-header proj-header--${this.typeConfig.cssClass.replace('proj-type-icon--', '')}`;
    }

    get timelineProgressStyle() {
        return `width: ${this.timelineProgressPercent}%`;
    }

    get timelineProgressPercent() {
        if (!this.startDate || !this.endDate) {
            return 0;
        }
        const start = new Date(this.startDate);
        const end = new Date(this.endDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (end <= start) {
            return 0;
        }
        if (today <= start) {
            return 0;
        }
        if (today >= end) {
            return 100;
        }
        const total = end.getTime() - start.getTime();
        const elapsed = today.getTime() - start.getTime();
        return Math.round((elapsed / total) * 100);
    }

    get hasDateRange() {
        return this.startDate && this.endDate;
    }

    get dateRangeCaption() {
        if (this.hasDateRange) {
            return `${this.timelineProgressPercent}% through project timeline`;
        }
        if (this.startDate) {
            return `Starts ${this.startDateDisplay}`;
        }
        if (this.endDate) {
            return `Ends ${this.endDateDisplay}`;
        }
        return 'Dates not set';
    }
}