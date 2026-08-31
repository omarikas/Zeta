import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRatingLayouts from '@salesforce/apex/ClmAdminController.getRatingLayouts';
import saveRatingLayout from '@salesforce/apex/ClmAdminController.saveRatingLayout';
import deployRatingLayout from '@salesforce/apex/ClmAdminController.deployRatingLayout';
import getRatingFieldCatalog from '@salesforce/apex/ClmAdminController.getRatingFieldCatalog';
import getRatingLayoutPreviewSample from '@salesforce/apex/ClmAdminController.getRatingLayoutPreviewSample';
import {
    parseLayoutJson,
    serializeLayout,
    getSectionCounts,
    getDefaultLayout,
    SECTION_ORDER,
    SECTION_LABELS
} from 'c/ratingLayoutUtils';

function fieldIdentity(field) {
    return `${field.objectApiName}.${field.fieldApiName}`;
}

function mergeCatalogOptions(layoutField, catalogField) {
    if (layoutField.options && layoutField.options.length) {
        return layoutField.options;
    }
    return catalogField?.options || [];
}

export default class ClmRatingLayoutEditor extends LightningElement {
    layouts = [];
    wiredResult;
    catalog = [];
    selectedLayoutId = null;
    selectedLayout = null;
    layoutState = getDefaultLayout();
    activeSection = 'account';
    searchTerm = '';
    previewValuesJson = '{}';

    @wire(getRatingLayouts)
    wiredLayouts(result) {
        this.wiredResult = result;
        this.layouts = (result.data || []).map((layout) => this.decorateLayoutRow(layout));
    }

    @wire(getRatingFieldCatalog)
    wiredCatalog({ data }) {
        this.catalog = data || [];
    }

    @wire(getRatingLayoutPreviewSample)
    wiredPreviewSample({ data }) {
        this.previewValuesJson = data || '{}';
    }

    get hasSelectedLayout() {
        return this.selectedLayout != null;
    }

    get isDeployed() {
        return this.selectedLayout?.status === 'Deployed';
    }

    get sectionTabs() {
        return SECTION_ORDER.map((key) => ({
            key,
            label: SECTION_LABELS[key],
            className: key === this.activeSection ? 'section-tab section-tab-active' : 'section-tab'
        }));
    }

    get catalogFields() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const selectedIds = new Set(
            (this.layoutState.sections[this.activeSection] || []).map((field) => fieldIdentity(field))
        );
        return this.catalog
            .filter((field) => field.sectionKey === this.activeSection)
            .filter((field) => {
                if (!term) {
                    return true;
                }
                return (
                    field.label.toLowerCase().includes(term) ||
                    field.fieldApiName.toLowerCase().includes(term)
                );
            })
            .map((field) => ({
                ...field,
                identity: fieldIdentity(field),
                checked: selectedIds.has(fieldIdentity(field))
            }));
    }

    get selectedSectionFields() {
        return (this.layoutState.sections[this.activeSection] || [])
            .slice()
            .sort((a, b) => (a.order || 0) - (b.order || 0))
            .map((field, index, list) => ({
                ...field,
                identity: fieldIdentity(field),
                canMoveUp: index > 0,
                canMoveDown: index < list.length - 1
            }));
    }

    get layoutJson() {
        return serializeLayout(this.layoutState);
    }

    handleNew() {
        this.selectedLayoutId = null;
        this.selectedLayout = {
            name: 'New Rating Layout',
            status: 'Draft'
        };
        this.layoutState = getDefaultLayout();
        this.activeSection = 'account';
    }

    handleSelect(event) {
        const layoutId = event.currentTarget.dataset.id;
        const layout = (this.wiredResult?.data || []).find((item) => item.id === layoutId);
        if (!layout) {
            return;
        }
        this.selectedLayoutId = layout.id;
        this.selectedLayout = { ...layout };
        this.layoutState = parseLayoutJson(layout.fieldsJson);
        this.activeSection = 'account';
        this.refreshLayoutListClasses();
    }

    handleNameChange(event) {
        this.selectedLayout = { ...this.selectedLayout, name: event.detail.value };
    }

    handleSectionTab(event) {
        this.activeSection = event.currentTarget.dataset.section;
        this.searchTerm = '';
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleCatalogToggle(event) {
        const identity = event.target.dataset.identity;
        const catalogField = this.catalog.find((field) => fieldIdentity(field) === identity);
        if (!catalogField) {
            return;
        }
        const sectionFields = [...(this.layoutState.sections[this.activeSection] || [])];
        const existingIndex = sectionFields.findIndex((field) => fieldIdentity(field) === identity);
        if (event.target.checked) {
            if (existingIndex >= 0) {
                return;
            }
            sectionFields.push({
                objectApiName: catalogField.objectApiName,
                fieldApiName: catalogField.fieldApiName,
                label: catalogField.label,
                widget: catalogField.widget,
                options: catalogField.options || [],
                readOnly: catalogField.readOnly === true,
                order: (sectionFields.length + 1) * 10
            });
            this.ensureCalculatedAtfFields(sectionFields, catalogField);
            this.ensureKolAtfFields(sectionFields, catalogField);
        } else if (existingIndex >= 0) {
            sectionFields.splice(existingIndex, 1);
        }
        this.layoutState = {
            ...this.layoutState,
            sections: {
                ...this.layoutState.sections,
                [this.activeSection]: sectionFields
            }
        };
    }

    ensureKolAtfFields(sectionFields, catalogField) {
        if (this.activeSection !== 'accountTerritory') {
            return;
        }
        if (catalogField.fieldApiName === 'Is_KOL__c') {
            this.addFieldIfMissing(
                sectionFields,
                'KOL_In_What__c',
                'KOL Reason',
                'picklist',
                6
            );
        }
    }

    addFieldIfMissing(sectionFields, fieldApiName, label, widget, order) {
        const exists = sectionFields.some(
            (field) =>
                field.fieldApiName === fieldApiName &&
                field.objectApiName === 'Account_Territory_Fields__c'
        );
        if (exists) {
            return;
        }
        sectionFields.push({
            objectApiName: 'Account_Territory_Fields__c',
            fieldApiName,
            label,
            widget,
            order
        });
    }

    ensureCalculatedAtfFields(sectionFields, catalogField) {
        if (this.activeSection !== 'accountTerritory') {
            return;
        }
        if (catalogField.fieldApiName === 'Potential__c' || catalogField.fieldApiName === 'Penetration__c') {
            this.addCalculatedIfMissing(sectionFields, 'Matrix_Rating__c', 'Matrix Rating', ['Potential__c', 'Penetration__c'], 30);
            this.addCalculatedIfMissing(sectionFields, 'Classification__c', 'Classification', ['Matrix_Rating__c'], 40);
        }
    }

    addCalculatedIfMissing(sectionFields, fieldApiName, label, calculatedFrom, order) {
        const exists = sectionFields.some(
            (field) => field.fieldApiName === fieldApiName && field.objectApiName === 'Account_Territory_Fields__c'
        );
        if (exists) {
            return;
        }
        sectionFields.push({
            objectApiName: 'Account_Territory_Fields__c',
            fieldApiName,
            label,
            widget: 'calculatedBadge',
            calculatedFrom,
            readOnly: true,
            order
        });
    }

    handleRemoveField(event) {
        const identity = event.currentTarget.dataset.identity;
        const sectionFields = (this.layoutState.sections[this.activeSection] || []).filter(
            (field) => fieldIdentity(field) !== identity
        );
        this.updateSectionFields(sectionFields);
    }

    handleMoveField(event) {
        const identity = event.currentTarget.dataset.identity;
        const direction = event.currentTarget.dataset.direction;
        const sectionFields = [...(this.layoutState.sections[this.activeSection] || [])];
        const index = sectionFields.findIndex((field) => fieldIdentity(field) === identity);
        if (index < 0) {
            return;
        }
        const targetIndex = direction === 'up' ? index - 1 : index + 1;
        if (targetIndex < 0 || targetIndex >= sectionFields.length) {
            return;
        }
        const [moved] = sectionFields.splice(index, 1);
        sectionFields.splice(targetIndex, 0, moved);
        this.updateSectionFields(sectionFields);
    }

    updateSectionFields(sectionFields) {
        const reordered = sectionFields.map((field, index) => ({
            ...field,
            order: (index + 1) * 10,
            options: mergeCatalogOptions(
                field,
                this.catalog.find((item) => fieldIdentity(item) === fieldIdentity(field))
            )
        }));
        this.layoutState = {
            ...this.layoutState,
            sections: {
                ...this.layoutState.sections,
                [this.activeSection]: reordered
            }
        };
    }

    handlePreviewValueChange(event) {
        this.previewValuesJson = JSON.stringify(event.detail.values || {});
    }

    async handleSave() {
        if (!this.selectedLayout) {
            return;
        }
        const counts = getSectionCounts(this.layoutState);
        const total = counts.accountCount + counts.territoryCount + counts.productCount;
        if (total === 0) {
            this.toast('Add at least one field', 'Select fields from any rating section.', 'warning');
            return;
        }
        try {
            const saved = await saveRatingLayout({
                layout: {
                    ...this.selectedLayout,
                    fieldsJson: this.layoutJson,
                    accountCount: counts.accountCount,
                    territoryCount: counts.territoryCount,
                    productCount: counts.productCount
                }
            });
            this.selectedLayoutId = saved.id;
            this.selectedLayout = saved;
            this.layoutState = parseLayoutJson(saved.fieldsJson);
            await refreshApex(this.wiredResult);
            this.refreshLayoutListClasses();
            this.toast('Layout saved', saved.name, 'success');
        } catch (error) {
            this.toast('Save failed', error?.body?.message || error?.message, 'error');
        }
    }

    async handleDeploy() {
        if (!this.selectedLayout?.id) {
            await this.handleSave();
        }
        if (!this.selectedLayout?.id) {
            return;
        }
        try {
            await deployRatingLayout({ layoutId: this.selectedLayout.id });
            this.selectedLayout = { ...this.selectedLayout, status: 'Deployed' };
            await refreshApex(this.wiredResult);
            this.refreshLayoutListClasses();
            this.toast('Layout deployed', 'Field reps will see this form during visits.', 'success');
        } catch (error) {
            this.toast('Deploy failed', error?.body?.message || error?.message, 'error');
        }
    }

    decorateLayoutRow(layout) {
        const counts = getSectionCounts(layout.fieldsJson);
        return {
            ...layout,
            itemClass:
                layout.id === this.selectedLayoutId
                    ? 'layout-item layout-item-selected'
                    : 'layout-item',
            statusClass:
                layout.status === 'Deployed' ? 'status status-deployed' : 'status status-draft',
            countChips: [
                { key: 'account', label: `Account ${counts.accountCount || layout.accountCount || 0}` },
                {
                    key: 'territory',
                    label: `Territory ${counts.territoryCount || layout.territoryCount || 0}`
                },
                { key: 'product', label: `Product ${counts.productCount || layout.productCount || 0}` }
            ]
        };
    }

    refreshLayoutListClasses() {
        this.layouts = (this.wiredResult?.data || []).map((layout) => this.decorateLayoutRow(layout));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}