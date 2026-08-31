import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadAccountRatingContext from '@salesforce/apex/ClmMetricsController.loadAccountRatingContext';
import saveAccountRatings from '@salesforce/apex/ClmMetricsController.saveAccountRatings';
import validateAccountRatings from '@salesforce/apex/ClmMetricsController.validateAccountRatings';
import { flattenLayoutFields } from 'c/ratingLayoutUtils';
import { hasMeaningfulValue, mergeRatingValues } from 'c/ratingValueMerge';

const AUTO_SAVE_DEBOUNCE_MS = 200;
const SAVED_INDICATOR_MS = 2500;

const TOGGLE_FIELDS = new Set(['Is_KOL__c', 'Has_KOLs__c']);
const ATPF_SAVE_FIELDS = [
    'Rx_Per_Week__c',
    'Adoption__c',
    'Loyalty__c',
    'Target_Visit_Frequency__c',
    'Notes__c'
];

export default class AccountRatingsPanel extends LightningElement {
    _recordId;
    contextLoadToken = 0;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (this._recordId === value) {
            return;
        }
        this._recordId = value;
        if (value) {
            this.loadContext();
        }
    }

    layoutId;
    layoutJson;
    accountVariant = 'HCP';
    territory2Id;
    territoryValuesJson = '{}';
    alignedProducts = [];
    territoryName;
    isLoading = false;
    loadError;
    productValuesById = {};
    productShowSectionHeaders = false;
    ratingsRenderKey = 0;
    isValidityChecking = false;
    @track validityResult;
    saveStatus = 'idle';
    saveErrorMessage;
    _autoSaveTimer;
    _saveInFlight = false;
    _queuedSave;

    disconnectedCallback() {
        if (this._autoSaveTimer) {
            clearTimeout(this._autoSaveTimer);
        }
    }

    async loadContext() {
        if (!this._recordId) {
            return;
        }
        const token = ++this.contextLoadToken;
        this.isLoading = true;
        this.loadError = null;
        try {
            const data = await loadAccountRatingContext({ accountId: this._recordId });
            if (token === this.contextLoadToken) {
                this.applyContext(data);
            }
        } catch (error) {
            if (token === this.contextLoadToken) {
                this.loadError = error;
            }
        } finally {
            if (token === this.contextLoadToken) {
                this.isLoading = false;
            }
        }
    }

    applyContext(data, { bumpRenderKey = true } = {}) {
        this.layoutId = data.layoutId;
        this.layoutJson = data.layoutJson;
        this.accountVariant = data.accountVariant || 'HCP';
        this.territory2Id = data.territory2Id;
        this.territoryValuesJson = data.valuesJson || '{}';
        this.territoryName = data.territoryName;
        if (bumpRenderKey) {
            const renderKey = this.ratingsRenderKey + 1;
            this.ratingsRenderKey = renderKey;
            this.alignedProducts = (data.alignedProducts || []).map((product) => ({
                ...product,
                valuesJson: product.valuesJson || '{}',
                renderKey: `${product.product2Id}-${renderKey}`
            }));
        } else {
            this.alignedProducts = (data.alignedProducts || []).map((product) => ({
                ...product,
                valuesJson: product.valuesJson || '{}',
                renderKey: product.renderKey || `${product.product2Id}-${this.ratingsRenderKey}`
            }));
        }
        this.productValuesById = {};
        this.alignedProducts.forEach((product) => {
            this.productValuesById[product.product2Id] = product.valuesJson;
        });
    }

    get hasLayout() {
        return Boolean(this.layoutJson);
    }

    get errorMessage() {
        return this.loadError?.body?.message || this.loadError?.message || null;
    }

    get isHcoAccount() {
        return this.accountVariant === 'HCO';
    }

    get productSectionHeading() {
        return this.isHcoAccount ? 'Organization Product Ratings' : 'Account Product Ratings';
    }

    get territorySubtitle() {
        return this.territoryName
            ? `Ratings for your territory: ${this.territoryName}`
            : 'Ratings for your assigned territory';
    }

    get hasAlignedProducts() {
        return this.alignedProducts.length > 0;
    }

    get noProductsMessage() {
        return 'No products aligned to your territory. Ask your admin to align products in the Product Catalog.';
    }

    get validitySubtext() {
        return this.isHcoAccount
            ? 'Agentforce checks public online signals for this organization against your ratings.'
            : 'Agentforce checks public online signals for this HCP against your ratings.';
    }

    get hasValidityResult() {
        return Boolean(this.validityResult);
    }

    get showValidityFallbackBanner() {
        return this.validityResult?.usedFallback === true;
    }

    get validityReasons() {
        return (this.validityResult?.reasons || []).map((text, index) => ({
            key: `reason-${index}`,
            text
        }));
    }

    get validityScoreClass() {
        const score = this.validityResult?.validityScore ?? 0;
        let band = 'validity-score validity-score-low';
        if (score >= 80) {
            band = 'validity-score validity-score-high';
        } else if (score >= 50) {
            band = 'validity-score validity-score-medium';
        }
        if (this.validityResult?.usedFallback) {
            band += ' validity-score-muted';
        }
        return band;
    }

    get validitySourceLabel() {
        return this.validityResult?.usedFallback ? 'Offline estimate' : 'Powered by Agentforce';
    }

    get validitySourceChipClass() {
        return this.validityResult?.usedFallback
            ? 'validity-source-chip validity-source-fallback'
            : 'validity-source-chip validity-source-agentforce';
    }

    get showSaveStatus() {
        return this.saveStatus !== 'idle';
    }

    get saveStatusClass() {
        if (this.saveStatus === 'saving') {
            return 'save-status save-status-saving';
        }
        if (this.saveStatus === 'saved') {
            return 'save-status save-status-saved';
        }
        if (this.saveStatus === 'error') {
            return 'save-status save-status-error';
        }
        return 'save-status';
    }

    get saveStatusLabel() {
        if (this.saveStatus === 'saving') {
            return 'Saving…';
        }
        if (this.saveStatus === 'saved') {
            return 'Saved';
        }
        if (this.saveStatus === 'error') {
            return this.saveErrorMessage || 'Save failed';
        }
        return '';
    }

    handleTerritoryValueChange(event) {
        const values = event.detail.values || {};
        const changedField = event.detail.changedField;
        this.territoryValuesJson = JSON.stringify(values);
        this.scheduleAutoSave('territory', null, values, changedField);
    }

    handleProductValueChange(event) {
        const productId = event.currentTarget.dataset.productId;
        if (!productId) {
            return;
        }
        const values = event.detail.values || {};
        const changedField = event.detail.changedField;
        const valuesJson = JSON.stringify(values);
        this.productValuesById = {
            ...this.productValuesById,
            [productId]: valuesJson
        };
        this.alignedProducts = this.alignedProducts.map((product) =>
            product.product2Id === productId ? { ...product, valuesJson } : product
        );
        this.scheduleAutoSave('product', productId, values, changedField);
    }

    scheduleAutoSave(scope, productId, values, changedField) {
        if (this._autoSaveTimer) {
            clearTimeout(this._autoSaveTimer);
        }
        this._autoSaveTimer = setTimeout(() => {
            this._autoSaveTimer = null;
            this.persistChange(scope, productId, values, changedField);
        }, AUTO_SAVE_DEBOUNCE_MS);
    }

    getFieldsToPersistForChange(changedField) {
        if (!changedField) {
            return null;
        }
        if (this.isHcoAccount) {
            if (changedField === 'KOL_Profile__c') {
                return ['KOL_Profile__c', 'Has_KOLs__c'];
            }
            if (changedField === 'Has_KOLs__c') {
                return ['Has_KOLs__c', 'KOL_Profile__c'];
            }
            return [changedField];
        }
        if (changedField === 'KOL_In_What__c') {
            return ['KOL_In_What__c', 'Is_KOL__c'];
        }
        if (changedField === 'Is_KOL__c') {
            return ['Is_KOL__c', 'KOL_In_What__c'];
        }
        return [changedField];
    }

    async persistChange(scope, productId, values, changedField) {
        if (!this.recordId || this.isLoading || !this.hasLayout) {
            return;
        }

        if (this._saveInFlight) {
            this._queuedSave = { scope, productId, values, changedField };
            return;
        }

        const fieldsToPersist = this.getFieldsToPersistForChange(changedField);
        let accountPayload = [];
        let territoryPayload = [];
        let productRatings = [];

        if (scope === 'territory') {
            const territoryValues = mergeRatingValues(
                this.parseValuesJson(this.territoryValuesJson),
                values || {}
            );
            territoryPayload = this.buildAtfPayload(territoryValues, fieldsToPersist);
            accountPayload = this.buildAccountPayload(territoryValues, fieldsToPersist);
        } else if (scope === 'product' && productId) {
            const productValues = mergeRatingValues(
                this.parseValuesJson(this.productValuesById[productId]),
                values || {}
            );
            const valuesPayload = this.buildAtpfPayload(productValues, fieldsToPersist);
            if (valuesPayload.length === 0) {
                return;
            }
            productRatings = [
                {
                    product2Id: productId,
                    values: valuesPayload
                }
            ];
        } else {
            return;
        }

        const apexFieldInputs = this.prepareApexFieldInputs([
            ...accountPayload,
            ...territoryPayload
        ]);
        const apexProductRatings = productRatings.map((product) => ({
            product2Id: product.product2Id,
            values: this.prepareApexFieldInputs(product.values || [])
        }));

        const totalPayloadCount =
            apexFieldInputs.length +
            apexProductRatings.reduce((sum, product) => sum + product.values.length, 0);
        if (totalPayloadCount === 0) {
            this.saveStatus = 'error';
            this.saveErrorMessage = 'Could not prepare rating save payload. Hard refresh and try again.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: this.saveErrorMessage,
                    variant: 'error'
                })
            );
            return;
        }

        this._saveInFlight = true;
        this.saveStatus = 'saving';
        this.saveErrorMessage = null;

        try {
            await saveAccountRatings({
                accountId: this.recordId,
                layoutId: this.layoutId,
                territory2Id: this.territory2Id,
                fieldInputsJson: JSON.stringify(apexFieldInputs),
                productRatingsJson: JSON.stringify(apexProductRatings)
            });
            this.saveStatus = 'saved';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this.saveStatus === 'saved') {
                    this.saveStatus = 'idle';
                }
            }, SAVED_INDICATOR_MS);
        } catch (error) {
            this.saveStatus = 'error';
            this.saveErrorMessage = error?.body?.message || error?.message || 'Save failed';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: this.saveErrorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this._saveInFlight = false;
            if (this._queuedSave) {
                const queued = this._queuedSave;
                this._queuedSave = null;
                this.persistChange(
                    queued.scope,
                    queued.productId,
                    queued.values,
                    queued.changedField
                );
            }
        }
    }

    getTerritoryRenderer() {
        return this.template.querySelector('c-rating-form-renderer[data-territory-ratings]');
    }

    getProductRenderer(productId) {
        return this.template.querySelector(`c-rating-form-renderer[data-product-id="${productId}"]`);
    }

    readRendererValues(renderer, fallbackJson) {
        const fallback = this.parseValuesJson(fallbackJson);
        if (!renderer) {
            return fallback;
        }
        const liveValues = renderer.flushEditableValues?.() || renderer.getValues?.() || {};
        return mergeRatingValues(fallback, liveValues);
    }

    getEditableAtfFieldNames() {
        return flattenLayoutFields(this.layoutJson)
            .filter(
                (field) =>
                    field.objectApiName === 'Account_Territory_Fields__c' &&
                    field.hidden !== true &&
                    field.widget !== 'calculatedBadge' &&
                    field.readOnly !== true
            )
            .map((field) => field.fieldApiName);
    }

    getEditableAtpfFieldNames() {
        const layoutFields = flattenLayoutFields(this.layoutJson)
            .filter(
                (field) =>
                    field.objectApiName === 'Account_Territory_Product_Fields__c' &&
                    field.hidden !== true &&
                    field.widget !== 'calculatedBadge' &&
                    field.readOnly !== true
            )
            .map((field) => field.fieldApiName);
        return layoutFields.length > 0 ? layoutFields : ATPF_SAVE_FIELDS;
    }

    normalizeHcoKolValues(values) {
        if (!values) {
            return;
        }
        const hasKols = values.Has_KOLs__c === true || values.Has_KOLs__c === 'true';
        if (hasMeaningfulValue(values.KOL_Profile__c)) {
            values.Has_KOLs__c = true;
            return;
        }
        if (values.Has_KOLs__c === false || values.Has_KOLs__c === 'false') {
            values.KOL_Profile__c = null;
            return;
        }
        if (!hasKols) {
            delete values.KOL_Profile__c;
        }
    }

    normalizeKolValues(values) {
        if (!values) {
            return;
        }
        const isKol = values.Is_KOL__c === true || values.Is_KOL__c === 'true';
        if (hasMeaningfulValue(values.KOL_In_What__c)) {
            values.Is_KOL__c = true;
            return;
        }
        if (values.Is_KOL__c === false || values.Is_KOL__c === 'false') {
            values.KOL_In_What__c = null;
            return;
        }
        if (!isKol) {
            delete values.KOL_In_What__c;
        }
    }

    shouldIncludeFieldInPayload(fieldApiName, value, values) {
        if (TOGGLE_FIELDS.has(fieldApiName)) {
            return typeof value === 'boolean' || value === 'true' || value === 'false';
        }
        if (hasMeaningfulValue(value)) {
            return true;
        }
        if (fieldApiName === 'KOL_In_What__c' && (values.Is_KOL__c === false || values.Is_KOL__c === 'false')) {
            return true;
        }
        if (fieldApiName === 'KOL_Profile__c' && (values.Has_KOLs__c === false || values.Has_KOLs__c === 'false')) {
            return true;
        }
        return false;
    }

    prepareApexFieldInputs(rows) {
        const normalized = (rows || [])
            .filter(
                (row) =>
                    row &&
                    typeof row.objectApiName === 'string' &&
                    row.objectApiName.length > 0 &&
                    typeof row.fieldApiName === 'string' &&
                    row.fieldApiName.length > 0
            )
            .map((row) => ({
                objectApiName: row.objectApiName,
                fieldApiName: row.fieldApiName,
                valueJson: row.valueJson == null ? null : String(row.valueJson)
            }));
        return JSON.parse(JSON.stringify(normalized));
    }

    buildExplicitFieldPayload(values, objectApiName, fieldApiNames) {
        const payload = [];
        for (const fieldApiName of fieldApiNames) {
            if (!(fieldApiName in values)) {
                continue;
            }
            const value = values[fieldApiName];
            if (this.shouldIncludeFieldInPayload(fieldApiName, value, values)) {
                payload.push({
                    objectApiName: String(objectApiName),
                    fieldApiName: String(fieldApiName),
                    valueJson: JSON.stringify(value)
                });
            }
        }
        return payload;
    }

    resolvePayloadFieldNames(allFieldApiNames, fieldsToPersist) {
        if (!fieldsToPersist || fieldsToPersist.length === 0) {
            return allFieldApiNames;
        }
        const allowed = new Set(fieldsToPersist);
        return allFieldApiNames.filter((fieldApiName) => allowed.has(fieldApiName));
    }

    buildAtfPayload(values, fieldsToPersist = null) {
        const fieldApiNames = this.resolvePayloadFieldNames(
            this.getEditableAtfFieldNames(),
            fieldsToPersist
        );
        if (fieldApiNames.length === 0) {
            return [];
        }
        if (this.isHcoAccount) {
            this.normalizeHcoKolValues(values);
            const payload = this.buildExplicitFieldPayload(
                values,
                'Account_Territory_Fields__c',
                fieldApiNames
            );
            const hasKolProfile = payload.some((row) => row.fieldApiName === 'KOL_Profile__c');
            const hasHasKols = payload.some((row) => row.fieldApiName === 'Has_KOLs__c');
            if (hasKolProfile && !hasHasKols) {
                payload.push({
                    objectApiName: 'Account_Territory_Fields__c',
                    fieldApiName: 'Has_KOLs__c',
                    valueJson: 'true'
                });
            }
            return payload;
        }

        this.normalizeKolValues(values);
        const payload = this.buildExplicitFieldPayload(
            values,
            'Account_Territory_Fields__c',
            fieldApiNames
        );
        const hasKolReason = payload.some((row) => row.fieldApiName === 'KOL_In_What__c');
        const hasIsKol = payload.some((row) => row.fieldApiName === 'Is_KOL__c');
        if (hasKolReason && !hasIsKol) {
            payload.push({
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Is_KOL__c',
                valueJson: 'true'
            });
        }
        return payload;
    }

    buildAccountPayload(values, fieldsToPersist = null) {
        const fields = flattenLayoutFields(this.layoutJson).filter(
            (field) => field.objectApiName === 'Account'
        );
        const allowed = fieldsToPersist ? new Set(fieldsToPersist) : null;
        return fields
            .filter((field) => {
                if (allowed && !allowed.has(field.fieldApiName)) {
                    return false;
                }
                return hasMeaningfulValue(values[field.fieldApiName]);
            })
            .map((field) => ({
                objectApiName: field.objectApiName,
                fieldApiName: field.fieldApiName,
                valueJson: JSON.stringify(values[field.fieldApiName])
            }));
    }

    buildAtpfPayload(values, fieldsToPersist = null) {
        return this.buildExplicitFieldPayload(
            values,
            'Account_Territory_Product_Fields__c',
            this.resolvePayloadFieldNames(this.getEditableAtpfFieldNames(), fieldsToPersist)
        );
    }

    parseValuesJson(valuesJson) {
        try {
            return JSON.parse(valuesJson || '{}');
        } catch (e) {
            return {};
        }
    }

    hasMeaningfulRatingValues(values) {
        if (!values || typeof values !== 'object') {
            return false;
        }
        return Object.values(values).some((value) => {
            if (typeof value === 'boolean') {
                return true;
            }
            if (value === null || value === undefined) {
                return false;
            }
            if (typeof value === 'string') {
                return value.trim().length > 0;
            }
            return true;
        });
    }

    buildLiveRatingsPayload() {
        const territoryRenderer = this.getTerritoryRenderer();
        const territoryValues = this.readRendererValues(
            territoryRenderer,
            this.territoryValuesJson
        );

        const products = this.alignedProducts.map((product) => {
            const productRenderer = this.getProductRenderer(product.product2Id);
            const values = this.readRendererValues(
                productRenderer,
                this.productValuesById[product.product2Id] || product.valuesJson || '{}'
            );
            return {
                product2Id: product.product2Id,
                values
            };
        });

        return {
            territory: territoryValues,
            products
        };
    }

    hasRatingsForValidityCheck(livePayload) {
        if (this.hasMeaningfulRatingValues(livePayload.territory)) {
            return true;
        }
        return (livePayload.products || []).some((product) =>
            this.hasMeaningfulRatingValues(product.values)
        );
    }

    async handleCheckValidity() {
        if (!this.recordId) {
            return;
        }

        const livePayload = this.buildLiveRatingsPayload();
        if (!this.hasRatingsForValidityCheck(livePayload)) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Nothing to check',
                    message: 'Enter at least one rating before checking validity.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isValidityChecking = true;
        try {
            this.validityResult = await validateAccountRatings({
                accountId: this.recordId,
                liveRatingsJson: JSON.stringify(livePayload)
            });
        } catch (error) {
            this.validityResult = null;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validity check failed',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isValidityChecking = false;
        }
    }
}