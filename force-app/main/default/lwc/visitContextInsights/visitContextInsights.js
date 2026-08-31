import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getVisitContextInsights from '@salesforce/apex/VisitContextInsightsController.getVisitContextInsights';

export default class VisitContextInsights extends NavigationMixin(LightningElement) {
    @api visitId;

    insights;
    error;

    @wire(getVisitContextInsights, { visitId: '$visitId' })
    wiredInsights({ data, error }) {
        if (data) {
            this.insights = {
                ...data,
                territoryPriorVisits: this.decorateVisits(data.territoryPriorVisits),
                zetaPriorVisits: this.decorateVisits(data.zetaPriorVisits)
            };
            this.error = undefined;
            return;
        }
        if (error) {
            this.insights = undefined;
            this.error = error?.body?.message || 'Unable to load visit insights.';
        }
    }

    get hasTerritoryVisits() {
        return (this.insights?.territoryPriorVisits || []).length > 0;
    }

    get hasZetaVisits() {
        return (this.insights?.zetaPriorVisits || []).length > 0;
    }

    decorateVisits(rows) {
        return (rows || []).map((row) => ({
            ...row,
            whenLabel: this.formatDateTime(row.startDateTime)
        }));
    }

    formatDateTime(value) {
        if (!value) {
            return '—';
        }
        return new Date(value).toLocaleString([], {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    handleOpenVisit(event) {
        const visitId = event.currentTarget.dataset.id;
        if (!visitId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: visitId,
                objectApiName: 'Visit__c',
                actionName: 'view'
            }
        });
    }
}