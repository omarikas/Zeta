import { LightningElement, track } from 'lwc';
import getHomeDashboard from '@salesforce/apex/PlannerMobileRestService.getHomeDashboard';
import { getHomeMetricsCache, getUserHomeMetricsKey, putHomeMetrics } from 'c/clmOfflineStore';

const HOME_DASHBOARD_PATH = '/services/apexrest/planner/v1/home/dashboard';
const CACHE_USER_FALLBACK = 'me';

const BADGE_DEFINITIONS = [
    {
        id: 'coverage_champion',
        label: 'Coverage Champion',
        icon: '🏆',
        hint: 'Reach 80% visit coverage this cycle',
        earnDescription: '80% visit coverage this month'
    },
    {
        id: 'on_target',
        label: 'On Target',
        icon: '🎯',
        hint: 'Achieve 100% of your call plan',
        earnDescription: '100% of your call plan'
    },
    {
        id: 'class_a_ace',
        label: 'Class A Ace',
        icon: '⭐',
        hint: 'Reach 90% Class A visit coverage',
        earnDescription: '90% Class A account coverage'
    },
    {
        id: 'streak_starter',
        label: 'Streak Starter',
        icon: '🔥',
        hint: 'Log visits on 3 consecutive working days',
        earnDescription: '3-day activity streak'
    },
    {
        id: 'perfect_week',
        label: 'Perfect Week',
        icon: '📅',
        hint: 'Visit accounts every weekday this week',
        earnDescription: 'visits on all 5 weekdays this week'
    },
    {
        id: 'early_bird',
        label: 'Early Bird',
        icon: '🌅',
        hint: 'Check in before 9 AM on any field day',
        earnDescription: 'check-in before 9 AM'
    }
];

const CLASS_COLORS = {
    A: { accent: '#0176d3', bg: 'rgba(1, 118, 211, 0.07)' },
    B: { accent: '#2e844a', bg: 'rgba(46, 132, 74, 0.08)' },
    C: { accent: '#fe9339', bg: 'rgba(254, 147, 57, 0.1)' }
};

const FILTER_VALUES = ['All', 'A', 'B', 'C'];
const RING_RADIUS = 28;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

const TIER_CONFIG = {
    starter: {
        label: 'Starter',
        icon: '🌱',
        accent: '#8b9196',
        gradientStart: '#c4c9ce',
        gradientEnd: '#8b9196',
        bg: 'rgba(139, 145, 150, 0.07)'
    },
    builder: {
        label: 'Builder',
        icon: '🔨',
        accent: '#cd7f32',
        gradientStart: '#e8a857',
        gradientEnd: '#b5651d',
        bg: 'rgba(205, 127, 50, 0.09)'
    },
    achiever: {
        label: 'Achiever',
        icon: '⚡',
        accent: '#0176d3',
        gradientStart: '#4a9eed',
        gradientEnd: '#014486',
        bg: 'rgba(1, 118, 211, 0.08)'
    },
    champion: {
        label: 'Champion',
        icon: '🏆',
        accent: '#f4b400',
        gradientStart: '#ffd54f',
        gradientEnd: '#e6a200',
        bg: 'rgba(244, 180, 0, 0.1)'
    },
    legend: {
        label: 'Legend',
        icon: '⭐',
        accent: '#7c4dff',
        gradientStart: '#b388ff',
        gradientEnd: '#651fff',
        bg: 'rgba(124, 77, 255, 0.1)'
    }
};

const NEXT_TIER = {
    starter: { threshold: 25, label: 'Builder' },
    builder: { threshold: 50, label: 'Achiever' },
    achiever: { threshold: 80, label: 'Champion' },
    champion: { threshold: 100, label: 'Legend' }
};

const TIER_TAGLINES = {
    starter: ['Keep pushing!', 'Every visit counts', 'Build your foundation'],
    builder: ['Almost there!', 'Building momentum', 'Keep climbing'],
    achiever: ['On fire!', 'Strong progress', "You're crushing it"],
    champion: ['Champion level!', 'So close to Legend', 'Elite performance'],
    legend: ['Legend status!', 'Maximum impact!', 'At the top!']
};

const KPI_MILESTONES = [25, 50, 80, 100];
const ACCOUNT_PAGE_SIZE = 5;
const SEARCH_DEBOUNCE_MS = 200;
const CLASS_SORT_ORDER = { A: 0, B: 1, C: 2, Other: 3 };
const STATUS_SORT_ORDER = { LCF: 0, RCF: 1, MCF: 2 };
const SORTABLE_ACCOUNT_FIELDS = ['name', 'class', 'reach', 'status'];

function normalizeClass(value) {
    if (!value) {
        return 'Other';
    }
    const v = String(value).trim().toUpperCase();
    if (v === 'A' || v === 'B' || v === 'C') {
        return v;
    }
    return 'Other';
}

function ringOffset(percent) {
    const p = Math.min(100, Math.max(0, Math.round(percent || 0)));
    return RING_CIRCUMFERENCE - (p / 100) * RING_CIRCUMFERENCE;
}

function ringStroke(percent) {
    const offset = ringOffset(percent);
    return `stroke-dasharray: ${RING_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`;
}

function resolveTierId(percent) {
    const p = Math.round(percent || 0);
    if (p >= 100) {
        return 'legend';
    }
    if (p >= 80) {
        return 'champion';
    }
    if (p >= 50) {
        return 'achiever';
    }
    if (p >= 25) {
        return 'builder';
    }
    return 'starter';
}

function taglineForTier(tierId, percent) {
    const lines = TIER_TAGLINES[tierId] || TIER_TAGLINES.starter;
    return lines[Math.floor((percent || 0) / 10) % lines.length];
}

function isMilestonePercent(percent) {
    const p = Math.round(percent || 0);
    return KPI_MILESTONES.some((milestone) => p === milestone || (milestone === 100 && p > 100));
}

function buildKpiCard(id, label, hint, percent) {
    const percentDisplay = Math.round(percent || 0);
    const tierId = resolveTierId(percentDisplay);
    const tier = TIER_CONFIG[tierId];
    const offset = ringOffset(percentDisplay);
    const next = NEXT_TIER[tierId];
    const gap = next ? Math.max(0, next.threshold - percentDisplay) : 0;

    return {
        id,
        label,
        hint,
        percentDisplay,
        tierId,
        tierLabel: tier.label,
        tierIcon: tier.icon,
        tierAriaLabel: `Tier: ${tier.label}`,
        tagline: taglineForTier(tierId, percentDisplay),
        ringStyle: `stroke-dasharray: ${RING_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`,
        cardClass: `kpi-card kpi-card-tier-${tierId}${tierId === 'legend' ? ' kpi-card-legend' : ''}`,
        cardStyle: `border-left-color: ${tier.accent}; background: linear-gradient(135deg, ${tier.bg} 0%, #fff 100%);`,
        ringFillClass: `kpi-ring-fill kpi-ring-fill-tier-${tierId}${tierId === 'legend' ? ' kpi-ring-legend-pulse' : ''}`,
        tierPillClass: `kpi-tier-pill kpi-tier-pill-${tierId}`,
        showNextTier: Boolean(next && gap > 0),
        nextTierLabel: next ? `${gap}% to ${next.label}` : '',
        showMilestoneSparkle: isMilestonePercent(percentDisplay),
        ariaLabel: `${label}: ${percentDisplay} percent, ${tier.label} tier. ${taglineForTier(tierId, percentDisplay)}`
    };
}

const EMPTY_METRICS = {
    visitCoveragePercentDisplay: 0,
    customerCoveragePercentDisplay: 0,
    rfPercentTotalDisplay: 0,
    visitRingStroke: ringStroke(0),
    customerRingStroke: ringStroke(0),
    rfRingStroke: ringStroke(0),
    byClassification: []
};

const EMPTY_GAMIFICATION = {
    userFirstName: '',
    streaks: { activityStreak: 0, coverageStreak: 0 },
    badges: []
};

const EMPTY_RANKINGS = {
    buName: '',
    buRank: null,
    buTotal: 0,
    companyRank: null,
    companyTotal: 0,
    myCoveragePercent: 0,
    top5InBu: [],
    top5Company: [],
    personAbove: null,
    isFirstInBu: false
};

function tokenizeSearch(raw) {
    return (raw || '')
        .trim()
        .toLowerCase()
        .split(/\s+/)
        .filter(Boolean);
}

function classSortValue(row) {
    const clazz = normalizeClass(row.calculatedClassification || row.filterClass);
    return CLASS_SORT_ORDER[clazz] ?? 99;
}

function statusSortValue(row) {
    const status = row.frequencyStatus || '';
    return STATUS_SORT_ORDER[status] ?? 99;
}

function compareAccountRows(a, b, field, direction) {
    const dir = direction === 'desc' ? -1 : 1;
    let cmp = 0;

    switch (field) {
        case 'name':
            cmp = (a.accountNameLower || '').localeCompare(b.accountNameLower || '', undefined, {
                sensitivity: 'base'
            });
            break;
        case 'class':
            cmp = classSortValue(a) - classSortValue(b);
            break;
        case 'reach':
            cmp = (a.reachPercent ?? -1) - (b.reachPercent ?? -1);
            break;
        case 'status':
            cmp = statusSortValue(a) - statusSortValue(b);
            break;
        default:
            cmp = 0;
    }

    if (cmp !== 0) {
        return cmp * dir;
    }

    return (a.accountNameLower || '').localeCompare(b.accountNameLower || '', undefined, {
        sensitivity: 'base'
    });
}

function sortAccountRows(rows, field, direction) {
    const sortField = SORTABLE_ACCOUNT_FIELDS.includes(field) ? field : 'name';
    const sortDirection = direction === 'desc' ? 'desc' : 'asc';
    return [...(rows || [])].sort((a, b) => compareAccountRows(a, b, sortField, sortDirection));
}

function matchesAccountSearch(row, rawTerm) {
    const tokens = tokenizeSearch(rawTerm);
    if (!tokens.length) {
        return true;
    }
    return tokens.every((token) => {
        if (row.searchText.includes(token)) {
            return true;
        }
        if (row.accountNameLower?.startsWith(token)) {
            return true;
        }
        if (token === 'lcf' && row.frequencyStatus === 'LCF') {
            return true;
        }
        if (token === 'rcf' && row.frequencyStatus === 'RCF') {
            return true;
        }
        if (token === 'mcf' && row.frequencyStatus === 'MCF') {
            return true;
        }
        if (token === 'visited' && row.isVisited) {
            return true;
        }
        if (token === 'unvisited' && !row.isVisited) {
            return true;
        }
        return false;
    });
}

export default class FieldRepHomeMetrics extends LightningElement {
    @track metrics = { ...EMPTY_METRICS };
    @track gamification = { ...EMPTY_GAMIFICATION };
    @track rankings = { ...EMPTY_RANKINGS };
    @track leaderboardScope = 'bu';
    @track displayAccountRows = [];
    @track selectedFilter = 'All';
    @track searchTerm = '';
    @track currentPage = 1;
    @track sortField = 'name';
    @track sortDirection = 'asc';
    @track isSearching = false;
    @track syncStatus = 'idle';
    @track errorMessage = '';

    allAccountRows = [];
    classFilteredRows = [];
    filteredAccountRows = [];
    @track searchDraft = '';
    @track showBadgeModal = false;
    @track badgeModalTitle = '';
    @track badgeModalMessage = '';
    searchDebounceTimer;
    cacheUserKey = CACHE_USER_FALLBACK;
    hasCachedData = false;

    get byClassification() {
        return this.metrics?.byClassification || [];
    }

    get filterChips() {
        return FILTER_VALUES.map((value) => ({
            value,
            label: value === 'All' ? 'All' : value,
            isActive: this.selectedFilter === value,
            chipClass: `filter-chip${this.selectedFilter === value ? ' filter-chip-active' : ''}`
        }));
    }

    get hasAccountRows() {
        return (this.displayAccountRows || []).length > 0;
    }

    get accountCountLabel() {
        const total = this.filteredAccountRows?.length || 0;
        if (total === 0) {
            return this.searchTerm ? 'No matches' : '0 accounts';
        }
        if (total === 1) {
            return '1 account';
        }
        if (this.searchTerm) {
            return `${total} matches`;
        }
        return `${total} accounts`;
    }

    get accountTableHeaders() {
        const columns = [
            { id: 'name', label: 'Account', sortable: true, sortField: 'name' },
            { id: 'class', label: 'Class', sortable: true, sortField: 'class' },
            { id: 'call-plan', label: 'Call plan', sortable: false },
            { id: 'reach', label: 'Reach', sortable: true, sortField: 'reach' },
            { id: 'status', label: 'Status', sortable: true, sortField: 'status' },
            { id: 'visited', label: 'Visited', sortable: false }
        ];

        return columns.map((column) => {
            if (!column.sortable) {
                return {
                    ...column,
                    headerClass: 'account-head-cell'
                };
            }

            const isActive = this.sortField === column.sortField;
            const indicator = isActive
                ? this.sortDirection === 'asc'
                    ? '↑'
                    : '↓'
                : '↕';

            return {
                ...column,
                headerClass: `account-head-cell sortable-header${isActive ? ' sortable-header-active' : ''}`,
                sortIndicator: indicator,
                ariaSort: isActive ? (this.sortDirection === 'asc' ? 'ascending' : 'descending') : 'none'
            };
        });
    }

    get rangeLabel() {
        const total = this.filteredAccountRows?.length || 0;
        if (total === 0) {
            return '';
        }
        const start = (this.currentPage - 1) * ACCOUNT_PAGE_SIZE + 1;
        const end = Math.min(this.currentPage * ACCOUNT_PAGE_SIZE, total);
        return `Showing ${start}–${end} of ${total}`;
    }

    get showPagination() {
        return (this.filteredAccountRows?.length || 0) > ACCOUNT_PAGE_SIZE;
    }

    get hasPreviousPage() {
        return this.currentPage > 1;
    }

    get hasNextPage() {
        return this.currentPage < this.totalPages;
    }

    get totalPages() {
        const total = this.filteredAccountRows?.length || 0;
        return Math.max(1, Math.ceil(total / ACCOUNT_PAGE_SIZE));
    }

    get pageLabel() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get isPrevDisabled() {
        return !this.hasPreviousPage;
    }

    get isNextDisabled() {
        return !this.hasNextPage;
    }

    get hasSearchTerm() {
        return Boolean((this.searchDraft || this.searchTerm || '').trim());
    }

    get showStreakBanner() {
        return (this.gamification?.streaks?.activityStreak || 0) > 0
            || (this.gamification?.streaks?.coverageStreak || 0) > 0;
    }

    get activityStreakLabel() {
        const days = this.gamification?.streaks?.activityStreak || 0;
        if (days <= 0) {
            return '';
        }
        return `🔥 ${days}-day activity streak`;
    }

    get coverageStreakLabel() {
        const days = this.gamification?.streaks?.coverageStreak || 0;
        if (days <= 0) {
            return '';
        }
        return `📈 ${days}-day coverage streak`;
    }

    get showActivityStreak() {
        return (this.gamification?.streaks?.activityStreak || 0) > 0;
    }

    get showCoverageStreak() {
        return (this.gamification?.streaks?.coverageStreak || 0) > 0;
    }

    get achievementBadges() {
        const earnedById = new Map(
            (this.gamification?.badges || []).map((badge) => [badge.badgeId, badge])
        );
        return BADGE_DEFINITIONS.map((definition) => {
            const serverBadge = earnedById.get(definition.id) || {};
            const earned = Boolean(serverBadge.earned);
            const progress = Math.round(serverBadge.progressPercent || 0);
            return {
                ...definition,
                earned,
                progress,
                progressLabel: earned ? 'Earned' : `${progress}%`,
                chipClass: `achievement-badge${earned ? ' achievement-badge-earned' : ' achievement-badge-locked'}`,
                tooltip: earned ? `${definition.label} — earned!` : `${definition.hint} (${progress}% there)`
            };
        });
    }

    get earnedBadgeCount() {
        return (this.achievementBadges || []).filter((badge) => badge.earned).length;
    }

    get achievementSummary() {
        const earned = this.earnedBadgeCount;
        const total = BADGE_DEFINITIONS.length;
        return `${earned} of ${total} earned`;
    }

    get userFirstName() {
        const name = (this.gamification?.userFirstName || '').trim();
        return name || 'there';
    }

    get metricsReady() {
        return this.metrics?.visitCoveragePercentDisplay != null;
    }

    get showSyncChip() {
        return this.syncStatus === 'cached' || this.syncStatus === 'updating' || this.syncStatus === 'offline';
    }

    get syncChipLabel() {
        if (this.syncStatus === 'updating') {
            return 'Updating…';
        }
        if (this.syncStatus === 'offline') {
            return 'Offline';
        }
        if (this.syncStatus === 'cached') {
            return 'Cached';
        }
        return '';
    }

    get syncChipClass() {
        return `sync-chip sync-chip-${this.syncStatus}`;
    }

    get showErrorBanner() {
        return Boolean(this.errorMessage);
    }

    get kpiCards() {
        return [
            buildKpiCard(
                'visit',
                'Visit Coverage',
                'Actual vs target visits',
                this.metrics?.visitCoveragePercentDisplay
            ),
            buildKpiCard(
                'customer',
                'Customer Coverage',
                'Accounts visited this cycle',
                this.metrics?.customerCoveragePercentDisplay
            ),
            buildKpiCard(
                'rf',
                'Right Frequency',
                'RCF across all accounts',
                this.metrics?.rfPercentTotalDisplay
            )
        ];
    }

    get showRankings() {
        return (this.rankings?.buTotal || 0) > 0 || (this.rankings?.companyTotal || 0) > 0;
    }

    get buRankLabel() {
        const rank = this.rankings?.buRank;
        const total = this.rankings?.buTotal || 0;
        const bu = (this.rankings?.buName || 'your team').trim();
        if (!rank || total <= 0) {
            return '—';
        }
        return `#${rank} of ${total} in ${bu}`;
    }

    get companyRankLabel() {
        const rank = this.rankings?.companyRank;
        const total = this.rankings?.companyTotal || 0;
        if (!rank || total <= 0) {
            return '—';
        }
        return `#${rank} of ${total} reps`;
    }

    get myCoverageDisplay() {
        return Math.round(this.rankings?.myCoveragePercent || 0);
    }

    get showCatchUpCard() {
        return Boolean(this.rankings?.personAbove) && !this.rankings?.isFirstInBu;
    }

    get showFirstPlaceCard() {
        return Boolean(this.rankings?.isFirstInBu);
    }

    get catchUpMessage() {
        const above = this.rankings?.personAbove;
        if (!above) {
            return '';
        }
        const aboveCoverage = Math.round(above.coveragePercent || 0);
        const myCoverage = this.myCoverageDisplay;
        const gap = Math.max(0.1, Math.round((above.gapPercent || 0) * 10) / 10);
        return `${above.name} is #${above.rank} — ${aboveCoverage}% coverage. You're #${this.rankings.buRank} at ${myCoverage}%. ${gap}% to catch up!`;
    }

    get firstPlaceMessage() {
        const bu = (this.rankings?.buName || 'your team').trim();
        return `You're #1 in ${bu}! 🏆 Keep it up.`;
    }

    get leaderboardRows() {
        const source = this.leaderboardScope === 'company'
            ? (this.rankings?.top5Company || [])
            : (this.rankings?.top5InBu || []);
        return source.map((row) => ({
            ...row,
            coverageDisplay: `${Math.round(row.coveragePercent || 0)}%`,
            rowClass: `leaderboard-row${row.isCurrentUser ? ' leaderboard-row-you' : ''}`,
            showBadge: Boolean(row.badgeIcon),
            rankLabel: `#${row.rank}`
        }));
    }

    get leaderboardScopeLabel() {
        return this.leaderboardScope === 'company' ? 'Company-wide' : (this.rankings?.buName || 'Your BU');
    }

    get isBuScopeActive() {
        return this.leaderboardScope === 'bu';
    }

    get isCompanyScopeActive() {
        return this.leaderboardScope === 'company';
    }

    get buScopeChipClass() {
        return `scope-chip${this.isBuScopeActive ? ' scope-chip-active' : ''}`;
    }

    get companyScopeChipClass() {
        return `scope-chip${this.isCompanyScopeActive ? ' scope-chip-active' : ''}`;
    }

    connectedCallback() {
        this.init();
    }

    disconnectedCallback() {
        if (this.searchDebounceTimer) {
            clearTimeout(this.searchDebounceTimer);
        }
        if (this.refreshAbort) {
            this.refreshAbort.abort();
            this.refreshAbort = null;
        }
        if (this._onOnline) {
            window.removeEventListener('online', this._onOnline);
        }
        if (this._onOffline) {
            window.removeEventListener('offline', this._onOffline);
        }
    }

    bindConnectivityListeners() {
        if (this._connectivityBound || typeof window === 'undefined') {
            return;
        }
        this._connectivityBound = true;
        this._onOnline = () => {
            this.init();
        };
        this._onOffline = () => {
            if (this.refreshAbort) {
                this.refreshAbort.abort();
            }
            this.syncStatus = 'offline';
            if (!this.hasCachedData) {
                this.errorMessage = 'You are offline. Connect to load metrics.';
            }
        };
        window.addEventListener('online', this._onOnline);
        window.addEventListener('offline', this._onOffline);
    }

    async init() {
        this.bindConnectivityListeners();
        this.errorMessage = '';
        const cached = await this.readCache();
        if (cached) {
            this.applyCachedBundle(cached);
            this.hasCachedData = true;
            this.syncStatus = 'cached';
        } else {
            this.hasCachedData = false;
        }

        if (typeof navigator !== 'undefined' && navigator.onLine === false) {
            this.syncStatus = 'offline';
            if (!this.hasCachedData) {
                this.errorMessage = 'You are offline. Connect to load metrics.';
            }
            return;
        }

        this.syncStatus = 'updating';
        try {
            const payload = await this.fetchHomeDashboard();
            this.applyDashboardPayload(payload);
            this.cacheUserKey = payload?.userId || CACHE_USER_FALLBACK;
            await this.writeCache();
            this.hasCachedData = true;
            this.errorMessage = '';
            this.syncStatus = 'idle';
        } catch (error) {
            if (error?.name === 'AbortError') {
                return;
            }
            this.syncStatus = 'offline';
            if (!this.hasCachedData) {
                this.errorMessage = this.isConnectivityError(error)
                    ? 'You are offline. Connect to load metrics.'
                    : this.reduceError(error) || 'Unable to load rep metrics.';
            }
        }
    }

    async readCache() {
        const primary = await getHomeMetricsCache(getUserHomeMetricsKey(this.cacheUserKey));
        if (primary) {
            return primary;
        }
        if (this.cacheUserKey !== CACHE_USER_FALLBACK) {
            return getHomeMetricsCache(getUserHomeMetricsKey(CACHE_USER_FALLBACK));
        }
        return null;
    }

    async writeCache() {
        const bundle = {
            metrics: this.metrics,
            gamification: this.gamification,
            rankings: this.rankings,
            allAccountRows: this.allAccountRows
        };
        await putHomeMetrics(getUserHomeMetricsKey(this.cacheUserKey), bundle);
        if (this.cacheUserKey !== CACHE_USER_FALLBACK) {
            await putHomeMetrics(getUserHomeMetricsKey(CACHE_USER_FALLBACK), bundle);
        }
    }

    async fetchHomeDashboard() {
        const restBase = typeof globalThis !== 'undefined' ? globalThis.PLANNER_REST_BASE : '';
        if (restBase) {
            return this.fetchHomeDashboardRest(restBase);
        }
        // Lightning UI sessions cannot call Apex REST (401). Same payload via AuraEnabled.
        return getHomeDashboard({ contextUserId: null });
    }

    async fetchHomeDashboardRest(restBase) {
        const token = typeof globalThis !== 'undefined' ? globalThis.PLANNER_ACCESS_TOKEN : '';
        const headers = { Accept: 'application/json' };
        if (token) {
            headers.Authorization = `Bearer ${token}`;
        }
        const path = `${String(restBase).replace(/\/$/, '')}${HOME_DASHBOARD_PATH}`;
        if (this.refreshAbort) {
            this.refreshAbort.abort();
        }
        this.refreshAbort = typeof AbortController !== 'undefined' ? new AbortController() : null;
        const response = await fetch(path, {
            method: 'GET',
            credentials: token ? 'omit' : 'same-origin',
            headers,
            signal: this.refreshAbort ? this.refreshAbort.signal : undefined
        });
        if (!response.ok) {
            if (response.status >= 500) {
                const offlineError = new Error('Offline');
                offlineError.name = 'OfflineError';
                throw offlineError;
            }
            let detail = `HTTP ${response.status}`;
            try {
                const failed = await response.json();
                detail = failed?.message || detail;
            } catch (_parseError) {
                // Keep the HTTP status message when the body is not JSON.
            }
            throw new Error(detail);
        }
        return response.json();
    }

    isConnectivityError(error) {
        const name = error?.name || '';
        if (name === 'AbortError' || name === 'TypeError' || name === 'OfflineError') {
            return true;
        }
        const message = error?.message || '';
        return /offline|failed to fetch|networkerror|load failed/i.test(message);
    }

    applyDashboardPayload(payload) {
        const metrics = payload?.metrics || {};
        this.metrics = this.mapMetrics(metrics);
        this.gamification = payload?.gamification || { ...EMPTY_GAMIFICATION };
        this.rankings = payload?.rankings || { ...EMPTY_RANKINGS };
        this.allAccountRows = (payload?.accountCoverageRows || []).map((row) => this.enrichAccountRow(row));
        this.applyClassFilter();
    }

    mapMetrics(metrics) {
        const byClassification = (metrics.byClassification || []).map((row) => {
            const visitPct = Math.round(row.visitCoveragePercent || 0);
            const customerPct = Math.round(row.customerCoveragePercent || 0);
            const colors = CLASS_COLORS[row.classification] || {
                accent: '#706e6b',
                bg: 'rgba(112, 110, 107, 0.08)'
            };
            return {
                ...row,
                visitCoveragePercentDisplay: visitPct,
                customerCoveragePercentDisplay: customerPct,
                rfPercentDisplay: Math.round(row.rfPercent || 0),
                lfPercentDisplay: Math.round(row.lfPercent || 0),
                progressStyle: `width: ${visitPct}%`,
                tileStyle: `border-left: 4px solid ${colors.accent}; background: ${colors.bg}`
            };
        });

        return {
            ...metrics,
            byClassification,
            visitCoveragePercentDisplay: Math.round(metrics.visitCoveragePercent || 0),
            customerCoveragePercentDisplay: Math.round(metrics.customerCoveragePercent || 0),
            rfPercentTotalDisplay: Math.round(metrics.rfPercentTotal || 0),
            visitRingStroke: ringStroke(metrics.visitCoveragePercent),
            customerRingStroke: ringStroke(metrics.customerCoveragePercent),
            rfRingStroke: ringStroke(metrics.rfPercentTotal)
        };
    }

    applyCachedBundle(cached) {
        this.metrics = cached.metrics || { ...EMPTY_METRICS };
        this.gamification = cached.gamification || { ...EMPTY_GAMIFICATION };
        this.rankings = cached.rankings || { ...EMPTY_RANKINGS };
        this.allAccountRows = cached.allAccountRows || [];
        this.applyClassFilter();
    }

    enrichAccountRow(row) {
        const filterClass = normalizeClass(row.potentialityOnTarget || row.calculatedClassification);
        const actual = Math.round(row.actualVisits || 0);
        const target = Math.round(row.targetVisits || 0);
        const visitPct = target > 0 ? Math.min(100, Math.round((actual / target) * 100)) : 0;
        const status = row.frequencyStatus || '';

        let statusClass = 'status-neutral';
        if (status === 'LCF') {
            statusClass = 'status-lcf';
        } else if (status === 'RCF') {
            statusClass = 'status-rcf';
        } else if (status === 'MCF') {
            statusClass = 'status-mcf';
        }

        const accountNameLower = (row.accountName || '').toLowerCase();

        return {
            ...row,
            filterClass,
            accountNameLower,
            callPlanLabel: `${actual} / ${target}`,
            reachDisplay: row.reachPercent != null ? `${Math.round(row.reachPercent)}%` : '—',
            visitedLabel: row.isVisited ? 'Visited' : 'Not visited',
            visitedClass: row.isVisited ? 'visited-yes' : 'visited-no',
            statusClass,
            progressStyle: `width: ${visitPct}%`,
            gapDisplay: Math.round(row.visitGap || 0),
            searchText: [
                row.accountName,
                row.specialty,
                row.city,
                row.frequencyStatus,
                row.calculatedClassification,
                row.potential,
                row.penetration,
                row.isVisited ? 'visited' : 'not visited'
            ]
                .filter(Boolean)
                .join(' ')
                .toLowerCase()
        };
    }

    applyClassFilter() {
        const filter = this.selectedFilter || 'All';
        this.classFilteredRows =
            filter === 'All'
                ? this.allAccountRows
                : this.allAccountRows.filter((row) => row.filterClass === filter);
        this.currentPage = 1;
        this.applySearch();
    }

    applySearch() {
        const term = (this.searchDraft || '').trim();
        this.searchTerm = term.toLowerCase();
        this.filteredAccountRows = term
            ? this.classFilteredRows.filter((row) => matchesAccountSearch(row, term))
            : [...this.classFilteredRows];
        this.currentPage = 1;
        this.updatePage();
        this.isSearching = false;
    }

    scheduleSearch(event) {
        this.searchDraft = event?.target?.value || '';
        this.isSearching = true;
        clearTimeout(this.searchDebounceTimer);
        this.searchDebounceTimer = window.setTimeout(() => {
            this.applySearch();
        }, SEARCH_DEBOUNCE_MS);
    }

    commitSearch(event) {
        this.searchDraft = event?.target?.value || '';
        clearTimeout(this.searchDebounceTimer);
        this.applySearch();
    }

    clearSearch() {
        this.searchDraft = '';
        this.searchTerm = '';
        const input = this.template.querySelector('.account-search-input');
        if (input) {
            input.value = '';
            input.focus();
        }
        clearTimeout(this.searchDebounceTimer);
        this.applySearch();
    }

    updatePage() {
        const total = this.filteredAccountRows?.length || 0;
        const maxPage = Math.max(1, Math.ceil(total / ACCOUNT_PAGE_SIZE));
        if (this.currentPage > maxPage) {
            this.currentPage = maxPage;
        }

        const sortedRows = sortAccountRows(
            this.filteredAccountRows,
            this.sortField,
            this.sortDirection
        );
        const start = (this.currentPage - 1) * ACCOUNT_PAGE_SIZE;
        this.displayAccountRows = sortedRows.slice(start, start + ACCOUNT_PAGE_SIZE);
    }

    handleSort(event) {
        const field = event?.currentTarget?.dataset?.sortField;
        if (!field || !SORTABLE_ACCOUNT_FIELDS.includes(field)) {
            return;
        }

        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }

        this.currentPage = 1;
        this.updatePage();
    }

    handlePreviousPage() {
        if (!this.hasPreviousPage) {
            return;
        }
        this.currentPage -= 1;
        this.updatePage();
    }

    handleNextPage() {
        if (!this.hasNextPage) {
            return;
        }
        this.currentPage += 1;
        this.updatePage();
    }

    handleFilter(event) {
        const value = event?.currentTarget?.dataset?.value;
        if (!value || value === this.selectedFilter) {
            return;
        }
        this.selectedFilter = value;
        this.applyClassFilter();
    }

    handleLeaderboardScope(event) {
        const scope = event?.currentTarget?.dataset?.scope;
        if (!scope || scope === this.leaderboardScope) {
            return;
        }
        this.leaderboardScope = scope;
    }

    handleBadgeClick(event) {
        const badgeId = event?.currentTarget?.dataset?.badgeId;
        if (!badgeId) {
            return;
        }
        const badge = (this.achievementBadges || []).find((item) => item.id === badgeId);
        if (!badge) {
            return;
        }

        const firstName = this.userFirstName;
        this.badgeModalTitle = `${badge.icon} ${badge.label}`;
        if (badge.earned) {
            this.badgeModalMessage = `Hello ${firstName}, you have completed ${badge.earnDescription} and earned the ${badge.label} badge!`;
        } else {
            this.badgeModalMessage = `Hello ${firstName}, keep going! ${badge.progress}% toward ${badge.label} — ${badge.hint}`;
        }
        this.showBadgeModal = true;
    }

    handleCloseBadgeModal() {
        this.showBadgeModal = false;
        this.badgeModalTitle = '';
        this.badgeModalMessage = '';
    }

    handleOpenAccount(event) {
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }
        window.open(`/lightning/r/Account/${accountId}/view`, '_self');
    }

    reduceError(error) {
        if (!error) {
            return null;
        }
        if (typeof error === 'string') {
            return error;
        }
        return error?.message || null;
    }
}