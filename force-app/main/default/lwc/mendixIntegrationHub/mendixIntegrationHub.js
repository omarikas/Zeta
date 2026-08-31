import { LightningElement, wire } from 'lwc';
import getRecentSyncLogs from '@salesforce/apex/MendixSyncService.getRecentSyncLogs';
import getIntegrationStatus from '@salesforce/apex/MendixSyncService.getIntegrationStatus';
import MENDIX_LOGO from '@salesforce/resourceUrl/Mendix_Logo';

export default class MendixIntegrationHub extends LightningElement {
    mendixLogoUrl = MENDIX_LOGO;
    statusMessage;
    logs = [];
    error;

    @wire(getIntegrationStatus)
    wiredStatus({ data, error }) {
        if (data) this.statusMessage = data;
        if (error) this.error = error.body?.message;
    }

    @wire(getRecentSyncLogs)
    wiredLogs({ data, error }) {
        if (data) this.logs = data;
    }
}