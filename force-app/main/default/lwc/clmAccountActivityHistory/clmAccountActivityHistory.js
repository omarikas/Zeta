import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountActivityTimeline from '@salesforce/apex/AccountActivityController.getAccountActivityTimeline';
import getAccountVisitInsights from '@salesforce/apex/AccountActivityController.getAccountVisitInsights';

const SOURCE_AGENTFORCE = 'Agentforce';

export default class ClmAccountActivityHistory extends NavigationMixin(LightningElement) {
    @api recordId;

    history = [];
    groupedHistory = [];
    expandedKeys = new Set();
    error;

    isInsightsModalOpen = false;
    isInsightsLoading = false;
    insights;
    insightsError;

    @wire(getAccountActivityTimeline, { accountId: '$recordId', recordLimit: 50 })
    wiredHistory({ data, error }) {
        if (data) {
            this.history = data.map((item, index) => this.decorateItem(item, index));
            this.groupedHistory = this.buildDateGroups(this.history);
            if (this.history.length > 0) {
                this.expandedKeys = new Set([this.history[0].key]);
                this.groupedHistory = this.buildDateGroups(this.history);
            }
            this.error = undefined;
            return;
        }

        if (error) {
            this.history = [];
            this.groupedHistory = [];
            this.error = error?.body?.message || 'Unable to load activity history.';
        }
    }

    get hasHistory() {
        return this.groupedHistory.length > 0;
    }

    get hasInsights() {
        return Boolean(this.insights);
    }

    get hasProductsDiscussed() {
        return (this.insights?.productsDiscussed?.length || 0) > 0;
    }

    get hasPainPoints() {
        return (this.insights?.painPoints?.length || 0) > 0;
    }

    get hasPositiveSignals() {
        return (this.insights?.positiveSignals?.length || 0) > 0;
    }

    get hasCustomerFeedback() {
        return (this.insights?.customerFeedback?.length || 0) > 0;
    }

    get hasTalkingPoints() {
        return (this.insights?.suggestedTalkingPoints?.length || 0) > 0;
    }

    get insightsSourceLabel() {
        if (!this.insights?.source) {
            return '';
        }
        return this.insights.source === SOURCE_AGENTFORCE ? 'Powered by Agentforce' : 'Structured summary';
    }

    get insightsSourceClass() {
        return this.insights?.source === SOURCE_AGENTFORCE
            ? 'insights-source insights-source-agentforce'
            : 'insights-source insights-source-structured';
    }

    decorateItem(item, index) {
        const presentations = (item.presentations || []).map((pres, presIndex) => ({
            ...pres,
            key: `${item.key}-pres-${presIndex}`,
            slideThumbnails: (pres.slideThumbnails || []).map((thumb, thumbIndex) => ({
                ...thumb,
                key: `${item.key}-pres-${presIndex}-thumb-${thumbIndex}`,
                hasImage: Boolean(thumb.thumbnailUrl)
            })),
            hasThumbnails: (pres.slideThumbnails || []).length > 0
        }));

        const isExpanded = index === 0;

        return {
            ...item,
            products: item.products || [],
            productNames: item.productNames || [],
            detailLines: item.detailLines || [],
            presentations,
            whenLabel: this.formatDateTime(item.activityDate),
            hasProducts: (item.products || []).length > 0,
            hasPresentations: presentations.length > 0,
            hasAddress: Boolean(item.address),
            hasChannel: Boolean(item.channel),
            hasDetails: (item.detailLines || []).length > 0,
            isVisit: item.type === 'visit',
            isPresentation: item.type === 'presentation',
            isEmail: item.type === 'email',
            isPrimary: item.type === 'visit' || item.type === 'presentation',
            linkObjectApiName: this.resolveObjectApiName(item.type),
            isExpanded,
            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            cardClass: this.buildCardClass(item.type, isExpanded),
            timelineItemClass: this.buildTimelineItemClass(item.type),
            iconContainerClass: this.buildIconContainerClass(item.type),
            timelineIconName: this.resolveTimelineIcon(item.type)
        };
    }

    resolveTimelineIcon(type) {
        if (type === 'visit') {
            return 'standard:event';
        }
        if (type === 'presentation') {
            return 'standard:screen';
        }
        return 'standard:email';
    }

    buildTimelineItemClass(type) {
        const classes = ['slds-timeline__item_expandable'];
        if (type === 'visit') {
            classes.push('slds-timeline__item_event');
        } else if (type === 'presentation') {
            classes.push('slds-timeline__item_task');
        } else {
            classes.push('slds-timeline__item_email');
        }
        return classes.join(' ');
    }

    buildIconContainerClass(type) {
        if (type === 'visit') {
            return 'slds-icon_container slds-icon-standard-event slds-timeline__icon';
        }
        if (type === 'presentation') {
            return 'slds-icon_container slds-icon-standard-screen slds-timeline__icon';
        }
        return 'slds-icon_container slds-icon-standard-email slds-timeline__icon';
    }

    resolveObjectApiName(type) {
        if (type === 'visit') {
            return 'Visit__c';
        }
        if (type === 'presentation') {
            return 'CLM_Presentation_Session__c';
        }
        if (type === 'email') {
            return 'Task';
        }
        return null;
    }

    buildCardClass(type, isExpanded) {
        const classes = ['timeline-card'];
        if (type === 'visit') {
            classes.push('timeline-card-visit');
        } else if (type === 'presentation') {
            classes.push('timeline-card-presentation');
        } else {
            classes.push('timeline-card-secondary');
        }
        if (isExpanded) {
            classes.push('is-expanded');
        }
        return classes.join(' ');
    }

    buildDateGroups(items) {
        const groups = [];
        const groupMap = new Map();

        items.forEach((item) => {
            const label = item.dateGroupLabel || 'Earlier';
            if (!groupMap.has(label)) {
                const group = { key: label, label, items: [] };
                groupMap.set(label, group);
                groups.push(group);
            }
            const group = groupMap.get(label);
            const isExpanded = this.expandedKeys.has(item.key);
            group.items.push({
                ...item,
                isExpanded,
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                cardClass: this.buildCardClass(item.type, isExpanded),
                linkObjectApiName: this.resolveObjectApiName(item.type),
                timelineItemClass: this.buildTimelineItemClass(item.type),
                iconContainerClass: this.buildIconContainerClass(item.type),
                timelineIconName: this.resolveTimelineIcon(item.type)
            });
        });

        return groups;
    }

    handleToggleExpand(event) {
        const itemKey = event.currentTarget.dataset.key;
        const nextExpanded = new Set(this.expandedKeys);
        if (nextExpanded.has(itemKey)) {
            nextExpanded.delete(itemKey);
        } else {
            nextExpanded.add(itemKey);
        }
        this.expandedKeys = nextExpanded;
        this.groupedHistory = this.buildDateGroups(this.history);
    }

    async handleOpenInsights() {
        this.isInsightsModalOpen = true;
        this.isInsightsLoading = true;
        this.insightsError = undefined;
        try {
            this.insights = await getAccountVisitInsights({ accountId: this.recordId });
        } catch (error) {
            this.insights = undefined;
            this.insightsError = error?.body?.message || 'Unable to generate insights.';
            this.toast('Agent insights', this.insightsError, 'error');
        } finally {
            this.isInsightsLoading = false;
        }
    }

    handleCloseInsights() {
        this.isInsightsModalOpen = false;
    }

    handleOpenRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;
        if (!recordId || !objectApiName) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    formatDateTime(value) {
        if (!value) {
            return '—';
        }
        const date = new Date(value);
        return date.toLocaleString([], {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}