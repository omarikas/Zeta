import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import getBricksByTerritory from '@salesforce/apex/BricksManagementController.getBricksByTerritory';
import getBrickPharmacies from '@salesforce/apex/BricksManagementController.getBrickPharmacies';
import searchPharmacyOptions from '@salesforce/apex/BricksManagementController.searchPharmacyOptions';
import upsertBrick from '@salesforce/apex/BricksManagementController.upsertBrick';
import assignBrickToTerritory from '@salesforce/apex/BricksManagementController.assignBrickToTerritory';
import deleteBrick from '@salesforce/apex/BricksManagementController.deleteBrick';
import addPharmacyToBrick from '@salesforce/apex/BricksManagementController.addPharmacyToBrick';
import removePharmacyFromBrick from '@salesforce/apex/BricksManagementController.removePharmacyFromBrick';
import seedBrickDemoData from '@salesforce/apex/BricksManagementController.seedBrickDemoData';

const DATA_SOURCE_OPTIONS = [
    { label: 'IQVIA IMS', value: 'IQVIA IMS' },
    { label: 'IbnSina', value: 'IbnSina' },
    { label: 'Pharmaoverseas', value: 'Pharmaoverseas' }
];

export default class BricksManagementConsole extends LightningElement {
    treeRoots = [];
    territoryFlatRows = [];
    territoryExpandedIds = new Set();
    selectedTerritoryId;
    selectedTerritoryName = 'All Territories';

    brickRows = [];
    pharmacyRows = [];
    pharmacyOptions = [];
    wiredBricksResult;
    wiredPharmaciesResult;

    selectedBrickId;
    selectedBrickName = '';
    selectedPharmacyId;
    pharmacySearchTerm = '';
    brickSearchTerm = '';

    showBrickModal = false;
    isSaving = false;
    isSeeding = false;

    draftBrick = {
        recordId: null,
        name: '',
        externalId: '',
        brickCode: '',
        dataSource: 'IQVIA IMS',
        governorate: '',
        city: '',
        isActive: true
    };

    dataSourceOptions = DATA_SOURCE_OPTIONS;

    brickColumns = [
        { label: 'Brick', fieldName: 'brickName', type: 'text' },
        { label: 'Code', fieldName: 'brickCode', type: 'text' },
        { label: 'Source', fieldName: 'dataSource', type: 'text' },
        { label: 'City', fieldName: 'city', type: 'text' },
        { label: 'Pharmacies', fieldName: 'pharmacyCount', type: 'number' },
        { label: 'Status', fieldName: 'statusLabel', type: 'text' }
    ];

    pharmacyColumns = [
        { label: 'Pharmacy', fieldName: 'pharmacyName', type: 'text' },
        { label: 'Type', fieldName: 'pharmacyType', type: 'text' },
        {
            type: 'button-icon',
            fixedWidth: 52,
            typeAttributes: {
                iconName: 'utility:delete',
                name: 'remove',
                title: 'Remove from brick',
                variant: 'border-filled',
                alternativeText: 'Remove'
            }
        }
    ];

    @wire(getTerritoryTree)
    wiredTerritoryTree({ data }) {
        if (data) {
            this.treeRoots = data;
            this.initializeTerritoryExpanded();
            this.rebuildTerritoryRows();
        }
    }

    @wire(getBricksByTerritory, { territory2Id: '$selectedTerritoryId' })
    wiredBricks(result) {
        this.wiredBricksResult = result;
        if (result.data) {
            this.brickRows = result.data.map((row) => ({
                ...row,
                statusLabel: row.isActive ? 'Active' : 'Inactive',
                rowClass: row.brickId === this.selectedBrickId ? 'brick-row brick-row--selected' : 'brick-row'
            }));
        } else {
            this.brickRows = [];
        }
    }

    @wire(getBrickPharmacies, { brickId: '$selectedBrickId' })
    wiredPharmacies(result) {
        this.wiredPharmaciesResult = result;
        this.pharmacyRows = result.data || [];
    }

    @wire(searchPharmacyOptions, { searchTerm: '$pharmacySearchTerm' })
    wiredPharmacySearch({ data }) {
        this.pharmacyOptions = (data || []).map((option) => ({
            label: option.label,
            value: option.value
        }));
    }

    get hasTerritories() {
        return this.territoryFlatRows.length > 0;
    }

    get hasBricks() {
        return this.filteredBrickRows.length > 0;
    }

    get filteredBrickRows() {
        const term = (this.brickSearchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.brickRows;
        }
        return this.brickRows.filter(
            (row) =>
                (row.brickName || '').toLowerCase().includes(term) ||
                (row.brickCode || '').toLowerCase().includes(term) ||
                (row.city || '').toLowerCase().includes(term) ||
                (row.dataSource || '').toLowerCase().includes(term)
        );
    }

    get showPharmacyPane() {
        return Boolean(this.selectedBrickId);
    }

    get pharmacyPaneTitle() {
        return this.selectedBrickName
            ? `Pharmacies — ${this.selectedBrickName}`
            : 'Pharmacies';
    }

    get isSaveBrickDisabled() {
        return this.isSaving || !(this.draftBrick.name || '').trim();
    }

    get isAddPharmacyDisabled() {
        return !this.selectedBrickId || !this.selectedPharmacyId;
    }

    get modalTitle() {
        return this.draftBrick.recordId ? 'Edit Brick' : 'New Brick';
    }

    initializeTerritoryExpanded() {
        if (this.territoryExpandedIds.size > 0) {
            return;
        }
        for (const root of this.treeRoots) {
            this.territoryExpandedIds.add(root.id);
            if (root.children) {
                for (const child of root.children) {
                    this.territoryExpandedIds.add(child.id);
                }
            }
        }
        this.territoryExpandedIds = new Set(this.territoryExpandedIds);
    }

    rebuildTerritoryRows() {
        const rows = [{ key: 'all', id: null, name: 'All Territories', depth: 0, depthStyle: 'padding-left: 0', hasChildren: false, expanded: false, chevronIcon: '', rowClass: !this.selectedTerritoryId ? 'tree-row tree-row--selected' : 'tree-row', isAll: true }];
        for (const root of this.treeRoots) {
            this.flattenTerritoryNode(root, 0, rows);
        }
        this.territoryFlatRows = rows;
    }

    flattenTerritoryNode(node, depth, rows) {
        const expanded = this.territoryExpandedIds.has(node.id);
        rows.push({
            key: node.id,
            id: node.id,
            name: node.name,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            rowClass: node.id === this.selectedTerritoryId ? 'tree-row tree-row--selected' : 'tree-row',
            isAll: false
        });
        if (expanded && node.children) {
            for (const child of node.children) {
                this.flattenTerritoryNode(child, depth + 1, rows);
            }
        }
    }

    handleTerritoryToggle(event) {
        const territoryId = event.currentTarget.dataset.id;
        if (this.territoryExpandedIds.has(territoryId)) {
            this.territoryExpandedIds.delete(territoryId);
        } else {
            this.territoryExpandedIds.add(territoryId);
        }
        this.territoryExpandedIds = new Set(this.territoryExpandedIds);
        this.rebuildTerritoryRows();
    }

    handleTerritorySelect(event) {
        const territoryId = event.currentTarget.dataset.id || null;
        const territoryName = event.currentTarget.dataset.name || 'All Territories';
        this.selectedTerritoryId = territoryId;
        this.selectedTerritoryName = territoryName;
        this.selectedBrickId = null;
        this.selectedBrickName = '';
        this.rebuildTerritoryRows();
    }

    handleBrickSearch(event) {
        this.brickSearchTerm = event.target.value || '';
    }

    handleBrickSelect(event) {
        const { brickid, brickname } = event.currentTarget.dataset;
        this.selectedBrickId = brickid;
        this.selectedBrickName = brickname;
        this.brickRows = this.brickRows.map((row) => ({
            ...row,
            rowClass: row.brickId === brickid ? 'brick-row brick-row--selected' : 'brick-row'
        }));
    }

    handleNewBrick() {
        this.draftBrick = {
            recordId: null,
            name: '',
            externalId: '',
            brickCode: '',
            dataSource: 'IQVIA IMS',
            governorate: '',
            city: '',
            isActive: true
        };
        this.showBrickModal = true;
    }

    handleEditBrick(event) {
        const brickId = event.currentTarget.dataset.id;
        const brick = this.brickRows.find((row) => row.brickId === brickId);
        if (!brick) {
            return;
        }
        this.draftBrick = {
            recordId: brick.brickId,
            name: brick.brickName,
            externalId: '',
            brickCode: brick.brickCode || '',
            dataSource: brick.dataSource || 'IQVIA IMS',
            governorate: brick.governorate || '',
            city: brick.city || '',
            isActive: brick.isActive !== false
        };
        this.showBrickModal = true;
    }

    handleDraftChange(event) {
        const field = event.target.dataset.field;
        let value;
        if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
        } else if (event.target.type === 'checkbox') {
            value = event.target.checked;
        } else {
            value = event.target.value;
        }
        this.draftBrick = { ...this.draftBrick, [field]: value };
    }

    handleCloseBrickModal() {
        this.showBrickModal = false;
    }

    async handleSaveBrick() {
        this.isSaving = true;
        try {
            const brickId = await upsertBrick({
                recordId: this.draftBrick.recordId,
                name: this.draftBrick.name,
                externalId: this.draftBrick.externalId,
                brickCode: this.draftBrick.brickCode,
                dataSource: this.draftBrick.dataSource,
                governorate: this.draftBrick.governorate,
                city: this.draftBrick.city,
                territory2Id: this.selectedTerritoryId,
                isActive: this.draftBrick.isActive
            });
            if (this.selectedTerritoryId && !this.draftBrick.recordId) {
                await assignBrickToTerritory({ brickId, territory2Id: this.selectedTerritoryId });
            }
            this.showBrickModal = false;
            await refreshApex(this.wiredBricksResult);
            this.toast('Success', 'Brick saved.', 'success');
        } catch (error) {
            this.toast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleAssignTerritory(event) {
        const brickId = event.currentTarget.dataset.id;
        if (!this.selectedTerritoryId) {
            this.toast('Select territory', 'Choose a territory on the left first.', 'warning');
            return;
        }
        try {
            await assignBrickToTerritory({ brickId, territory2Id: this.selectedTerritoryId });
            await refreshApex(this.wiredBricksResult);
            this.toast('Aligned', 'Brick aligned to territory.', 'success');
        } catch (error) {
            this.toast('Alignment failed', this.reduceError(error), 'error');
        }
    }

    async handleDeleteBrick(event) {
        const brickId = event.currentTarget.dataset.id;
        try {
            await deleteBrick({ brickId });
            if (this.selectedBrickId === brickId) {
                this.selectedBrickId = null;
                this.selectedBrickName = '';
            }
            await refreshApex(this.wiredBricksResult);
            this.toast('Deleted', 'Brick removed.', 'success');
        } catch (error) {
            this.toast('Delete failed', this.reduceError(error), 'error');
        }
    }

    handlePharmacySearch(event) {
        this.pharmacySearchTerm = event.target.value || '';
    }

    handlePharmacySelect(event) {
        this.selectedPharmacyId = event.detail.value;
    }

    async handleAddPharmacy() {
        try {
            await addPharmacyToBrick({
                brickId: this.selectedBrickId,
                pharmacyId: this.selectedPharmacyId
            });
            this.selectedPharmacyId = null;
            await refreshApex(this.wiredPharmaciesResult);
            await refreshApex(this.wiredBricksResult);
            this.toast('Added', 'Pharmacy linked to brick.', 'success');
        } catch (error) {
            this.toast('Add failed', this.reduceError(error), 'error');
        }
    }

    async handlePharmacyRowAction(event) {
        if (event.detail.action.name !== 'remove') {
            return;
        }
        try {
            await removePharmacyFromBrick({ membershipId: event.detail.row.membershipId });
            await refreshApex(this.wiredPharmaciesResult);
            await refreshApex(this.wiredBricksResult);
            this.toast('Removed', 'Pharmacy removed from brick.', 'success');
        } catch (error) {
            this.toast('Remove failed', this.reduceError(error), 'error');
        }
    }

    async handleSeedDemoData() {
        this.isSeeding = true;
        try {
            const result = await seedBrickDemoData();
            await refreshApex(this.wiredBricksResult);
            if (this.selectedBrickId) {
                await refreshApex(this.wiredPharmaciesResult);
            }
            this.toast('Demo data loaded', result.message || 'Brick demo data refreshed.', 'success');
        } catch (error) {
            this.toast('Seed failed', this.reduceError(error), 'error');
        } finally {
            this.isSeeding = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}