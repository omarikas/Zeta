import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTileTargets from '@salesforce/apex/ReportsHubController.getTileTargets';

export default class ReportsHub extends NavigationMixin(LightningElement) {
    @track searchTerm = '';
    @track tileTargets = {};
    @track loadState = 'loading';

    reportCards = [
        {
            id: 'working-days-analysis',
            accent: 'blue',
            title: 'Working Days Analysis',
            description: 'Working days, activity, visits, and TOT by territory and month.',
            icon: 'utility:table'
        },
        {
            id: 'medical-rep-360',
            accent: 'teal',
            title: 'Medical Rep 360',
            description: 'Coverage, visit targets, CLM usage, and coaching trends.',
            icon: 'utility:chart'
        },
        {
            id: 'pharmacy-sales',
            accent: 'green',
            title: 'Pharmacy Sales',
            description: 'Sell-out withdrawals and revenue by product, brick, and data source.',
            icon: 'utility:product'
        }
    ];

    @wire(getTileTargets)
    wiredTileTargets({ data, error }) {
        if (data) {
            this.tileTargets = data;
            this.loadState = 'ready';
        } else if (error) {
            this.tileTargets = {};
            this.loadState = 'error';
        }
    }

    get moduleCount() {
        return this.reportCards.length;
    }

    get cardsView() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const filtered = term
            ? this.reportCards.filter(
                  (card) =>
                      card.title.toLowerCase().includes(term) ||
                      card.description.toLowerCase().includes(term)
              )
            : this.reportCards;

        return filtered.map((card) => {
            const target = this.tileTargets[card.id];
            const accessible = target?.accessible === true;
            return {
                ...card,
                cardClass: `reports-hub-card reports-hub-card--${card.accent}${accessible ? '' : ' reports-hub-card--disabled'}`,
                ariaLabel: accessible
                    ? `${card.title}. ${card.description}`
                    : `${card.title}. Not available for your profile.`,
                disabled: !accessible
            };
        });
    }

    get hasResults() {
        return this.cardsView.length > 0;
    }

    get targetsLoaded() {
        return this.loadState !== 'loading';
    }

    get isLoading() {
        return this.loadState === 'loading';
    }

    get showEmptySearch() {
        return this.targetsLoaded && !this.hasResults;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleCardClick(event) {
        if (event.key && event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        if (event.key) {
            event.preventDefault();
        }

        const cardId = event.currentTarget.dataset.cardId;
        const target = this.tileTargets[cardId];
        if (!target?.accessible) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Not available',
                    message: 'You do not have access to this report or dashboard.',
                    variant: 'warning'
                })
            );
            return;
        }

        if (target.objectApiName === 'Tab' && target.apiName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: target.apiName
                }
            });
            return;
        }

        if (!target.recordId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Not available',
                    message: 'You do not have access to this report or dashboard.',
                    variant: 'warning'
                })
            );
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: target.recordId,
                objectApiName: target.objectApiName,
                actionName: 'view'
            }
        });
    }
}