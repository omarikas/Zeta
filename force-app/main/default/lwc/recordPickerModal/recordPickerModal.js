import { LightningElement, api, track } from 'lwc';
import searchAttendeeCandidates from '@salesforce/apex/VisitCallReportController.searchAttendeeCandidates';

const DEBOUNCE_MS = 300;

export default class RecordPickerModal extends LightningElement {
    @api visitId;
    @api title = 'Add Attendees';
    @api open = false;

    @track candidates = [];
    searchTerm = '';
    isLoading = false;
    hasSearched = false;
    debounceTimer;

    renderedCallback() {
        if (this.open && !this.hasSearched && !this.isLoading) {
            this.runSearch(this.searchTerm || '');
        }
    }

    get dialogClass() {
        return `slds-modal slds-fade-in-open ${this.open ? '' : 'slds-hide'}`;
    }

    get backdropClass() {
        return `slds-backdrop ${this.open ? 'slds-backdrop_open' : ''}`;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this.debounceTimer);
        this.debounceTimer = setTimeout(() => {
            this.runSearch(this.searchTerm);
        }, DEBOUNCE_MS);
    }

    async runSearch(term) {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        this.hasSearched = true;
        try {
            this.candidates = await searchAttendeeCandidates({
                visitId: this.visitId,
                searchTerm: term,
                offset: 0
            });
        } catch (error) {
            this.candidates = [];
            // eslint-disable-next-line no-console
            console.error('Error searching attendees:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSelect(event) {
        const accountId = event.currentTarget.dataset.id;
        const candidate = this.candidates.find((row) => row.accountId === accountId);
        if (candidate) {
            this.dispatchEvent(
                new CustomEvent('select', {
                    detail: { candidate },
                    bubbles: true,
                    composed: true
                })
            );
        }
    }

    handleClose() {
        this.hasSearched = false;
        this.candidates = [];
        this.searchTerm = '';
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }
}