import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLineTerritories from '@salesforce/apex/PromoGridAdminController.getLineTerritories';
import getPromoGrid from '@salesforce/apex/PromoGridAdminController.getPromoGrid';
import getSpecialtyOptions from '@salesforce/apex/PromoGridAdminController.getSpecialtyOptions';
import getClassOptions from '@salesforce/apex/PromoGridAdminController.getClassOptions';
import searchProducts from '@salesforce/apex/PromoGridAdminController.searchProducts';
import upsertProductWeight from '@salesforce/apex/PromoGridAdminController.upsertProductWeight';
import deleteProductWeight from '@salesforce/apex/PromoGridAdminController.deleteProductWeight';
import upsertSpecialtyFocus from '@salesforce/apex/PromoGridAdminController.upsertSpecialtyFocus';
import deleteSpecialtyFocus from '@salesforce/apex/PromoGridAdminController.deleteSpecialtyFocus';
import upsertClassTargeting from '@salesforce/apex/PromoGridAdminController.upsertClassTargeting';
import deleteClassTargeting from '@salesforce/apex/PromoGridAdminController.deleteClassTargeting';

const ACTIVE_TAB_WEIGHTS = 'weights';
const ACTIVE_TAB_SPECIALTY = 'specialty';
const ACTIVE_TAB_CLASS = 'class';

export default class PromoGridManager extends LightningElement {
    @track treeRoots = [];
    @track flatRows = [];
    @track productWeights = [];
    @track specialtyFocus = [];
    @track classTargeting = [];
    @track specialtyOptions = [];
    @track classOptions = [];
    @track productOptions = [];

    wiredLinesResult;
    wiredGridResult;
    expandedIds = new Set();

    selectedLineId;
    selectedLineName = '';
    lineSearchTerm = '';
    activeTab = ACTIVE_TAB_WEIGHTS;
    isSaving = false;

    productWeightTotal = 0;
    specialtyFocusTotal = 0;
    classTargetingTotal = 0;

    showWeightModal = false;
    showSpecialtyModal = false;
    showClassModal = false;

    draftWeight = this.emptyWeightDraft();
    draftSpecialty = this.emptySpecialtyDraft();
    draftClass = this.emptyClassDraft();
    productSearchTerm = '';

    @wire(getLineTerritories)
    wiredLines(result) {
        this.wiredLinesResult = result;
        if (result.data) {
            this.treeRoots = result.data || [];
            this.initializeExpanded();
            this.rebuildFlatRows();
            if (!this.selectedLineId) {
                const firstLine = this.findFirstLine(this.treeRoots);
                if (firstLine) {
                    this.selectLine(firstLine.id, firstLine.name);
                }
            } else {
                this.rebuildFlatRows();
            }
        } else if (result.error) {
            this.toast('Error', this.reduceError(result.error), 'error');
        }
    }

    @wire(getPromoGrid, { lineTerritoryId: '$selectedLineId' })
    wiredGrid(result) {
        this.wiredGridResult = result;
        if (result.data) {
            this.applyGrid(result.data);
        } else if (!this.selectedLineId) {
            this.clearGrid();
        } else if (result.error) {
            this.toast('Error', this.reduceError(result.error), 'error');
        }
    }

    @wire(getSpecialtyOptions)
    wiredSpecialtyOptions({ data, error }) {
        if (data) {
            this.specialtyOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.toast('Error', this.reduceError(error), 'error');
        }
    }

    @wire(getClassOptions)
    wiredClassOptions({ data, error }) {
        if (data) {
            this.classOptions = data.map((option) => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.toast('Error', this.reduceError(error), 'error');
        }
    }

    @wire(searchProducts, { searchTerm: '$productSearchTerm' })
    wiredProducts({ data }) {
        this.productOptions = (data || []).map((option) => ({
            label: option.label,
            value: option.value
        }));
    }

    get hasLines() {
        return this.filteredLines.length > 0;
    }

    get filteredLines() {
        const term = (this.lineSearchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.flatRows;
        }
        const matchIds = new Set();
        const ancestorIds = new Set();
        this.collectSearchMatches(this.treeRoots, term, matchIds, ancestorIds);
        const rows = [];
        for (const root of this.treeRoots) {
            this.flattenSearchNode(root, 0, rows, matchIds, ancestorIds);
        }
        return rows;
    }

    get hasSelectedLine() {
        return Boolean(this.selectedLineId);
    }

    get detailTitle() {
        return this.selectedLineName
            ? `Promo Grid - ${this.selectedLineName}`
            : 'Promo Grid';
    }

    get isWeightsTab() {
        return this.activeTab === ACTIVE_TAB_WEIGHTS;
    }

    get isSpecialtyTab() {
        return this.activeTab === ACTIVE_TAB_SPECIALTY;
    }

    get isClassTab() {
        return this.activeTab === ACTIVE_TAB_CLASS;
    }

    get weightsTabClass() {
        return this.tabClass(this.isWeightsTab);
    }

    get specialtyTabClass() {
        return this.tabClass(this.isSpecialtyTab);
    }

    get classTabClass() {
        return this.tabClass(this.isClassTab);
    }

    get weightMeter() {
        return this.buildMeter(this.projectedWeightTotal, true);
    }

    get specialtyMeter() {
        return this.buildMeter(this.projectedSpecialtyTotal, false);
    }

    get classMeter() {
        return this.buildMeter(this.projectedClassTotal, false);
    }

    get projectedWeightTotal() {
        return this.projectTotal(
            this.productWeightTotal,
            this.draftWeight.originalPercentage,
            this.draftWeight.weightPercentage,
            this.showWeightModal
        );
    }

    get projectedSpecialtyTotal() {
        return this.projectTotal(
            this.specialtyFocusTotal,
            this.draftSpecialty.originalPercentage,
            this.draftSpecialty.listPercentage,
            this.showSpecialtyModal
        );
    }

    get projectedClassTotal() {
        return this.projectTotal(
            this.classTargetingTotal,
            this.draftClass.originalPercentage,
            this.draftClass.listPercentage,
            this.showClassModal
        );
    }

    get weightDraftImpactLabel() {
        if (!this.showWeightModal) {
            return '';
        }
        return `Editing this row -> projected total ${this.formatPercent(this.projectedWeightTotal)}`;
    }

    get specialtyDraftImpactLabel() {
        if (!this.showSpecialtyModal) {
            return '';
        }
        return `Editing this row -> projected total ${this.formatPercent(this.projectedSpecialtyTotal)}`;
    }

    get classDraftImpactLabel() {
        if (!this.showClassModal) {
            return '';
        }
        return `Editing this row -> projected total ${this.formatPercent(this.projectedClassTotal)}`;
    }

    get hasProductWeights() {
        return this.productWeights.length > 0;
    }

    get hasSpecialtyFocus() {
        return this.specialtyFocus.length > 0;
    }

    get hasClassTargeting() {
        return this.classTargeting.length > 0;
    }

    get weightModalTitle() {
        return this.draftWeight.recordId ? 'Edit Product Weight' : 'Add Product Weight';
    }

    get specialtyModalTitle() {
        return this.draftSpecialty.recordId ? 'Edit Specialty Focus' : 'Add Specialty Focus';
    }

    get classModalTitle() {
        return this.draftClass.recordId ? 'Edit Class Targeting' : 'Add Class Targeting';
    }

    handleLineSearch(event) {
        this.lineSearchTerm = event.target.value || '';
    }

    handleToggle(event) {
        event.stopPropagation();
        const territoryId = event.currentTarget.dataset.id;
        if (this.expandedIds.has(territoryId)) {
            this.expandedIds.delete(territoryId);
        } else {
            this.expandedIds.add(territoryId);
        }
        this.expandedIds = new Set(this.expandedIds);
        this.rebuildFlatRows();
    }

    handleLineSelect(event) {
        const isLine = event.currentTarget.dataset.isLine === 'true';
        if (!isLine) {
            const territoryId = event.currentTarget.dataset.id;
            if (this.expandedIds.has(territoryId)) {
                this.expandedIds.delete(territoryId);
            } else {
                this.expandedIds.add(territoryId);
            }
            this.expandedIds = new Set(this.expandedIds);
            this.rebuildFlatRows();
            return;
        }
        const lineId = event.currentTarget.dataset.id;
        const lineName = event.currentTarget.dataset.name;
        this.selectLine(lineId, lineName);
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleNewWeight() {
        this.draftWeight = this.emptyWeightDraft();
        this.productSearchTerm = '';
        this.showWeightModal = true;
    }

    handleEditWeight(event) {
        const recordId = event.currentTarget.dataset.id;
        const row = this.productWeights.find((item) => item.id === recordId);
        if (!row) {
            return;
        }
        this.draftWeight = {
            recordId: row.id,
            product2Id: row.product2Id,
            productName: row.productName,
            weightPercentage: row.weightPercentage,
            originalPercentage: row.weightPercentage
        };
        this.productSearchTerm = row.productName || '';
        this.showWeightModal = true;
    }

    handleWeightProductSearch(event) {
        this.productSearchTerm = event.target.value || '';
    }

    handleWeightProductChange(event) {
        this.draftWeight = {
            ...this.draftWeight,
            product2Id: event.detail.value
        };
    }

    handleWeightPercentageChange(event) {
        const value = event.target.value;
        this.draftWeight = {
            ...this.draftWeight,
            weightPercentage: value === '' || value === null ? null : Number(value)
        };
    }

    handleCloseWeightModal() {
        this.showWeightModal = false;
        this.draftWeight = this.emptyWeightDraft();
    }

    async handleSaveWeight() {
        if (!this.selectedLineId) {
            return;
        }
        if (!this.draftWeight.product2Id) {
            this.toast('Missing product', 'Select a product.', 'warning');
            return;
        }
        if (this.draftWeight.weightPercentage === null || this.draftWeight.weightPercentage === undefined) {
            this.toast('Missing weight', 'Enter a weight percentage.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await upsertProductWeight({
                input: {
                    recordId: this.draftWeight.recordId,
                    territory2Id: this.selectedLineId,
                    product2Id: this.draftWeight.product2Id,
                    weightPercentage: this.draftWeight.weightPercentage
                }
            });
            this.toast('Saved', 'Product weight saved.', 'success');
            this.handleCloseWeightModal();
            await this.refreshAll();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteWeight(event) {
        const recordId = event.currentTarget.dataset.id;
        this.isSaving = true;
        try {
            await deleteProductWeight({ recordId });
            this.toast('Deleted', 'Product weight removed.', 'success');
            await this.refreshAll();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleNewSpecialty() {
        this.draftSpecialty = this.emptySpecialtyDraft();
        this.showSpecialtyModal = true;
    }

    handleEditSpecialty(event) {
        const recordId = event.currentTarget.dataset.id;
        const row = this.specialtyFocus.find((item) => item.id === recordId);
        if (!row) {
            return;
        }
        this.draftSpecialty = {
            recordId: row.id,
            specialty: row.specialty,
            listPercentage: row.listPercentage,
            originalPercentage: row.listPercentage
        };
        this.showSpecialtyModal = true;
    }

    handleSpecialtyChange(event) {
        this.draftSpecialty = {
            ...this.draftSpecialty,
            specialty: event.detail.value
        };
    }

    handleSpecialtyPercentageChange(event) {
        const value = event.target.value;
        this.draftSpecialty = {
            ...this.draftSpecialty,
            listPercentage: value === '' || value === null ? null : Number(value)
        };
    }

    handleCloseSpecialtyModal() {
        this.showSpecialtyModal = false;
        this.draftSpecialty = this.emptySpecialtyDraft();
    }

    async handleSaveSpecialty() {
        if (!this.selectedLineId) {
            return;
        }
        if (!this.draftSpecialty.specialty) {
            this.toast('Missing specialty', 'Select a specialty.', 'warning');
            return;
        }
        if (this.draftSpecialty.listPercentage === null || this.draftSpecialty.listPercentage === undefined) {
            this.toast('Missing percentage', 'Enter a list percentage.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await upsertSpecialtyFocus({
                input: {
                    recordId: this.draftSpecialty.recordId,
                    territory2Id: this.selectedLineId,
                    specialty: this.draftSpecialty.specialty,
                    listPercentage: this.draftSpecialty.listPercentage
                }
            });
            this.toast('Saved', 'Specialty focus saved.', 'success');
            this.handleCloseSpecialtyModal();
            await this.refreshAll();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteSpecialty(event) {
        const recordId = event.currentTarget.dataset.id;
        this.isSaving = true;
        try {
            await deleteSpecialtyFocus({ recordId });
            this.toast('Deleted', 'Specialty focus removed.', 'success');
            await this.refreshAll();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleNewClass() {
        this.draftClass = this.emptyClassDraft();
        this.showClassModal = true;
    }

    handleEditClass(event) {
        const recordId = event.currentTarget.dataset.id;
        const row = this.classTargeting.find((item) => item.id === recordId);
        if (!row) {
            return;
        }
        this.draftClass = {
            recordId: row.id,
            classCode: row.classCode,
            listPercentage: row.listPercentage,
            targetMonthlyVisits: row.targetMonthlyVisits,
            originalPercentage: row.listPercentage
        };
        this.showClassModal = true;
    }

    handleClassChange(event) {
        this.draftClass = {
            ...this.draftClass,
            classCode: event.detail.value
        };
    }

    handleClassPercentageChange(event) {
        const value = event.target.value;
        this.draftClass = {
            ...this.draftClass,
            listPercentage: value === '' || value === null ? null : Number(value)
        };
    }

    handleClassVisitsChange(event) {
        const value = event.target.value;
        this.draftClass = {
            ...this.draftClass,
            targetMonthlyVisits: value === '' || value === null ? null : Number(value)
        };
    }

    handleCloseClassModal() {
        this.showClassModal = false;
        this.draftClass = this.emptyClassDraft();
    }

    async handleSaveClass() {
        if (!this.selectedLineId) {
            return;
        }
        if (!this.draftClass.classCode) {
            this.toast('Missing class', 'Select a class.', 'warning');
            return;
        }
        if (this.draftClass.listPercentage === null || this.draftClass.listPercentage === undefined) {
            this.toast('Missing percentage', 'Enter a list percentage.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await upsertClassTargeting({
                input: {
                    recordId: this.draftClass.recordId,
                    territory2Id: this.selectedLineId,
                    classCode: this.draftClass.classCode,
                    listPercentage: this.draftClass.listPercentage,
                    targetMonthlyVisits: this.draftClass.targetMonthlyVisits
                }
            });
            this.toast('Saved', 'Class targeting saved.', 'success');
            this.handleCloseClassModal();
            await this.refreshAll();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteClass(event) {
        const recordId = event.currentTarget.dataset.id;
        this.isSaving = true;
        try {
            await deleteClassTargeting({ recordId });
            this.toast('Deleted', 'Class targeting removed.', 'success');
            await this.refreshAll();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    selectLine(lineId, lineName) {
        this.selectedLineId = lineId;
        this.selectedLineName = lineName;
        this.rebuildFlatRows();
    }

    applyGrid(data) {
        this.selectedLineName = data.lineName || this.selectedLineName;
        this.productWeights = (data.productWeights || []).map((row) => ({
            ...row,
            weightLabel: this.formatPercent(row.weightPercentage)
        }));
        this.specialtyFocus = (data.specialtyFocus || []).map((row) => ({
            ...row,
            percentageLabel: this.formatPercent(row.listPercentage)
        }));
        this.classTargeting = (data.classTargeting || []).map((row) => ({
            ...row,
            percentageLabel: this.formatPercent(row.listPercentage),
            visitsLabel:
                row.targetMonthlyVisits === null || row.targetMonthlyVisits === undefined
                    ? '--'
                    : String(row.targetMonthlyVisits)
        }));
        this.productWeightTotal = Number(data.productWeightTotal || 0);
        this.specialtyFocusTotal = Number(data.specialtyFocusTotal || 0);
        this.classTargetingTotal = Number(data.classTargetingTotal || 0);
    }

    clearGrid() {
        this.productWeights = [];
        this.specialtyFocus = [];
        this.classTargeting = [];
        this.productWeightTotal = 0;
        this.specialtyFocusTotal = 0;
        this.classTargetingTotal = 0;
    }

    initializeExpanded() {
        if (this.expandedIds.size > 0) {
            return;
        }
        for (const root of this.treeRoots) {
            this.expandedIds.add(root.id);
            if (root.children) {
                for (const child of root.children) {
                    this.expandedIds.add(child.id);
                }
            }
        }
        this.expandedIds = new Set(this.expandedIds);
    }

    rebuildFlatRows() {
        const rows = [];
        for (const root of this.treeRoots) {
            this.flattenNode(root, 0, rows);
        }
        this.flatRows = rows;
    }

    flattenNode(node, depth, rows) {
        rows.push(this.toTreeRowView(node, depth));
        const expanded = this.expandedIds.has(node.id);
        if (expanded && node.children) {
            for (const child of node.children) {
                this.flattenNode(child, depth + 1, rows);
            }
        }
    }

    flattenSearchNode(node, depth, rows, matchIds, ancestorIds) {
        if (!matchIds.has(node.id) && !ancestorIds.has(node.id)) {
            return;
        }
        rows.push(this.toTreeRowView(node, depth, true));
        if (node.children) {
            for (const child of node.children) {
                this.flattenSearchNode(child, depth + 1, rows, matchIds, ancestorIds);
            }
        }
    }

    collectSearchMatches(nodes, term, matchIds, ancestorIds) {
        if (!nodes) {
            return false;
        }
        let anyMatch = false;
        for (const node of nodes) {
            const selfMatch =
                (node.name || '').toLowerCase().includes(term) ||
                (node.externalId || '').toLowerCase().includes(term);
            const childMatch = this.collectSearchMatches(
                node.children,
                term,
                matchIds,
                ancestorIds
            );
            if (selfMatch) {
                matchIds.add(node.id);
                anyMatch = true;
            }
            if (childMatch) {
                ancestorIds.add(node.id);
                anyMatch = true;
            }
        }
        return anyMatch;
    }

    findFirstLine(nodes) {
        if (!nodes) {
            return null;
        }
        for (const node of nodes) {
            if (node.isLine) {
                return node;
            }
            const nested = this.findFirstLine(node.children);
            if (nested) {
                return nested;
            }
        }
        return null;
    }

    toTreeRowView(node, depth, forceExpanded) {
        const weightTotal = Number(node.weightTotal || 0);
        const isLine = node.isLine === true;
        const isSelected = isLine && node.id === this.selectedLineId;
        const expanded = forceExpanded === true ? true : this.expandedIds.has(node.id);
        const isVacant = node.isVacant === true;
        return {
            id: node.id,
            name: node.name,
            externalId: node.externalId,
            level: node.level || 'Unknown',
            isLine,
            hasChildren: node.hasChildren === true,
            depth,
            depthStyle: `padding-left: ${depth * 0.9}rem`,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            isVacant,
            vacantClass: isVacant ? 'badge badge-vacant' : 'badge badge-assigned',
            vacantLabel: isVacant ? 'Vacant' : 'Assigned',
            weightBadge: isLine ? `${this.formatPercent(weightTotal)} weights` : '',
            badgeClass: this.badgeClassForTotal(weightTotal),
            isSelected,
            rowClass: isSelected ? 'line-row line-row--selected' : 'line-row',
            selectBtnClass: isLine
                ? 'line-select-btn line-select-btn--line'
                : 'line-select-btn line-select-btn--branch',
            selectDisabled: false,
            selectTitle: isLine ? 'Select line for Promo Grid' : 'Expand or collapse'
        };
    }

    buildMeter(totalValue, emphasizeHundred) {
        const total = Number(totalValue || 0);
        const remaining = 100 - total;
        const status =
            Math.abs(remaining) < 0.01 ? 'ok' : remaining > 0 ? 'under' : 'over';
        const width = Math.max(0, Math.min(100, total));
        return {
            totalLabel: this.formatPercent(total),
            remainingLabel: this.formatPercent(remaining),
            statusLabel:
                status === 'ok'
                    ? emphasizeHundred
                        ? 'On target (100%)'
                        : 'Totals 100%'
                    : status === 'under'
                      ? emphasizeHundred
                          ? `${this.formatPercent(remaining)} left to reach 100%`
                          : `${this.formatPercent(remaining)} remaining to 100%`
                      : `${this.formatPercent(Math.abs(remaining))} over 100%`,
            barClass: `meter-fill meter-fill--${status}`,
            stripClass: `meter-strip meter-strip--${status}`,
            barStyle: `width:${width}%;`
        };
    }

    projectTotal(savedTotal, originalValue, draftValue, active) {
        if (!active) {
            return Number(savedTotal || 0);
        }
        const base = Number(savedTotal || 0);
        const original =
            originalValue === null || originalValue === undefined ? 0 : Number(originalValue);
        const draft = draftValue === null || draftValue === undefined ? 0 : Number(draftValue);
        return base - original + draft;
    }

    tabClass(isActive) {
        return isActive ? 'tab-btn tab-btn--active' : 'tab-btn';
    }

    badgeClassForTotal(total) {
        if (Math.abs(100 - total) < 0.01) {
            return 'line-badge line-badge--ok';
        }
        if (total > 100) {
            return 'line-badge line-badge--over';
        }
        return 'line-badge';
    }

    formatPercent(value) {
        const number = Number(value || 0);
        return `${number.toFixed(number % 1 === 0 ? 0 : 1)}%`;
    }

    async refreshAll() {
        const tasks = [];
        if (this.wiredLinesResult) {
            tasks.push(refreshApex(this.wiredLinesResult));
        }
        if (this.wiredGridResult) {
            tasks.push(refreshApex(this.wiredGridResult));
        }
        await Promise.all(tasks);
    }

    emptyWeightDraft() {
        return {
            recordId: null,
            product2Id: null,
            productName: '',
            weightPercentage: null,
            originalPercentage: 0
        };
    }

    emptySpecialtyDraft() {
        return {
            recordId: null,
            specialty: null,
            listPercentage: null,
            originalPercentage: 0
        };
    }

    emptyClassDraft() {
        return {
            recordId: null,
            classCode: null,
            listPercentage: null,
            targetMonthlyVisits: null,
            originalPercentage: 0
        };
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}