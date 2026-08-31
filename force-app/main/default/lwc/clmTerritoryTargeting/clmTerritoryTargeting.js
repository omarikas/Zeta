import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTerritories from '@salesforce/apex/ClmAdminController.getTerritories';
import getTerritoryProductAlignments from '@salesforce/apex/ClmAdminController.getTerritoryProductAlignments';

const ROOT_KEY = 'territory-alignment-root';

function buildTerritoryTree(flatNodes) {
    const byId = new Map();
    const roots = [];

    (flatNodes || []).forEach((node) => {
        byId.set(node.id, {
            id: node.id,
            name: node.name,
            parentId: node.parentId,
            hasChildren: node.hasChildren === true,
            children: []
        });
    });

    byId.forEach((node) => {
        if (node.parentId && byId.has(node.parentId)) {
            byId.get(node.parentId).children.push(node);
            byId.get(node.parentId).hasChildren = true;
        } else {
            roots.push(node);
        }
    });

    const sortNodes = (nodes) => {
        nodes.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
        nodes.forEach((child) => sortNodes(child.children));
    };
    sortNodes(roots);
    return roots;
}

export default class ClmTerritoryTargeting extends LightningElement {
    @api territoryIdsJson = '[]';
    @api allowUnaligned = false;
    @api productIdsJson = '[]';

    territoryRoots = [];
    territoryFlatRows = [];
    territoryExpandedIds = new Set([ROOT_KEY]);
    alignmentByTerritoryId = {};
    searchTerm = '';
    selectedIds = new Set();
    hasLinkedProducts = false;

    @wire(getTerritories)
    wiredTerritories({ data }) {
        const flat = data || [];
        this.territoryRoots = buildTerritoryTree(flat);
        this.initializeExpanded();
        this.syncSelectedFromJson();
        this.rebuildTerritoryRows();
    }

    @wire(getTerritoryProductAlignments, { productIdsJson: '$productIdsJson' })
    wiredAlignments({ data }) {
        const map = {};
        (data || []).forEach((row) => {
            map[row.territoryId] = row;
        });
        this.alignmentByTerritoryId = map;
        try {
            const ids = JSON.parse(this.productIdsJson || '[]');
            this.hasLinkedProducts = Array.isArray(ids) && ids.length > 0;
        } catch (e) {
            this.hasLinkedProducts = false;
        }
        this.rebuildTerritoryRows();
    }

    connectedCallback() {
        this.syncSelectedFromJson();
    }

    get hasTerritories() {
        return this.territoryFlatRows.length > 0;
    }

    get alignmentHelpText() {
        if (!this.hasLinkedProducts) {
            return 'Link presentation products above to see which territories have product alignment.';
        }
        if (this.allowUnaligned) {
            return 'Aligned territories match at least one linked product. Unaligned territories can still be selected.';
        }
        return 'Only territories with aligned linked products can be selected while unaligned selection is inactive.';
    }

    syncSelectedFromJson() {
        try {
            const parsed = JSON.parse(this.territoryIdsJson || '[]');
            this.selectedIds = new Set(parsed.map((id) => String(id)));
        } catch (e) {
            this.selectedIds = new Set();
        }
        this.rebuildTerritoryRows();
    }

    initializeExpanded() {
        this.territoryExpandedIds = new Set([ROOT_KEY]);
        for (const root of this.territoryRoots) {
            this.territoryExpandedIds.add(root.id);
        }
    }

    getTerritoryAlignment(territoryId) {
        return this.alignmentByTerritoryId[String(territoryId)] || null;
    }

    buildAlignmentMeta(territoryId) {
        if (!this.hasLinkedProducts) {
            return {
                hasAlignedProducts: false,
                showAlignment: false,
                alignmentLabel: '',
                badgeClass: 'alignment-badge'
            };
        }
        const alignment = this.getTerritoryAlignment(territoryId);
        const hasAlignedProducts = alignment?.hasAlignedProducts === true;
        return {
            hasAlignedProducts,
            showAlignment: true,
            alignmentLabel: hasAlignedProducts
                ? `Aligned: ${alignment.alignedProductNames}`
                : 'No linked product alignment',
            badgeClass: hasAlignedProducts
                ? 'alignment-badge alignment-badge--aligned'
                : 'alignment-badge alignment-badge--none'
        };
    }

    rebuildTerritoryRows() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const rows = [];
        const rootExpanded = term ? true : this.territoryExpandedIds.has(ROOT_KEY);

        rows.push({
            key: ROOT_KEY,
            id: ROOT_KEY,
            name: 'Territory Alignment',
            depth: 0,
            depthStyle: 'padding-left: 0.25rem',
            hasChildren: this.territoryRoots.length > 0,
            expanded: rootExpanded,
            chevronIcon: rootExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            isVirtual: true,
            checked: false,
            showCheckbox: false,
            showAlignment: false,
            alignmentLabel: '',
            badgeClass: 'alignment-badge',
            rowClass: 'tree-row tree-row--root',
            nameClass: 'territory-name territory-name--root'
        });

        if (rootExpanded) {
            for (const root of this.territoryRoots) {
                this.flattenTerritoryNode(root, 1, rows, term);
            }
        }

        this.territoryFlatRows = rows;
    }

    flattenTerritoryNode(node, depth, rows, term) {
        const nameMatches = !term || (node.name || '').toLowerCase().includes(term);
        const childRows = [];
        if (node.children) {
            for (const child of node.children) {
                this.flattenTerritoryNode(child, depth + 1, childRows, term);
            }
        }
        if (!nameMatches && childRows.length === 0) {
            return;
        }

        const expanded = term ? true : this.territoryExpandedIds.has(node.id);
        const checked = this.selectedIds.has(String(node.id));
        const alignmentMeta = this.buildAlignmentMeta(node.id);

        rows.push({
            key: node.id,
            id: node.id,
            name: node.name,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            isVirtual: false,
            checked,
            showCheckbox: true,
            hasAlignedProducts: alignmentMeta.hasAlignedProducts,
            showAlignment: alignmentMeta.showAlignment,
            alignmentLabel: alignmentMeta.alignmentLabel,
            badgeClass: alignmentMeta.badgeClass,
            rowClass: checked ? 'tree-row tree-row--selected' : 'tree-row',
            nameClass: checked ? 'territory-name territory-name--selected' : 'territory-name'
        });

        if (expanded) {
            rows.push(...childRows);
        }
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
        this.rebuildTerritoryRows();
    }

    handleToggleAllowUnaligned(event) {
        this.allowUnaligned = event.target.checked;
        if (!this.allowUnaligned) {
            this.pruneUnalignedSelections();
        }
        this.emitChange();
    }

    pruneUnalignedSelections() {
        if (!this.hasLinkedProducts) {
            return;
        }
        let removed = false;
        for (const territoryId of Array.from(this.selectedIds)) {
            const alignment = this.getTerritoryAlignment(territoryId);
            if (alignment && alignment.hasAlignedProducts !== true) {
                this.selectedIds.delete(territoryId);
                removed = true;
            }
        }
        if (removed) {
            this.selectedIds = new Set(this.selectedIds);
            this.rebuildTerritoryRows();
            this.toast(
                'Unaligned territories removed',
                'Territories without linked product alignment were deselected.',
                'warning'
            );
        }
    }

    handleTerritoryExpand(event) {
        const id = event.currentTarget.dataset.id;
        if (this.territoryExpandedIds.has(id)) {
            this.territoryExpandedIds.delete(id);
        } else {
            this.territoryExpandedIds.add(id);
        }
        this.territoryExpandedIds = new Set(this.territoryExpandedIds);
        this.rebuildTerritoryRows();
    }

    handleTerritoryCheck(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        const alignment = this.getTerritoryAlignment(id);

        if (
            checked &&
            !this.allowUnaligned &&
            this.hasLinkedProducts &&
            alignment?.hasAlignedProducts !== true
        ) {
            event.target.checked = false;
            this.toast(
                'Product not aligned',
                'This territory has none of the linked presentation products. Enable unaligned selection to include it.',
                'warning'
            );
            return;
        }

        if (checked) {
            this.selectedIds.add(id);
            this.selectDescendants(id, true);
        } else {
            this.selectedIds.delete(id);
            this.selectDescendants(id, false);
        }
        this.selectedIds = new Set(this.selectedIds);
        this.rebuildTerritoryRows();
        this.emitChange();
    }

    selectDescendants(territoryId, selected) {
        const node = this.findTerritoryNode(this.territoryRoots, territoryId);
        if (!node) {
            return;
        }
        const walk = (current) => {
            const alignment = this.getTerritoryAlignment(current.id);
            const canSelect =
                this.allowUnaligned ||
                !this.hasLinkedProducts ||
                alignment?.hasAlignedProducts === true;

            if (selected) {
                if (canSelect) {
                    this.selectedIds.add(String(current.id));
                }
            } else {
                this.selectedIds.delete(String(current.id));
            }
            (current.children || []).forEach(walk);
        };
        (node.children || []).forEach(walk);
    }

    findTerritoryNode(nodes, territoryId) {
        for (const node of nodes || []) {
            if (node.id === territoryId) {
                return node;
            }
            const match = this.findTerritoryNode(node.children, territoryId);
            if (match) {
                return match;
            }
        }
        return null;
    }

    emitChange() {
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: {
                    territoryIdsJson: JSON.stringify(Array.from(this.selectedIds)),
                    allowUnaligned: this.allowUnaligned
                }
            })
        );
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}