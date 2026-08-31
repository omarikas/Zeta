import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/user/Id';
import getAvailablePresentations from '@salesforce/apex/ClmMetricsController.getAvailablePresentations';
import getVisitSessions from '@salesforce/apex/ClmMetricsController.getVisitSessions';
import { getPresentationList, getUserPresentationListKey } from 'c/clmOfflineStore';
import { isOfflineMode } from 'c/clmOfflineSync';

export default class ClmVisitPresentations extends LightningElement {
    @api recordId;
    @api isLocked = false;

    presentations = [];
    sessions = [];
    wiredPresentationsResult;
    wiredSessionsResult;

    showPlayer = false;
    activePresentationId;
    activePresentationName;
    activeSessionId;
    showFeedbackForSession = false;
    usingCachedPresentations = false;

    connectedCallback() {
        if (isOfflineMode()) {
            this.loadCachedPresentations();
        }
    }

    @wire(getAvailablePresentations, { visitId: '$recordId' })
    wiredPresentations(result) {
        this.wiredPresentationsResult = result;
        if (result.data) {
            this.presentations = result.data;
            this.usingCachedPresentations = false;
        } else if (result.error || isOfflineMode()) {
            this.loadCachedPresentations();
        }
    }

    @wire(getVisitSessions, { visitId: '$recordId' })
    wiredSessions(result) {
        this.wiredSessionsResult = result;
        this.sessions = result.data || [];
    }

    get hasPresentations() {
        return this.presentations.length > 0;
    }

    get offlineHint() {
        return this.usingCachedPresentations ? 'Showing cached CLMs from device' : '';
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

    get hasSessions() {
        return this.sessions.length > 0;
    }

    get presentationCards() {
        return this.presentations.map((pres) => ({
            key: pres.id,
            id: pres.id,
            name: pres.name,
            productName: pres.productName || '—',
            imageUrl: pres.imageUrl,
            slideCount: pres.slideCount || 0,
            formatType: pres.formatType
        }));
    }

    get sessionCards() {
        return this.sessions.map((session) => ({
            key: session.id,
            id: session.id,
            name: session.presentationName,
            status: session.status,
            duration: this.formatDuration(session.totalDurationSeconds),
            slidesLabel: `${session.slidesPresentedCount || 0}/${session.slideCount || 0} slides presented`,
            canFeedback: session.status === 'Completed'
        }));
    }

    handleOpenPresentation(event) {
        if (this.isLocked) {
            return;
        }
        const presentationId = event.currentTarget.dataset.id;
        const presentationName = event.currentTarget.dataset.name;
        this.activePresentationId = presentationId;
        this.activePresentationName = presentationName;
        this.showPlayer = true;
    }

    handlePlayerClose() {
        this.showPlayer = false;
        this.activePresentationId = null;
        this.activePresentationName = null;
        this.refreshData();
    }

    async handleSessionComplete(event) {
        const session = event.detail?.session;
        this.activeSessionId = session?.id;
        this.showFeedbackForSession = true;
        await this.refreshData();
    }

    handleOpenFeedback(event) {
        this.activeSessionId = event.currentTarget.dataset.id;
        this.showFeedbackForSession = true;
    }

    handleFeedbackSaved() {
        this.showFeedbackForSession = false;
        this.activeSessionId = null;
        this.showToast('Feedback saved', 'Responses captured for this presentation session.', 'success');
    }

    handleFeedbackCancel() {
        this.showFeedbackForSession = false;
        this.activeSessionId = null;
    }

    async refreshData() {
        await Promise.all([
            refreshApex(this.wiredPresentationsResult),
            refreshApex(this.wiredSessionsResult)
        ]);
    }

    formatDuration(seconds) {
        const total = Number(seconds) || 0;
        const mins = Math.floor(total / 60);
        const secs = Math.round(total % 60);
        return `${mins}m ${secs}s`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}