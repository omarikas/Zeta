import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInsightsContext from '@salesforce/apex/PharmacySalesInsightsController.getInsightsContext';
import generateInsights from '@salesforce/apex/PharmacySalesInsightsController.generateInsights';
import updateRecommendation from '@salesforce/apex/PharmacySalesInsightsController.updateRecommendation';
import applyAcceptedRecommendations from '@salesforce/apex/PharmacySalesInsightsController.applyAcceptedRecommendations';
import saveVision from '@salesforce/apex/PharmacySalesInsightsController.saveVision';

const TRENDS_PER_PAGE = 3;
const DETAIL_PAGES = ['summary', 'market', 'brand', 'vision'];

const RECOMMENDATION_PRIORITY = {
    EnsurePlan: 1,
    UpdatePlanTarget: 2,
    CreateVisit: 3,
    UpdateAccountRating: 4,
    UpdateVision: 5
};

export default class PharmacySalesAgentInsights extends LightningElement {
    @api filterState;

    @track isModalOpen = false;
    @track isLoading = false;
    @track isApplying = false;
    @track insights;
    @track vision;
    @track repOptions = [];
    @track territoryOptions = [];
    @track selectedRepIds = [];
    @track detailPage = 'summary';
    @track marketTrendPage = 0;
    @track brandTrendPage = 0;

    _initialized = false;

    connectedCallback() {
        this.bootstrap();
    }

    @api
    refreshFromParent(filterState) {
        this.filterState = filterState;
        if (this._initialized) {
            this.loadInsights();
        }
    }

    get hasInsights() {
        return Boolean(this.insights);
    }

    get hasRecommendations() {
        return this.prioritizedRecommendations.length > 0;
    }

    get recommendationCount() {
        const count = this.prioritizedRecommendations.length;
        return count ? String(count) : '';
    }

    get teaserText() {
        if (this.isLoading) {
            return 'Generating insights…';
        }
        if (this.insights?.headline) {
            return this.truncate(this.insights.headline, 72);
        }
        return 'Sell-out trends and plan recommendations';
    }

    get detailTabs() {
        return [
            { id: 'summary', label: 'Summary', buttonClass: this.tabClass('summary') },
            { id: 'market', label: 'Market', buttonClass: this.tabClass('market') },
            { id: 'brand', label: 'Brand', buttonClass: this.tabClass('brand') },
            { id: 'vision', label: 'Vision', buttonClass: this.tabClass('vision') }
        ];
    }

    get isSummaryPage() {
        return this.detailPage === 'summary';
    }

    get isMarketPage() {
        return this.detailPage === 'market';
    }

    get isBrandPage() {
        return this.detailPage === 'brand';
    }

    get isVisionPage() {
        return this.detailPage === 'vision';
    }

    get marketTrends() {
        return this.decorateTrends(this.insights?.marketTrends || []);
    }

    get brandTrends() {
        return this.decorateTrends(this.insights?.brandTrends || []);
    }

    get paginatedMarketTrends() {
        return this.sliceTrendPage(this.marketTrends, this.marketTrendPage);
    }

    get paginatedBrandTrends() {
        return this.sliceTrendPage(this.brandTrends, this.brandTrendPage);
    }

    get marketPageCount() {
        return this.trendPageCount(this.marketTrends);
    }

    get brandPageCount() {
        return this.trendPageCount(this.brandTrends);
    }

    get marketPageIndicator() {
        return `${this.marketTrendPage + 1} / ${this.marketPageCount}`;
    }

    get brandPageIndicator() {
        return `${this.brandTrendPage + 1} / ${this.brandPageCount}`;
    }

    get marketPrevDisabled() {
        return this.marketTrendPage === 0;
    }

    get marketNextDisabled() {
        return this.marketTrendPage >= this.marketPageCount - 1;
    }

    get brandPrevDisabled() {
        return this.brandTrendPage === 0;
    }

    get brandNextDisabled() {
        return this.brandTrendPage >= this.brandPageCount - 1;
    }

    get prioritizedRecommendations() {
        const recs = [...(this.insights?.recommendations || [])];
        recs.sort((left, right) => this.compareRecommendations(left, right));
        return recs.map((rec, index) => {
            const rank = index + 1;
            return {
                ...rec,
                key: rec.recordId || rec.key,
                isSelected: rec.selected !== false && rec.status !== 'Rejected',
                typeLabel: this.typeLabel(rec.recommendationType),
                priorityLabel: `P${rank}`,
                priorityClass: this.priorityClass(rank),
                cardClass: `rec-card${rank === 1 ? ' rec-card--top' : ''}`
            };
        });
    }

    get selectedCount() {
        return this.prioritizedRecommendations.filter((rec) => rec.isSelected).length;
    }

    get applyDisabled() {
        return this.isApplying || this.selectedCount === 0 || !this.insights?.sessionId;
    }

    get applyLabel() {
        const count = this.selectedCount;
        return count ? `Apply ${count} recommendation${count === 1 ? '' : 's'}` : 'Apply recommendations';
    }

    tabClass(pageId) {
        return `detail-tab${this.detailPage === pageId ? ' detail-tab--active' : ''}`;
    }

    compareRecommendations(left, right) {
        const leftOrder = left.sortOrder != null ? left.sortOrder : 999;
        const rightOrder = right.sortOrder != null ? right.sortOrder : 999;
        if (leftOrder !== rightOrder) {
            return leftOrder - rightOrder;
        }
        const leftType = RECOMMENDATION_PRIORITY[left.recommendationType] || 99;
        const rightType = RECOMMENDATION_PRIORITY[right.recommendationType] || 99;
        return leftType - rightType;
    }

    priorityClass(rank) {
        if (rank === 1) {
            return 'rec-priority-badge rec-priority-badge--high';
        }
        if (rank <= 3) {
            return 'rec-priority-badge rec-priority-badge--medium';
        }
        return 'rec-priority-badge';
    }

    decorateTrends(trends) {
        return trends.map((trend) => ({
            ...trend,
            key: trend.id,
            directionClass: `trend-direction trend-direction--${trend.direction || 'flat'}`
        }));
    }

    sliceTrendPage(trends, pageIndex) {
        const start = pageIndex * TRENDS_PER_PAGE;
        return trends.slice(start, start + TRENDS_PER_PAGE);
    }

    trendPageCount(trends) {
        return Math.max(1, Math.ceil(trends.length / TRENDS_PER_PAGE));
    }

    truncate(value, maxLength) {
        if (!value || value.length <= maxLength) {
            return value || '';
        }
        return `${value.slice(0, maxLength - 1)}…`;
    }

    handleOpenModal() {
        this.isModalOpen = true;
        this.detailPage = 'summary';
        this.marketTrendPage = 0;
        this.brandTrendPage = 0;
    }

    handleCloseModal() {
        this.isModalOpen = false;
    }

    handleDetailTab(event) {
        const page = event.currentTarget.dataset.page;
        if (DETAIL_PAGES.includes(page)) {
            this.detailPage = page;
        }
    }

    handleMarketPrev() {
        if (this.marketTrendPage > 0) {
            this.marketTrendPage -= 1;
        }
    }

    handleMarketNext() {
        if (this.marketTrendPage < this.marketPageCount - 1) {
            this.marketTrendPage += 1;
        }
    }

    handleBrandPrev() {
        if (this.brandTrendPage > 0) {
            this.brandTrendPage -= 1;
        }
    }

    handleBrandNext() {
        if (this.brandTrendPage < this.brandPageCount - 1) {
            this.brandTrendPage += 1;
        }
    }

    handleRefreshClick(event) {
        event.stopPropagation();
        this.handleRefresh();
    }

    async bootstrap() {
        try {
            const context = await getInsightsContext({ filters: this.buildFilters() });
            this.repOptions = (context?.reps || []).map((rep) => ({
                label: rep.territoryName ? `${rep.label} (${rep.territoryName})` : rep.label,
                value: rep.value
            }));
            this.territoryOptions = context?.territories || [];
            this.vision = context?.vision || {};
            if (this.repOptions.length) {
                this.selectedRepIds = [this.repOptions[0].value];
            }
            this._initialized = true;
            await this.loadInsights();
        } catch (error) {
            this.toast('Agentforce', this.reduceError(error), 'error');
        }
    }

    async loadInsights() {
        this.isLoading = true;
        try {
            this.insights = await generateInsights({
                filters: this.buildFilters(),
                visionDraft: this.vision
            });
            if (this.insights?.vision) {
                this.vision = { ...this.insights.vision };
            }
            this.marketTrendPage = 0;
            this.brandTrendPage = 0;
        } catch (error) {
            this.insights = null;
            this.toast('Agentforce', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    buildFilters() {
        const base = this.filterState || {};
        return {
            startMonth: base.startMonth || null,
            endMonth: base.endMonth || null,
            dataSource: base.dataSource || 'All',
            therapyArea: base.therapyArea || 'All',
            productFamily: base.productFamily || 'All',
            brickId: base.brickId && base.brickId !== 'All' ? base.brickId : null,
            pharmacyIds: base.pharmacyId && base.pharmacyId !== 'All' ? [base.pharmacyId] : null,
            repIds: this.selectedRepIds
        };
    }

    handleRefresh() {
        this.loadInsights();
    }

    handleRepChange(event) {
        this.selectedRepIds = event.detail.value;
        this.loadInsights();
    }

    handleVisionSummaryChange(event) {
        this.vision = { ...this.vision, visionSummary: event.target.value };
    }

    handleFocusTherapyChange(event) {
        this.vision = { ...this.vision, focusTherapyAreas: event.target.value };
    }

    handleFocusFamiliesChange(event) {
        this.vision = { ...this.vision, focusProductFamilies: event.target.value };
    }

    handleWeightsChange(event) {
        this.vision = { ...this.vision, classificationVisitWeights: event.target.value };
    }

    async handleSaveVision() {
        try {
            this.vision = await saveVision({ visionDraft: this.vision });
            this.toast('Vision saved', 'Planning vision updated for the next cycle.', 'success');
            await this.loadInsights();
        } catch (error) {
            this.toast('Vision save failed', this.reduceError(error), 'error');
        }
    }

    async handleRecommendationToggle(event) {
        const recordId = event.target.dataset.id;
        const selected = event.target.checked;
        try {
            const updated = await updateRecommendation({
                sessionId: this.insights.sessionId,
                edit: { recordId, selected }
            });
            this.insights = {
                ...this.insights,
                recommendations: this.insights.recommendations.map((rec) =>
                    rec.recordId === recordId ? { ...rec, ...updated, selected } : rec
                )
            };
        } catch (error) {
            this.toast('Update failed', this.reduceError(error), 'error');
        }
    }

    async handleApply() {
        const acceptedIds = this.prioritizedRecommendations
            .filter((rec) => rec.isSelected)
            .map((rec) => rec.recordId);
        if (!acceptedIds.length) {
            return;
        }
        this.isApplying = true;
        try {
            const result = await applyAcceptedRecommendations({
                sessionId: this.insights.sessionId,
                acceptedRecommendationIds: acceptedIds
            });
            this.toast('Agentforce applied', result.message, result.failedCount ? 'warning' : 'success');
            await this.loadInsights();
        } catch (error) {
            this.toast('Apply failed', this.reduceError(error), 'error');
        } finally {
            this.isApplying = false;
        }
    }

    typeLabel(type) {
        const labels = {
            EnsurePlan: 'Plan cycle',
            UpdatePlanTarget: 'Visit target',
            CreateVisit: 'Visit',
            UpdateAccountRating: 'Rating',
            UpdateVision: 'Vision'
        };
        return labels[type] || type;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}