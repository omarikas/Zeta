import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMaterialSummaries from '@salesforce/apex/LearningAdminController.getMaterialSummaries';
import getAssignments from '@salesforce/apex/LearningAdminController.getAssignments';
import createMaterial from '@salesforce/apex/LearningAdminController.createMaterial';
import updateMaterial from '@salesforce/apex/LearningAdminController.updateMaterial';
import assignToUser from '@salesforce/apex/LearningAdminController.assignToUser';

const CHILD_TYPE_OPTIONS = [
    { label: 'Video', value: 'Video' },
    { label: 'PDF', value: 'PDF' },
    { label: 'Lesson', value: 'Lesson' },
    { label: 'Quiz', value: 'Quiz' }
];

export default class LearningModuleManager extends NavigationMixin(LightningElement) {
    searchTerm = '';
    typeFilter = 'All';
    activeFilter = 'All';
    materials = [];
    wiredResult;
    expandedIds = new Set();
    selectedParentId;
    selectedChildId;

    @track editTitle = '';
    @track editDescription = '';
    @track editActive = true;
    @track editDuration;
    @track editMaterialType = 'Course';
    @track editMaterialUrl = '';
    @track assignees = [];
    assigneesLoading = false;
    assignUserId;

    showNewModal = false;
    isSaving = false;
    newTitle = '';
    newType = 'Course';

    typeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Course', value: 'Course' },
        { label: 'Video', value: 'Video' },
        { label: 'PDF', value: 'PDF' },
        { label: 'Lesson', value: 'Lesson' },
        { label: 'Quiz', value: 'Quiz' }
    ];

    activeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];

    newTypeOptions = this.typeOptions.filter((o) => o.value !== 'All');
    childTypeOptions = CHILD_TYPE_OPTIONS;

    @wire(getMaterialSummaries, {
        searchTerm: '$searchTerm',
        typeFilter: '$typeFilter',
        activeFilter: '$activeFilter'
    })
    wiredMaterials(result) {
        this.wiredResult = result;
        if (result.data) {
            this.materials = result.data.map((row) => {
                const durationLabel = row.duration != null ? `${row.duration} min` : '-';
                return {
                    ...row,
                    activeLabel: row.isActive ? 'Active' : 'Inactive',
                    durationLabel,
                    metaLabel: [row.materialType, row.isActive ? 'Active' : 'Inactive', durationLabel]
                        .filter(Boolean)
                        .join(' | ')
                };
            });
            this.syncSelectionAfterRefresh();
        } else {
            this.materials = [];
        }
    }

    syncSelectionAfterRefresh() {
        if (this.selectedChildId) {
            const child = this.materials.find((m) => m.id === this.selectedChildId);
            if (!child) {
                this.selectedChildId = null;
            } else {
                this.applyEditFields(child);
                return;
            }
        }
        if (this.selectedParentId) {
            const parent = this.materials.find((m) => m.id === this.selectedParentId);
            if (!parent) {
                this.selectedParentId = null;
                this.assignees = [];
            } else {
                this.applyEditFields(parent);
                this.loadAssignees(this.selectedParentId);
            }
        }
    }

    get accordionGroups() {
        const byId = new Map(this.materials.map((m) => [m.id, m]));
        const childrenByParent = new Map();

        for (const row of this.materials) {
            if (row.parentMaterialId) {
                if (!childrenByParent.has(row.parentMaterialId)) {
                    childrenByParent.set(row.parentMaterialId, []);
                }
                childrenByParent.get(row.parentMaterialId).push(row);
            }
        }

        const roots = this.materials.filter((row) => row.materialType === 'Course');
        const usedChildIds = new Set();
        const groups = roots.map((parent) => {
            const children = childrenByParent.get(parent.id) || [];
            children.forEach((c) => usedChildIds.add(c.id));
            return this.toGroup(parent, children);
        });

        for (const row of this.materials) {
            if (row.materialType === 'Course' || usedChildIds.has(row.id)) {
                continue;
            }
            if (!row.parentMaterialId || !byId.has(row.parentMaterialId)) {
                groups.push(this.toGroup(row, []));
            }
        }
        return groups;
    }

    toGroup(parent, children) {
        const expanded = this.expandedIds.has(parent.id);
        const selected = this.selectedParentId === parent.id && !this.selectedChildId;
        return {
            ...parent,
            children: children.map((c) => ({
                ...c,
                iconName: this.iconForType(c.materialType),
                childClass: `child-row${this.selectedChildId === c.id ? ' is-selected' : ''}`,
                metaLabel: [c.materialType, c.activeLabel, c.durationLabel].join(' | ')
            })),
            childCountLabel: `${children.length} item${children.length === 1 ? '' : 's'}`,
            assignmentLabel: `${parent.assignmentCount || 0} assigned`,
            parentMetaLabel: [
                parent.materialType,
                parent.activeLabel,
                `${children.length} item${children.length === 1 ? '' : 's'}`,
                `${parent.assignmentCount || 0} assigned`
            ].join(' | '),
            expanded,
            selected,
            groupClass: `accordion-item${selected ? ' is-selected' : ''}${expanded ? ' is-expanded' : ''}`,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            iconName: this.iconForType(parent.materialType),
            hasChildren: children.length > 0
        };
    }

    get hasGroups() {
        return this.accordionGroups.length > 0;
    }

    get selectedParent() {
        return this.selectedParentId
            ? this.materials.find((m) => m.id === this.selectedParentId) || null
            : null;
    }

    get selectedChild() {
        return this.selectedChildId
            ? this.materials.find((m) => m.id === this.selectedChildId) || null
            : null;
    }

    get selectedItem() {
        return this.selectedChild || this.selectedParent;
    }

    get hasSelection() {
        return !!this.selectedItem;
    }

    get isEditingChild() {
        return !!this.selectedChild;
    }

    get isEditingParent() {
        return !!this.selectedParent && !this.selectedChild;
    }

    get isQuizSelected() {
        return this.selectedItem?.materialType === 'Quiz';
    }

    get showUrlField() {
        const type = this.editMaterialType || this.selectedItem?.materialType;
        return type === 'Video' || type === 'PDF' || type === 'Lesson';
    }

    get showTypePicker() {
        return this.isEditingChild;
    }

    get detailHeading() {
        if (this.isEditingChild) {
            return 'Edit child material';
        }
        if (this.isEditingParent) {
            return 'Edit parent course';
        }
        return 'Edit material';
    }

    get hasAssignees() {
        return this.assignees.length > 0;
    }

    get assigneeRows() {
        return this.assignees.map((row) => ({
            ...row,
            progressLabel: `${Math.round(row.progress || 0)}%`,
            scoreLabel: row.score == null ? '-' : `${row.score}%`
        }));
    }

    get isNewDisabled() {
        return this.isSaving || !this.newTitle?.trim();
    }

    get isAssignDisabled() {
        return this.isSaving || !this.assignUserId || !this.selectedParentId;
    }

    get isSaveDisabled() {
        return this.isSaving || !this.editTitle?.trim();
    }

    iconForType(type) {
        switch (type) {
            case 'Course':
                return 'utility:education';
            case 'Video':
                return 'utility:video';
            case 'PDF':
                return 'utility:file';
            case 'Quiz':
                return 'utility:question';
            case 'Lesson':
                return 'utility:knowledge_base';
            default:
                return 'utility:knowledge_base';
        }
    }

    applyEditFields(item) {
        this.editTitle = item.title || '';
        this.editDescription = item.description || '';
        this.editActive = item.isActive === true;
        this.editDuration = item.duration;
        this.editMaterialType = item.materialType || 'Course';
        this.editMaterialUrl = item.materialUrl || '';
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleTypeFilter(event) {
        this.typeFilter = event.detail.value;
    }

    handleActiveFilter(event) {
        this.activeFilter = event.detail.value;
    }

    handleToggleExpand(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.expandedIds);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        this.expandedIds = next;
    }

    handleSelectParent(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedParentId = id;
        this.selectedChildId = null;
        const parent = this.materials.find((m) => m.id === id);
        if (!parent) {
            return;
        }
        this.applyEditFields(parent);
        this.assignUserId = null;
        const next = new Set(this.expandedIds);
        next.add(id);
        this.expandedIds = next;
        this.loadAssignees(id);
    }

    handleSelectChild(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const child = this.materials.find((m) => m.id === id);
        if (!child) {
            return;
        }
        this.selectedChildId = id;
        this.selectedParentId = child.parentMaterialId || this.selectedParentId;
        this.applyEditFields(child);
        if (this.selectedParentId) {
            const next = new Set(this.expandedIds);
            next.add(this.selectedParentId);
            this.expandedIds = next;
            this.loadAssignees(this.selectedParentId);
        }
    }

    async loadAssignees(materialId) {
        this.assigneesLoading = true;
        try {
            this.assignees = await getAssignments({ materialId });
        } catch (error) {
            this.assignees = [];
            this.toast('Unable to load assignees', this.errorMessage(error), 'error');
        } finally {
            this.assigneesLoading = false;
        }
    }

    handleEditTitle(event) {
        this.editTitle = event.target.value;
    }

    handleEditDescription(event) {
        this.editDescription = event.target.value;
    }

    handleEditActive(event) {
        this.editActive = event.target.checked;
    }

    handleEditDuration(event) {
        const value = event.target.value;
        this.editDuration = value === '' || value == null ? null : Number(value);
    }

    handleEditMaterialType(event) {
        this.editMaterialType = event.detail.value;
    }

    handleEditMaterialUrl(event) {
        this.editMaterialUrl = event.target.value;
    }

    async handleSaveItem() {
        const item = this.selectedItem;
        if (!item || !this.editTitle?.trim()) {
            return;
        }
        this.isSaving = true;
        try {
            await updateMaterial({
                materialId: item.id,
                title: this.editTitle.trim(),
                description: this.editDescription,
                active: this.editActive,
                duration: this.editDuration,
                materialType: this.editMaterialType,
                materialUrl: this.editMaterialUrl
            });
            await refreshApex(this.wiredResult);
            this.toast('Saved', 'Material updated.', 'success');
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenRecord() {
        const item = this.selectedItem;
        if (item) {
            this.navigateToMaterial(item.id);
        }
    }

    handleAssignUser(event) {
        this.assignUserId = event.detail.recordId;
    }

    async handleAssign() {
        if (!this.assignUserId || !this.selectedParentId) {
            return;
        }
        this.isSaving = true;
        try {
            const result = await assignToUser({
                userId: this.assignUserId,
                materialId: this.selectedParentId
            });
            this.assignUserId = null;
            const picker = this.template.querySelector('lightning-record-picker');
            if (picker) {
                picker.clearSelection();
            }
            await refreshApex(this.wiredResult);
            await this.loadAssignees(this.selectedParentId);
            this.toast(
                'Assigned',
                `Created/ensured ${result.instanceCount} learning instance(s).`,
                'success'
            );
        } catch (error) {
            this.toast('Assign failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleNew() {
        this.newTitle = '';
        this.newType = 'Course';
        this.showNewModal = true;
    }

    handleNewTitle(event) {
        this.newTitle = event.target.value;
    }

    handleNewType(event) {
        this.newType = event.detail.value;
    }

    handleCloseNew() {
        this.showNewModal = false;
    }

    async handleCreate() {
        const title = this.newTitle?.trim();
        if (!title) {
            return;
        }
        this.isSaving = true;
        try {
            const parentId =
                this.newType === 'Course' ? null : this.selectedParentId || null;
            const materialId = await createMaterial({
                title,
                materialType: this.newType,
                parentMaterialId: parentId,
                active: true
            });
            this.showNewModal = false;
            await refreshApex(this.wiredResult);
            if (this.newType === 'Course') {
                this.selectedParentId = materialId;
                this.selectedChildId = null;
            } else {
                this.selectedChildId = materialId;
                if (parentId) {
                    this.selectedParentId = parentId;
                }
            }
            this.toast('Material created', 'Ready to edit.', 'success');
        } catch (error) {
            this.toast('Create failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    navigateToMaterial(id) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: id,
                objectApiName: 'Learning_Material__c',
                actionName: 'view'
            }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}