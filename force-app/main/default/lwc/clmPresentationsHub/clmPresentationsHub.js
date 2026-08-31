import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/user/Id';
import getRepPresentations from '@salesforce/apex/ClmMetricsController.getRepPresentations';
import { getPresentationList, getUserPresentationListKey } from 'c/clmOfflineStore';
import { isOfflineMode } from 'c/clmOfflineSync';

export default class ClmPresentationsHub extends LightningElement {
    presentations = [];
    usingCachedPresentations = false;
    isLoading = true;

    showPlayer = false;
    activePresentationId;
    activePresentationName;

    connectedCallback() {
        this.loadPresentations();
    }

    async loadPresentations() {
        this.isLoading = true;
        try {
            if (isOfflineMode()) {
                await this.loadCachedPresentations();
                return;
            }
            const rows = await getRepPresentations();
            this.presentations = Array.isArray(rows) ? rows : [];
            this.usingCachedPresentations = false;
            if (!this.presentations.length) {
                await this.loadCachedPresentations();
            }
        } catch (error) {
            await this.loadCachedPresentations();
            if (!this.presentations.length) {
                this.showToast('Unable to load presentations', this.reduceError(error), 'error');
            }
        } finally {
            this.isLoading = false;
        }
    }

    async loadCachedPresentations() {
        try {
            const cached = await getPresentationList(getUserPresentationListKey(Id));
            this.presentations = cached?.presentations || [];
            this.usingCachedPresentations = this.presentations.length > 0;
        } catch (error) {
            this.presentations = [];
            this.usingCachedPresentations = false;
        }
    }

    get hasPresentations() {
        return this.presentations.length > 0;
    }

    get offlineHint() {
        if (this.isLoading) {
            return 'Loading presentations…';
        }
        if (this.usingCachedPresentations) {
            return 'Showing cached CLMs from device';
        }
        return `${this.presentations.length} presentation${this.presentations.length === 1 ? '' : 's'} available`;
    }

    get presentationCards() {
        return this.presentations.map((pres) => ({
            key: pres.id,
            id: pres.id,
            name: pres.name,
            productName: pres.productName || '—',
            imageUrl: pres.imageUrl,
            slideCount: pres.slideCount || 0,
            slideCountLabel: `${pres.slideCount || 0} ${(pres.slideCount || 0) === 1 ? 'slide' : 'slides'}`,
            formatType: pres.formatType || '—',
            tags: pres.tags
        }));
    }

    handlePresent(event) {
        const presentationId = event.currentTarget.dataset.id;
        const presentationName = event.currentTarget.dataset.name;
        if (!presentationId) {
            return;
        }

        this.activePresentationId = presentationId;
        this.activePresentationName = presentationName;
        this.showPlayer = true;
    }

    handlePlayerClose() {
        this.showPlayer = false;
        this.activePresentationId = null;
        this.activePresentationName = null;
        this.loadPresentations();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}