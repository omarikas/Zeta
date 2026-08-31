import { LightningElement, api, wire } from 'lwc';
import getActiveClmPresentations from '@salesforce/apex/VisitCallReportController.getActiveClmPresentations';

export default class VisitClmPanel extends LightningElement {
    @api clmSessions = [];
    @api clmPresentation;
    @api disabled = false;

    presentationOptions = [];

    @wire(getActiveClmPresentations)
    wiredPresentations({ data }) {
        if (data) {
            this.presentationOptions = data.map((row) => ({
                label: row.Name,
                value: row.Name
            }));
        }
    }

    get displaySessions() {
        return (this.clmSessions || []).map((row, index) => ({
            ...row,
            key: row.id || `session-${index}`,
            durationLabel: row.totalDurationSeconds
                ? `${Math.round(row.totalDurationSeconds / 60)} min`
                : '—'
        }));
    }

    handlePresentationChange(event) {
        this.dispatchEvent(
            new CustomEvent('presentationchange', {
                detail: { value: event.detail.value },
                bubbles: true,
                composed: true
            })
        );
    }
}