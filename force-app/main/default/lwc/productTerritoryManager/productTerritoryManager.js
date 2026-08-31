import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProductCatalogTree from '@salesforce/apex/ProductCatalogAdminController.getProductCatalogTree';
import getTerritoryTreeForProduct from '@salesforce/apex/ProductCatalogAdminController.getTerritoryTreeForProduct';
import saveProductTerritoryAlignments from '@salesforce/apex/ProductCatalogAdminController.saveProductTerritoryAlignments';

export default class ProductTerritoryManager extends LightningElement {
    productRoots = [];
    territoryRoots = [];
    productFlatRows = [];
    territoryFlatRows = [];
    productExpandedKeys = new Set();
    territoryExpandedIds = new Set();
    selectedProductId;
    selectedProductLabel = '';
    selectedTerritoryIds = new Set();
    productSearchTerm = '';
    territorySearchTerm = '';
    cascadeToChildren = true;
    isLoadingTerritories = false;
    isSaving = false;
    hasUnsavedChanges = false;

    @wire(getProductCatalogTree)
    wiredProducts({ data, error }) {
        if (data) {
            this.productRoots = data;
            this.initializeProductExpanded();
            this.rebuildProductRows();
        } else if (error) {
            this.productRoots = [];
            this.productFlatRows = [];
            this.toast('Product catalog error', this.reduceError(error), 'error');
        }
    }

    get hasProducts() {
        return this.productFlatRows.length > 0;
    }

    get hasTerritories() {
        return this.territoryFlatRows.length > 0;
    }

    get showTerritoryPane() {
        return Boolean(this.selectedProductId);
    }

    get territoryPaneTitle() {
        return this.selectedProductLabel
            ? `Territory Distribution — ${this.selectedProductLabel}`
            : 'Territory Distribution';
    }

    get isSaveDisabled() {
        return !this.selectedProductId || this.isSaving || !this.hasUnsavedChanges;
    }

    get selectedAlignmentCount() {
        return this.selectedTerritoryIds.size;
    }

    initializeProductExpanded() {
        if (this.productExpandedKeys.size > 0) {
            return;
        }
        for (const family of this.productRoots) {
            this.productExpandedKeys.add(family.key);
        }
        this.productExpandedKeys = new Set(this.productExpandedKeys);
    }

    initializeTerritoryExpanded() {
        this.territoryExpandedIds = new Set();
        for (const root of this.territoryRoots) {
            this.territoryExpandedIds.add(root.id);
            if (root.children) {
                for (const child of root.children) {
                    this.territoryExpandedIds.add(child.id);
                }
            }
        }
    }

    rebuildProductRows() {
        const term = (this.productSearchTerm || '').trim().toLowerCase();
        const rows = [];
        for (const family of this.productRoots) {
            const matchingChildren = (family.children || []).filter((product) => {
                if (!term) {
                    return true;
                }
                return (
                    (product.label || '').toLowerCase().includes(term) ||
                    (product.productCode || '').toLowerCase().includes(term) ||
                    (family.label || '').toLowerCase().includes(term)
                );
            });
            if (term && matchingChildren.length === 0 && !(family.label || '').toLowerCase().includes(term)) {
                continue;
            }

            const familyExpanded = term ? true : this.productExpandedKeys.has(family.key);
            rows.push({
                key: family.key,
                rowKey: family.key,
                label: family.label,
                nodeType: 'family',
                depth: 0,
                depthStyle: 'padding-left: 0.25rem',
                hasChildren: matchingChildren.length > 0,
                expanded: familyExpanded,
                chevronIcon: familyExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                isSelected: false,
                isFamily: true,
                selectable: false
            });

            if (familyExpanded) {
                for (const product of matchingChildren) {
                    const isSelected = product.productId === this.selectedProductId;
                    rows.push({
                        key: product.key,
                        rowKey: product.key,
                        label: product.label,
                        nodeType: 'product',
                        productId: product.productId,
                        therapyArea: product.therapyArea,
                        productCode: product.productCode,
                        imageUrl: product.imageUrl,
                        depth: 1,
                        depthStyle: 'padding-left: 1.5rem',
                        hasChildren: false,
                        expanded: false,
                        chevronIcon: 'utility:chevronright',
                        isSelected,
                        isFamily: false,
                        selectable: true,
                        rowClass: isSelected ? 'tree-row tree-row--selected' : 'tree-row'
                    });
                }
            }
        }
        this.productFlatRows = rows;
    }

    rebuildTerritoryRows() {
        const term = (this.territorySearchTerm || '').trim().toLowerCase();
        const rows = [];
        for (const root of this.territoryRoots) {
            this.flattenTerritoryNode(root, 0, rows, term);
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
        const checked = this.selectedTerritoryIds.has(String(node.id));
        rows.push({
            key: node.id,
            id: node.id,
            name: node.name,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            checked,
            checkboxLabel: node.name
        });

        if (expanded) {
            rows.push(...childRows);
        }
    }

    handleProductSearch(event) {
        this.productSearchTerm = event.target.value || '';
        this.rebuildProductRows();
    }

    handleTerritorySearch(event) {
        this.territorySearchTerm = event.target.value || '';
        this.rebuildTerritoryRows();
    }

    handleProductToggle(event) {
        const familyKey = event.currentTarget.dataset.key;
        if (this.productExpandedKeys.has(familyKey)) {
            this.productExpandedKeys.delete(familyKey);
        } else {
            this.productExpandedKeys.add(familyKey);
        }
        this.productExpandedKeys = new Set(this.productExpandedKeys);
        this.rebuildProductRows();
    }

    async handleProductSelect(event) {
        const productId = event.currentTarget.dataset.id;
        const productLabel = event.currentTarget.dataset.label;
        if (!productId || productId === this.selectedProductId) {
            return;
        }
        if (this.hasUnsavedChanges) {
            const confirmed = window.confirm('You have unsaved territory changes. Discard them and switch product?');
            if (!confirmed) {
                return;
            }
        }
        this.selectedProductId = productId;
        this.selectedProductLabel = productLabel;
        this.hasUnsavedChanges = false;
        this.rebuildProductRows();
        await this.loadTerritoryTree();
    }

    async loadTerritoryTree() {
        if (!this.selectedProductId) {
            this.territoryRoots = [];
            this.territoryFlatRows = [];
            this.selectedTerritoryIds = new Set();
            return;
        }
        this.isLoadingTerritories = true;
        try {
            const tree = await getTerritoryTreeForProduct({ productId: this.selectedProductId });
            this.territoryRoots = tree || [];
            this.selectedTerritoryIds = this.collectAlignedIds(this.territoryRoots);
            this.initializeTerritoryExpanded();
            this.rebuildTerritoryRows();
        } catch (error) {
            this.territoryRoots = [];
            this.territoryFlatRows = [];
            this.toast('Territory load failed', this.reduceError(error), 'error');
        } finally {
            this.isLoadingTerritories = false;
        }
    }

    collectAlignedIds(nodes) {
        const ids = new Set();
        const walk = (nodeList) => {
            for (const node of nodeList || []) {
                if (node.aligned) {
                    ids.add(String(node.id));
                }
                walk(node.children);
            }
        };
        walk(nodes);
        return ids;
    }

    findTerritoryNode(nodes, territoryId) {
        for (const node of nodes || []) {
            if (String(node.id) === String(territoryId)) {
                return node;
            }
            const match = this.findTerritoryNode(node.children, territoryId);
            if (match) {
                return match;
            }
        }
        return null;
    }

    collectDescendantIds(node) {
        const ids = [];
        const walk = (current) => {
            if (!current) {
                return;
            }
            ids.push(String(current.id));
            for (const child of current.children || []) {
                walk(child);
            }
        };
        walk(node);
        return ids;
    }

    handleTerritoryExpand(event) {
        const territoryId = event.currentTarget.dataset.id;
        if (this.territoryExpandedIds.has(territoryId)) {
            this.territoryExpandedIds.delete(territoryId);
        } else {
            this.territoryExpandedIds.add(territoryId);
        }
        this.territoryExpandedIds = new Set(this.territoryExpandedIds);
        this.rebuildTerritoryRows();
    }

    handleCascadeToggle(event) {
        this.cascadeToChildren = event.target.checked;
    }

    handleTerritoryCheck(event) {
        const territoryId = event.target.dataset.id;
        const checked = event.target.checked;
        const node = this.findTerritoryNode(this.territoryRoots, territoryId);
        const targetIds = this.cascadeToChildren && node
            ? this.collectDescendantIds(node)
            : [String(territoryId)];

        const next = new Set(this.selectedTerritoryIds);
        for (const id of targetIds) {
            if (checked) {
                next.add(id);
            } else {
                next.delete(id);
            }
        }
        this.selectedTerritoryIds = next;
        this.hasUnsavedChanges = true;
        this.rebuildTerritoryRows();
    }

    async handleSave() {
        if (!this.selectedProductId) {
            return;
        }
        this.isSaving = true;
        try {
            const territoryIds = Array.from(this.selectedTerritoryIds);
            await saveProductTerritoryAlignments({
                productId: this.selectedProductId,
                territoryIds
            });
            this.hasUnsavedChanges = false;
            await this.loadTerritoryTree();
            this.toast(
                'Alignment saved',
                `${territoryIds.length} territor${territoryIds.length === 1 ? 'y' : 'ies'} aligned to ${this.selectedProductLabel}.`,
                'success'
            );
        } catch (error) {
            this.toast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}