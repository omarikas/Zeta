import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getAccountAffiliations from '@salesforce/apex/AccountAffiliationController.getAccountAffiliations';
import getAccountDetails from '@salesforce/apex/AccountAffiliationController.getAccountDetails';
import getRelationTypePicklistValues from '@salesforce/apex/AccountAffiliationController.getRelationTypePicklistValues';
import getRolePicklistValues from '@salesforce/apex/AccountAffiliationController.getRolePicklistValues';
import getStrengthPicklistValues from '@salesforce/apex/AccountAffiliationController.getStrengthPicklistValues';

const COLUMN_WIDTH = 280;
const ROW_HEIGHT = 72;
const NODE_WIDTH = 210;
const NODE_HEIGHT = 44;
const PADDING = 40;
const PAGE_SIZE = 25;
const LEVEL_PAGE_SIZE = 3;

const AFFILIATION_ICON_PATHS = {
    hcp: 'M12 12c2.2 0 4-1.8 4-4s-1.8-4-4-4-4 1.8-4 4 1.8 4 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z',
    hco: 'M12 7V3H2v18h20V7H12zm-2 12H6v-2h4v2zm0-4H6v-2h4v2zm0-4H6V9h4v2zm0-4H6V5h4v2zm6 12h-4v-2h4v2zm0-4h-4v-2h4v2zm0-4h-4V9h4v2zm0-4h-4V5h4v2zm8 12h-6v-2h2v-2h-2v-2h2v-2h-2V9h6v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z',
    pharmacy:
        'M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-8 14H7v-2h4v2zm0-4H7v-2h4v2zm0-4H7V7h4v2zm6 8h-4v-2h4v2zm0-4h-4v-2h4v2zm0-4h-4V7h4v2z'
};

const AFFILIATION_ICON_COLORS = {
    hcp: '#0176d3',
    hco: '#6a1b9a',
    pharmacy: '#2e844a'
};

const AFFILIATION_ICON_BACKGROUNDS = {
    hcp: '#e8f4fd',
    hco: '#f3e8fd',
    pharmacy: '#e8f5e9'
};

export default class AccountAffiliationNetwork extends NavigationMixin(LightningElement) {
    _recordId;
    _initialized = false;
    _loadToken = 0;

    @track isInitialLoading = false;
    @track isLoadingMore = false;
    @track initialLoadComplete = false;
    @track error;

    @track nodes = [];
    @track edges = [];
    @track treeLayoutNodes = [];
    @track treeLayoutEdges = [];

    @track totalCount = 0;
    @track nextOffset = 0;
    @track hasMore = false;
    @track pagingAccountId = null;

    expandedNodes = new Set();
    collapsedNodes = new Set();
    loadedAffiliationAccounts = new Set();
    levelVisibleLimits = new Map();
    selectedNodeId = null;
    @track selectedNode = null;

    svgWidth = 900;
    svgHeight = 500;
    clickHandlerAttached = false;

    @track filters = {
        relationType: 'All',
        showInactive: false,
        showOutsideTerritory: true,
        strength: 'All',
        role: 'All',
        direction: 'All',
        maxDepth: '3'
    };

    depthOptions = [
        { label: '1 level', value: '1' },
        { label: '2 levels', value: '2' },
        { label: '3 levels', value: '3' },
        { label: 'All levels', value: 'All' }
    ];

    @track relationTypeOptions = [{ label: 'All', value: 'All' }];
    @track roleOptions = [{ label: 'All', value: 'All' }];
    @track strengthOptions = [{ label: 'All', value: 'All' }];
    @track directionOptions = [
        { label: 'All', value: 'All' },
        { label: 'Primary → Related', value: 'Primary→Related' },
        { label: 'Related → Primary', value: 'Related→Primary' }
    ];

    @track currentAccount = null;
    formFactor = FORM_FACTOR;

    get isMobile() {
        return this.formFactor === 'Small';
    }

    get isLoading() {
        return this.isInitialLoading || this.isLoadingMore;
    }

    get showLoadMore() {
        return this.hasMore && !this.isLoading;
    }

    get loadMoreLabel() {
        const loaded = this.edges.length;
        const remaining = Math.max(this.totalCount - this.nextOffset, 0);
        return `Load more affiliations (${loaded} of ${this.totalCount}, ${remaining} remaining)`;
    }

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        const normalized = this.normalizeRecordId(value);
        if (!normalized || normalized === this._recordId) {
            return;
        }
        this._recordId = normalized;
        this.beginRecordLoad();
    }

    connectedCallback() {
        if (this._recordId && !this._initialized) {
            this.beginRecordLoad();
        }
    }

    normalizeRecordId(value) {
        return value ? String(value) : null;
    }

    beginRecordLoad() {
        this._initialized = true;
        this.resetGraphState();
        this.expandedNodes.add(this._recordId);
        this.pagingAccountId = this._recordId;
        this.nextOffset = 0;
        this.loadAccountDetails();
        this.fetchAffiliationPage({ reset: true });
    }

    resetGraphState() {
        this._loadToken += 1;
        this.isInitialLoading = false;
        this.isLoadingMore = false;
        this.initialLoadComplete = false;
        this.expandedNodes.clear();
        this.collapsedNodes.clear();
        this.loadedAffiliationAccounts.clear();
        this.levelVisibleLimits.clear();
        this.selectedNodeId = null;
        this.selectedNode = null;
        this.nodes = [];
        this.edges = [];
        this.treeLayoutNodes = [];
        this.treeLayoutEdges = [];
        this.totalCount = 0;
        this.nextOffset = 0;
        this.hasMore = false;
        this.pagingAccountId = null;
        this.clickHandlerAttached = false;
        this.error = undefined;
    }

    buildFiltersJson(accountIds) {
        return JSON.stringify({
            relationType: this.filters.relationType,
            showInactive: this.filters.showInactive,
            showOutsideTerritory: this.filters.showOutsideTerritory,
            direction: this.filters.direction,
            role: this.filters.role,
            strength: this.filters.strength,
            accountIds: accountIds
        });
    }

    getMaxDepthLimit() {
        if (this.filters.maxDepth === 'All') {
            return null;
        }
        const parsed = parseInt(this.filters.maxDepth, 10);
        return Number.isNaN(parsed) ? 3 : parsed;
    }

    buildAdjacencyMap() {
        const adjacency = new Map();
        const addNeighbor = (fromId, toId) => {
            if (!adjacency.has(fromId)) {
                adjacency.set(fromId, new Set());
            }
            adjacency.get(fromId).add(toId);
        };
        this.edges.forEach((edge) => {
            addNeighbor(edge.from, edge.to);
            addNeighbor(edge.to, edge.from);
        });
        return adjacency;
    }

    buildTreeHierarchy(rootId) {
        const adjacency = this.buildAdjacencyMap();
        const maxDepth = this.getMaxDepthLimit();
        const parentMap = new Map();
        const levels = [];
        const visited = new Set([rootId]);
        let currentLevel = [rootId];
        let depth = 0;

        while (currentLevel.length > 0) {
            levels.push([...currentLevel]);
            if (maxDepth !== null && depth >= maxDepth - 1) {
                break;
            }

            const nextLevel = [];
            currentLevel.forEach((nodeId) => {
                if (this.collapsedNodes.has(nodeId)) {
                    return;
                }
                const neighbors = adjacency.get(nodeId) || new Set();
                neighbors.forEach((neighborId) => {
                    if (!visited.has(neighborId)) {
                        visited.add(neighborId);
                        parentMap.set(neighborId, nodeId);
                        nextLevel.push(neighborId);
                    }
                });
            });
            currentLevel = nextLevel;
            depth++;
        }

        return { levels, parentMap, visibleIds: visited, adjacency };
    }

    getLevelLimit(depth) {
        if (depth === 0) {
            return 1;
        }
        return this.levelVisibleLimits.get(depth) ?? LEVEL_PAGE_SIZE;
    }

    applyLevelCaps(levels, parentMap) {
        const cappedLevels = [];
        const visibleIds = new Set();
        const moreNodes = [];

        levels.forEach((levelNodeIds, depth) => {
            if (depth === 0) {
                cappedLevels.push([...levelNodeIds]);
                levelNodeIds.forEach((id) => visibleIds.add(id));
                return;
            }

            const eligible = levelNodeIds.filter((nodeId) => {
                const parentId = parentMap.get(nodeId);
                return parentId && visibleIds.has(parentId);
            });

            const limit = this.getLevelLimit(depth);
            const shown = eligible.slice(0, limit);
            const hiddenCount = eligible.length - shown.length;

            shown.forEach((id) => visibleIds.add(id));
            cappedLevels.push(shown);

            if (hiddenCount > 0) {
                moreNodes.push({
                    id: `more-level-${depth}`,
                    depth,
                    hiddenCount,
                    rowIndex: shown.length
                });
            }
        });

        return { cappedLevels, visibleIds, moreNodes };
    }

    expandLevel(depth) {
        const parsedDepth = parseInt(depth, 10);
        if (Number.isNaN(parsedDepth) || parsedDepth < 1) {
            return;
        }
        const current = this.getLevelLimit(parsedDepth);
        this.levelVisibleLimits.set(parsedDepth, current + LEVEL_PAGE_SIZE);
        this.refreshVisualization();
        this.loadAffiliationsForVisibleNodesAtDepth(parsedDepth);
    }

    loadAffiliationsForVisibleNodesAtDepth(depth) {
        const { levels, parentMap } = this.buildTreeHierarchy(this._recordId);
        const { cappedLevels } = this.applyLevelCaps(levels, parentMap);
        const levelNodes = cappedLevels[depth] || [];
        const unloaded = levelNodes.filter((nodeId) => !this.loadedAffiliationAccounts.has(nodeId));
        if (unloaded.length > 0) {
            this.fetchAffiliationChain(unloaded, 0);
        }
    }

    nodeHasHiddenNeighbors(nodeId, visibleIds, adjacency) {
        const neighbors = adjacency.get(nodeId) || new Set();
        for (const neighborId of neighbors) {
            if (!visibleIds.has(neighborId)) {
                return true;
            }
        }
        return false;
    }

    autoFetchNeighborsForDepth() {
        const depthLimit = this.getMaxDepthLimit();
        if (!depthLimit || depthLimit < 2 || this.isLoading) {
            return;
        }

        const { levels, adjacency } = this.buildTreeHierarchy(this._recordId);
        const targets = new Set();
        levels.slice(1, depthLimit).forEach((levelNodes) => {
            levelNodes.forEach((nodeId) => targets.add(nodeId));
        });

        const unloaded = [...targets].filter((nodeId) => !this.loadedAffiliationAccounts.has(nodeId));
        if (unloaded.length > 0) {
            this.fetchAffiliationChain(unloaded, 0);
        }
    }

    fetchAffiliationChain(accountIds, index) {
        if (index >= accountIds.length || this.isLoading) {
            return;
        }
        const accountId = accountIds[index];
        if (this.loadedAffiliationAccounts.has(accountId)) {
            this.fetchAffiliationChain(accountIds, index + 1);
            return;
        }

        this.pagingAccountId = accountId;
        this.nextOffset = 0;
        this.fetchAffiliationPage({
            reset: false,
            accountId,
            offset: 0,
            onComplete: () => this.fetchAffiliationChain(accountIds, index + 1)
        });
    }

    fetchAffiliationPage({ reset = false, accountId = null, offset = null, onComplete = null } = {}) {
        const targetAccountId = accountId || this.pagingAccountId || this._recordId;
        if (!targetAccountId) {
            if (onComplete) {
                onComplete();
            }
            return;
        }

        const requestOffset = offset != null ? offset : (reset ? 0 : this.nextOffset);
        const loadToken = this._loadToken;
        const isFirstPage = reset || requestOffset === 0;

        if (isFirstPage && reset) {
            this.isInitialLoading = true;
            this.isLoadingMore = false;
        } else {
            this.isLoadingMore = true;
        }

        getAccountAffiliations({
            accountId: this._recordId,
            filtersJson: this.buildFiltersJson([targetAccountId]),
            offset: requestOffset,
            pageSize: PAGE_SIZE
        })
            .then((result) => {
                if (loadToken !== this._loadToken) {
                    return;
                }
                this.applyGraphPage(result, { reset: isFirstPage && reset });
                this.pagingAccountId = targetAccountId;
                this.nextOffset = (result?.offset || 0) + (result?.recordsReturned || 0);
                this.totalCount = result?.totalCount || 0;
                this.hasMore = result?.hasMore === true;
                this.initialLoadComplete = true;
                if (isFirstPage) {
                    this.loadedAffiliationAccounts.add(targetAccountId);
                }
                this.refreshVisualization();
                if (isFirstPage && reset) {
                    this.autoFetchNeighborsForDepth();
                }
            })
            .catch((err) => {
                if (loadToken !== this._loadToken) {
                    return;
                }
                const errorMessage = err.body?.message || err.message || JSON.stringify(err);
                this.showError('Error loading affiliations: ' + errorMessage);
            })
            .finally(() => {
                if (loadToken !== this._loadToken) {
                    return;
                }
                this.isInitialLoading = false;
                this.isLoadingMore = false;
                if (onComplete) {
                    onComplete();
                }
            });
    }

    applyGraphPage(graphData, { reset }) {
        if (!graphData) {
            if (reset) {
                this.nodes = [];
                this.edges = [];
            }
            return;
        }

        const nodeMap = reset
            ? new Map()
            : new Map(this.nodes.map((node) => [node.id, node]));
        const edgeMap = reset
            ? new Map()
            : new Map(this.edges.map((edge) => [edge.id, edge]));

        (graphData.nodes || []).forEach((node) => {
            if (!nodeMap.has(node.id)) {
                const iconType = this.resolveIconType(node.accountType);
                nodeMap.set(node.id, {
                    id: node.id,
                    label: node.label,
                    accountType: node.accountType,
                    isActive: node.isActive,
                    hasMoreAffiliations: node.hasMoreAffiliations === true,
                    iconType,
                    iconName: this.getSldsIconName(iconType)
                });
            }
        });

        (graphData.edges || []).forEach((edge) => {
            const edgeKey = `${edge.fromId}-${edge.toId}-${edge.affiliationId || edge.relationType}`;
            if (!edgeMap.has(edgeKey)) {
                edgeMap.set(edgeKey, {
                    id: edgeKey,
                    from: edge.fromId,
                    to: edge.toId,
                    label: edge.relationType || '',
                    description: edge.description || ''
                });
            }
        });

        this.nodes = Array.from(nodeMap.values());
        this.edges = Array.from(edgeMap.values());
    }

    refreshVisualization() {
        if (this.isMobile || this.nodes.length === 0) {
            this.treeLayoutNodes = [];
            this.treeLayoutEdges = [];
            return;
        }
        this.computeTreeLayout();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this.renderTreeSVG());
    }

    @wire(getRelationTypePicklistValues)
    wiredRelationTypes({ error, data }) {
        if (data) {
            this.relationTypeOptions = [{ label: 'All', value: 'All' }, ...data.map((item) => ({
                label: item.label,
                value: item.value
            }))];
        } else if (error) {
            console.error('Error loading relation types:', error);
        }
    }

    @wire(getRolePicklistValues)
    wiredRoles({ error, data }) {
        if (data) {
            this.roleOptions = [{ label: 'All', value: 'All' }, ...data.map((item) => ({
                label: item.label,
                value: item.value
            }))];
        } else if (error) {
            console.error('Error loading roles:', error);
        }
    }

    @wire(getStrengthPicklistValues)
    wiredStrengths({ error, data }) {
        if (data) {
            this.strengthOptions = [{ label: 'All', value: 'All' }, ...data.map((item) => ({
                label: item.label,
                value: item.value
            }))];
        } else if (error) {
            console.error('Error loading strengths:', error);
        }
    }

    loadAccountDetails() {
        if (!this._recordId) {
            return;
        }

        getAccountDetails({ accountId: this._recordId })
            .then((result) => {
                this.currentAccount = result;
            })
            .catch((err) => {
                console.error('Error loading account details:', err);
            });
    }

    resolveIconType(accountType) {
        const type = (accountType || '').toLowerCase();
        if (type.includes('pharm')) {
            return 'pharmacy';
        }
        if (
            type.includes('person') ||
            type.includes('hcp') ||
            type.includes('medical professional') ||
            type.includes('physician') ||
            type.includes('healthcare provider')
        ) {
            return 'hcp';
        }
        if (
            type.includes('institution') ||
            type.includes('hospital') ||
            type.includes('hco') ||
            type.includes('clinic') ||
            type.includes('practice') ||
            type.includes('university')
        ) {
            return 'hco';
        }
        return 'hco';
    }

    getSldsIconName(iconType) {
        switch (iconType) {
            case 'hcp':
                return 'standard:contact';
            case 'pharmacy':
                return 'standard:location';
            case 'hco':
            default:
                return 'standard:account';
        }
    }

    appendNodeIcon(group, node) {
        const iconType = node.iconType || this.resolveIconType(node.accountType);
        const isHighlighted = node.isSelected || node.isOnPath;
        const baseColor = AFFILIATION_ICON_COLORS[iconType] || AFFILIATION_ICON_COLORS.hco;
        const iconFill = isHighlighted ? '#ffffff' : baseColor;
        const iconX = node.x + 9;
        const iconY = node.y + 10;
        const size = 24;

        const badge = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        badge.setAttribute('cx', iconX + size / 2);
        badge.setAttribute('cy', iconY + size / 2);
        badge.setAttribute('r', size / 2);
        badge.setAttribute(
            'fill',
            isHighlighted ? 'rgba(255,255,255,0.22)' : AFFILIATION_ICON_BACKGROUNDS[iconType] || AFFILIATION_ICON_BACKGROUNDS.hco
        );
        group.appendChild(badge);

        const iconSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        iconSvg.setAttribute('x', iconX + 3);
        iconSvg.setAttribute('y', iconY + 3);
        iconSvg.setAttribute('width', size - 6);
        iconSvg.setAttribute('height', size - 6);
        iconSvg.setAttribute('viewBox', '0 0 24 24');
        iconSvg.setAttribute('aria-hidden', 'true');

        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('d', AFFILIATION_ICON_PATHS[iconType] || AFFILIATION_ICON_PATHS.hco);
        path.setAttribute('fill', iconFill);
        iconSvg.appendChild(path);
        group.appendChild(iconSvg);
    }

    computeTreeLayout() {
        if (!this._recordId || this.nodes.length === 0) {
            this.treeLayoutNodes = [];
            this.treeLayoutEdges = [];
            return;
        }

        const nodeMap = new Map(this.nodes.map((n) => [n.id, n]));
        const { levels, parentMap, adjacency } = this.buildTreeHierarchy(this._recordId);
        const { cappedLevels, visibleIds, moreNodes } = this.applyLevelCaps(levels, parentMap);
        const pathIds = this.buildSelectedPath(parentMap);

        const layoutNodes = [];
        let maxDepth = 0;
        let maxRows = 0;

        cappedLevels.forEach((levelNodeIds, depth) => {
            maxDepth = Math.max(maxDepth, depth);
            const levelMore = moreNodes.find((m) => m.depth === depth);
            maxRows = Math.max(maxRows, levelNodeIds.length + (levelMore ? 1 : 0));

            levelNodeIds.forEach((nodeId, rowIndex) => {
                const node = nodeMap.get(nodeId);
                if (!node) {
                    return;
                }

                const neighbors = adjacency.get(nodeId) || new Set();
                const hasNeighbors = neighbors.size > 0;
                const isCollapsed = this.collapsedNodes.has(nodeId);
                const hasHiddenNeighbors = this.nodeHasHiddenNeighbors(nodeId, visibleIds, adjacency);
                const needsAffiliationLoad = !this.loadedAffiliationAccounts.has(nodeId);
                const hasVisibleChildren = [...neighbors].some(
                    (neighborId) => visibleIds.has(neighborId) && parentMap.get(neighborId) === nodeId
                );

                layoutNodes.push({
                    ...node,
                    iconType: node.iconType || this.resolveIconType(node.accountType),
                    x: PADDING + depth * COLUMN_WIDTH,
                    y: PADDING + rowIndex * ROW_HEIGHT,
                    depth,
                    isRoot: nodeId === this._recordId,
                    isSelected: nodeId === this.selectedNodeId,
                    isOnPath: pathIds.has(nodeId),
                    hasChildren: hasNeighbors,
                    hasVisibleChildren,
                    hasHiddenNeighbors,
                    needsAffiliationLoad,
                    isCollapsed,
                    showCollapseToggle: hasNeighbors && (hasVisibleChildren || hasHiddenNeighbors),
                    showLoadToggle: needsAffiliationLoad && nodeId !== this._recordId,
                    fill: this.getNodeFill(node, nodeId === this.selectedNodeId, pathIds.has(nodeId)),
                    stroke: this.getNodeStroke(node, nodeId === this.selectedNodeId, pathIds.has(nodeId))
                });
            });
        });

        moreNodes.forEach((more) => {
            layoutNodes.push({
                id: more.id,
                isMoreNode: true,
                depth: more.depth,
                hiddenCount: more.hiddenCount,
                x: PADDING + more.depth * COLUMN_WIDTH,
                y: PADDING + more.rowIndex * ROW_HEIGHT,
                label: `+${more.hiddenCount} more`
            });
        });

        this.svgWidth = Math.max(PADDING * 2 + (maxDepth + 1) * COLUMN_WIDTH, 800);
        this.svgHeight = Math.max(PADDING * 2 + maxRows * ROW_HEIGHT, 400);

        const positionedMap = new Map(layoutNodes.map((n) => [n.id, n]));
        const layoutEdges = [];

        visibleIds.forEach((nodeId) => {
            if (nodeId === this._recordId) {
                return;
            }
            const parentId = parentMap.get(nodeId);
            if (!parentId || !visibleIds.has(parentId)) {
                return;
            }
            const fromNode = positionedMap.get(parentId);
            const toNode = positionedMap.get(nodeId);
            if (!fromNode || !toNode) {
                return;
            }
            const fromX = fromNode.x + NODE_WIDTH;
            const fromY = fromNode.y + NODE_HEIGHT / 2;
            const toX = toNode.x;
            const toY = toNode.y + NODE_HEIGHT / 2;
            const midX = (fromX + toX) / 2;
            layoutEdges.push({
                id: `${parentId}-${nodeId}`,
                path: `M ${fromX} ${fromY} C ${midX} ${fromY}, ${midX} ${toY}, ${toX} ${toY}`,
                isOnPath: pathIds.has(parentId) && pathIds.has(nodeId),
                fromId: parentId,
                toId: nodeId
            });
        });

        this.treeLayoutNodes = layoutNodes;
        this.treeLayoutEdges = layoutEdges;
    }

    buildSelectedPath(parentMap) {
        const pathIds = new Set();
        if (!this.selectedNodeId) {
            return pathIds;
        }
        let currentId = this.selectedNodeId;
        while (currentId) {
            pathIds.add(currentId);
            currentId = parentMap.get(currentId);
        }
        return pathIds;
    }

    getNodeFill(node, isSelected, isOnPath) {
        if (!node.isActive) {
            return '#e5e5e5';
        }
        if (isSelected || isOnPath) {
            return '#0176d3';
        }
        return '#e3f3ff';
    }

    getNodeStroke(node, isSelected, isOnPath) {
        if (!node.isActive) {
            return '#969696';
        }
        if (isSelected || isOnPath) {
            return '#014486';
        }
        return '#0176d3';
    }

    renderTreeSVG() {
        const svgElement = this.template.querySelector('.network-svg');
        if (!svgElement || this.treeLayoutNodes.length === 0) {
            return;
        }

        svgElement.setAttribute('width', this.svgWidth);
        svgElement.setAttribute('height', this.svgHeight);
        svgElement.setAttribute('viewBox', `0 0 ${this.svgWidth} ${this.svgHeight}`);
        svgElement.innerHTML = '';

        this.treeLayoutEdges.forEach((edge) => {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('d', edge.path);
            path.setAttribute('fill', 'none');
            path.setAttribute('stroke', edge.isOnPath ? '#0176d3' : '#b0adab');
            path.setAttribute('stroke-width', edge.isOnPath ? '2.5' : '1.5');
            path.classList.add('tree-edge');
            svgElement.appendChild(path);
        });

        this.treeLayoutNodes.forEach((node) => {
            if (node.isMoreNode) {
                this.appendMoreNode(svgElement, node);
                return;
            }

            const group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            group.classList.add('tree-node');
            group.setAttribute('data-node-id', node.id);

            const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
            rect.setAttribute('x', node.x);
            rect.setAttribute('y', node.y);
            rect.setAttribute('width', NODE_WIDTH);
            rect.setAttribute('height', NODE_HEIGHT);
            rect.setAttribute('rx', '6');
            rect.setAttribute('fill', node.fill);
            rect.setAttribute('stroke', node.stroke);
            rect.setAttribute('stroke-width', node.isSelected ? '2.5' : '1.5');
            rect.setAttribute('data-node-id', node.id);
            rect.setAttribute('data-action', 'select');
            group.appendChild(rect);

            this.appendNodeIcon(group, node);

            if (node.showCollapseToggle) {
                const toggleBg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                toggleBg.setAttribute('cx', node.x - 12);
                toggleBg.setAttribute('cy', node.y + NODE_HEIGHT / 2);
                toggleBg.setAttribute('r', '9');
                toggleBg.setAttribute('fill', '#ffffff');
                toggleBg.setAttribute('stroke', '#706e6b');
                toggleBg.setAttribute('data-node-id', node.id);
                toggleBg.setAttribute('data-action', 'toggle-collapse');
                toggleBg.classList.add('node-toggle');
                group.appendChild(toggleBg);

                const toggleText = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                toggleText.setAttribute('x', node.x - 12);
                toggleText.setAttribute('y', node.y + NODE_HEIGHT / 2 + 4);
                toggleText.setAttribute('text-anchor', 'middle');
                toggleText.setAttribute('font-size', '11');
                toggleText.setAttribute('font-weight', 'bold');
                toggleText.setAttribute('fill', '#706e6b');
                toggleText.setAttribute('data-node-id', node.id);
                toggleText.setAttribute('data-action', 'toggle-collapse');
                toggleText.textContent = node.isCollapsed ? '▶' : '▼';
                toggleText.classList.add('node-toggle');
                group.appendChild(toggleText);
            }

            if (node.showLoadToggle) {
                const loadBg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                loadBg.setAttribute('cx', node.x + NODE_WIDTH + 12);
                loadBg.setAttribute('cy', node.y + NODE_HEIGHT / 2);
                loadBg.setAttribute('r', '9');
                loadBg.setAttribute('fill', '#0176d3');
                loadBg.setAttribute('stroke', '#014486');
                loadBg.setAttribute('data-node-id', node.id);
                loadBg.setAttribute('data-action', 'load-affiliations');
                loadBg.classList.add('node-toggle');
                group.appendChild(loadBg);

                const loadText = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                loadText.setAttribute('x', node.x + NODE_WIDTH + 12);
                loadText.setAttribute('y', node.y + NODE_HEIGHT / 2 + 4);
                loadText.setAttribute('text-anchor', 'middle');
                loadText.setAttribute('font-size', '12');
                loadText.setAttribute('font-weight', 'bold');
                loadText.setAttribute('fill', '#ffffff');
                loadText.setAttribute('data-node-id', node.id);
                loadText.setAttribute('data-action', 'load-affiliations');
                loadText.textContent = '+';
                loadText.classList.add('node-toggle');
                group.appendChild(loadText);
            }

            const label = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            label.setAttribute('x', node.x + 36);
            label.setAttribute('y', node.y + 26);
            label.setAttribute('fill', node.isSelected || node.isOnPath ? '#ffffff' : '#181818');
            label.setAttribute('font-size', '12');
            label.setAttribute('data-node-id', node.id);
            label.setAttribute('data-action', 'select');
            label.textContent = this.truncateLabel(node.label);
            group.appendChild(label);

            svgElement.appendChild(group);
        });

        if (!this.clickHandlerAttached) {
            svgElement.addEventListener('click', (event) => this.handleSvgClick(event));
            this.clickHandlerAttached = true;
        }
    }

    appendMoreNode(svgElement, node) {
        const group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
        group.classList.add('level-more-node');
        group.setAttribute('data-action', 'expand-level');
        group.setAttribute('data-level-depth', String(node.depth));

        const title = document.createElementNS('http://www.w3.org/2000/svg', 'title');
        title.textContent = `Show ${node.hiddenCount} more at level ${node.depth + 1}`;
        group.appendChild(title);

        const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        rect.setAttribute('x', node.x);
        rect.setAttribute('y', node.y);
        rect.setAttribute('width', NODE_WIDTH);
        rect.setAttribute('height', NODE_HEIGHT);
        rect.setAttribute('rx', '6');
        rect.setAttribute('fill', '#f3f2f2');
        rect.setAttribute('stroke', '#706e6b');
        rect.setAttribute('stroke-width', '1.5');
        rect.setAttribute('stroke-dasharray', '5 3');
        rect.setAttribute('data-action', 'expand-level');
        rect.setAttribute('data-level-depth', String(node.depth));
        group.appendChild(rect);

        const dots = document.createElementNS('http://www.w3.org/2000/svg', 'text');
        dots.setAttribute('x', node.x + NODE_WIDTH / 2);
        dots.setAttribute('y', node.y + 22);
        dots.setAttribute('text-anchor', 'middle');
        dots.setAttribute('font-size', '18');
        dots.setAttribute('font-weight', 'bold');
        dots.setAttribute('fill', '#706e6b');
        dots.setAttribute('data-action', 'expand-level');
        dots.setAttribute('data-level-depth', String(node.depth));
        dots.textContent = '⋯';
        group.appendChild(dots);

        const sublabel = document.createElementNS('http://www.w3.org/2000/svg', 'text');
        sublabel.setAttribute('x', node.x + NODE_WIDTH / 2);
        sublabel.setAttribute('y', node.y + 38);
        sublabel.setAttribute('text-anchor', 'middle');
        sublabel.setAttribute('font-size', '10');
        sublabel.setAttribute('fill', '#0176d3');
        sublabel.setAttribute('data-action', 'expand-level');
        sublabel.setAttribute('data-level-depth', String(node.depth));
        sublabel.textContent = node.label;
        group.appendChild(sublabel);

        svgElement.appendChild(group);
    }

    truncateLabel(label) {
        if (!label) {
            return 'Account';
        }
        return label.length > 22 ? `${label.substring(0, 20)}…` : label;
    }

    handleSvgClick(event) {
        const action = event.target.getAttribute('data-action');
        const nodeId = event.target.getAttribute('data-node-id');

        if (action === 'toggle-collapse' && nodeId) {
            event.preventDefault();
            this.toggleCollapse(nodeId);
            return;
        }

        if (action === 'load-affiliations' && nodeId) {
            event.preventDefault();
            this.handleNodeExpand(nodeId);
            return;
        }

        if (action === 'expand-level') {
            event.preventDefault();
            const depth = event.target.getAttribute('data-level-depth');
            this.expandLevel(depth);
            return;
        }

        if (!nodeId) {
            return;
        }

        event.preventDefault();

        if (this.selectedNodeId === nodeId) {
            this.navigateToAccount(nodeId);
            return;
        }

        this.setSelectedNode(nodeId);
        this.refreshVisualization();
    }

    setSelectedNode(nodeId) {
        this.selectedNodeId = nodeId;
        this.selectedNode = this.nodes.find((node) => node.id === nodeId) || null;
    }

    toggleCollapse(nodeId) {
        if (this.collapsedNodes.has(nodeId)) {
            this.collapsedNodes.delete(nodeId);
        } else {
            this.collapsedNodes.add(nodeId);
        }
        this.refreshVisualization();
    }

    handleNodeExpand(nodeId) {
        if (this.isLoading) {
            return;
        }
        this.expandedNodes.add(nodeId);
        this.pagingAccountId = nodeId;
        this.nextOffset = 0;
        this.fetchAffiliationPage({ reset: false, accountId: nodeId, offset: 0 });
    }

    handleNodeClick(event) {
        event.preventDefault();
        const nodeId = event.currentTarget.dataset.nodeId;
        if (nodeId) {
            this.setSelectedNode(nodeId);
            this.handleNodeExpand(nodeId);
        }
    }

    handleViewSelectedAccount() {
        if (this.selectedNodeId) {
            this.navigateToAccount(this.selectedNodeId);
        }
    }

    handleNodeNavigate(event) {
        event.preventDefault();
        const nodeId = event.currentTarget.dataset.nodeId;
        if (nodeId) {
            this.navigateToAccount(nodeId);
        }
    }

    handleLoadMore() {
        if (!this.hasMore || this.isLoading) {
            return;
        }
        this.fetchAffiliationPage({
            reset: false,
            accountId: this.pagingAccountId || this._recordId,
            offset: this.nextOffset
        });
    }

    navigateToAccount(accountId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        let value;
        if (event.target.type === 'toggle') {
            value = event.target.checked;
        } else {
            value = event.detail?.value ?? event.target.value;
        }

        this.filters = { ...this.filters, [field]: value };

        if (field === 'maxDepth') {
            this.refreshVisualization();
            this.autoFetchNeighborsForDepth();
            return;
        }

        this.pagingAccountId = this._recordId;
        this.nextOffset = 0;
        this.nodes = [];
        this.edges = [];
        this.collapsedNodes.clear();
        this.loadedAffiliationAccounts.clear();
        this.levelVisibleLimits.clear();
        this.expandedNodes.clear();
        this.expandedNodes.add(this._recordId);
        this.selectedNodeId = null;
        this.fetchAffiliationPage({ reset: true });
    }

    showError(message) {
        this.error = message;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
    }

    toggleFilterPanel() {
        const panel = this.template.querySelector('.filter-panel');
        if (panel) {
            panel.classList.toggle('collapsed');
        }
    }

    handleRefresh() {
        this.beginRecordLoad();
    }

    get hasData() {
        return this.nodes.length > 0;
    }

    get hasSelectedNode() {
        return !!this.selectedNode;
    }

    get selectedNodeLabel() {
        return this.selectedNode ? this.selectedNode.label : '';
    }

    get selectedNodeIcon() {
        return this.selectedNode ? this.selectedNode.iconName : 'standard:account';
    }

    get hasEdges() {
        return this.edges.length > 0;
    }

    get nodeCount() {
        return this.nodes.length;
    }

    get edgeCount() {
        return this.edges.length;
    }

    get showTreeView() {
        return !this.isMobile && this.treeLayoutNodes.length > 0;
    }

    get edgesWithLabels() {
        return this.edges.map((edge) => ({
            ...edge,
            fromLabel: this.getNodeLabel(edge.from),
            toLabel: this.getNodeLabel(edge.to)
        }));
    }

    getNodeLabel(nodeId) {
        const node = this.nodes.find((n) => n.id === nodeId);
        return node ? node.label : nodeId;
    }
}