import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRatingCaptureContext from '@salesforce/apex/ClmMetricsController.getRatingCaptureContext';
import saveVisitRatings from '@salesforce/apex/ClmMetricsController.saveVisitRatings';
import { flattenLayoutFields } from 'c/ratingLayoutUtils';
import { getRatingContext, putRatingContext } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

export default class ClmRatingsCapture extends LightningElement {
    @api sessionId;
    @api visitId;

    layoutId;
    layoutJson;
    valuesJson = '{}';
    alignedProducts = [];
    productValuesById = {};
    productShowSectionHeaders = false;
    isSaving = false;
    wiredContextResult;

    connectedCallback() {
        if (isOfflineMode() && this.visitId) {
            this.loadCachedContext();
        }
    }

    async loadCachedContext() {
        const data = await getRatingContext(this.visitId);
        if (data) {
            this.applyContext(data);
        }
    }

    applyContext(data) {
        this.layoutId = data.layoutId;
        this.layoutJson = data.layoutJson;
        this.valuesJson = data.valuesJson || '{}';
        this.alignedProducts = (data.alignedProducts || []).map((product) => ({
            ...product,
            valuesJson: product.valuesJson || '{}'
        }));
        this.productValuesById = {};
        this.alignedProducts.forEach((product) => {
            this.productValuesById[product.product2Id] = product.valuesJson;
        });
    }

    @wire(getRatingCaptureContext, { visitId: '$visitId', sessionId: '$sessionId' })
    wiredContext(result) {
        this.wiredContextResult = result;
        const data = result.data;
        if (!data) {
            return;
        }
        this.applyContext(data);
        if (this.visitId) {
            putRatingContext(this.visitId, data);
        }
    }

    get hasLayout() {
        return Boolean(this.layoutJson);
    }

    get hasAlignedProducts() {
        return this.alignedProducts.length > 0;
    }

    handleValueChange(event) {
        this.valuesJson = JSON.stringify(event.detail.values || {});
    }

    handleProductValueChange(event) {
        const productId = event.currentTarget.dataset.productId;
        if (!productId) {
            return;
        }
        this.productValuesById = {
            ...this.productValuesById,
            [productId]: JSON.stringify(event.detail.values || {})
        };
    }

    parseValuesJson(valuesJson) {
        try {
            return JSON.parse(valuesJson || '{}');
        } catch (e) {
            return {};
        }
    }

    normalizeKolValues(values) {
        if (!values) {
            return;
        }
        const hasMeaningfulValue = (value) => {
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
        };
        if (hasMeaningfulValue(values.KOL_In_What__c)) {
            values.Is_KOL__c = true;
            return;
        }
        if (values.Is_KOL__c === false || values.Is_KOL__c === 'false') {
            values.KOL_In_What__c = null;
        }
    }

    collectRendererValues(renderer, fallbackJson) {
        renderer?.flushEditableValues?.();
        const fallback = this.parseValuesJson(fallbackJson);
        const fromRenderer = renderer?.getValues?.() || {};
        return { ...fallback, ...fromRenderer };
    }

    buildFieldPayload(values, objectApiName) {
        const fields = flattenLayoutFields(this.layoutJson).filter(
            (field) => field.objectApiName === objectApiName
        );
        return fields
            .filter((field) => {
                const value = values[field.fieldApiName];
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
            })
            .map((field) => ({
                objectApiName: field.objectApiName,
                fieldApiName: field.fieldApiName,
                valueJson: JSON.stringify(values[field.fieldApiName])
            }));
    }

    async handleSave() {
        if (!this.visitId) {
            return;
        }

        const territoryRenderer = this.template.querySelector(
            'c-rating-form-renderer:not([data-product-id])'
        );
        const territoryValues = this.collectRendererValues(territoryRenderer, this.valuesJson);
        this.normalizeKolValues(territoryValues);

        const territoryPayload = this.buildFieldPayload(
            territoryValues,
            'Account_Territory_Fields__c'
        );
        const accountPayload = this.buildFieldPayload(territoryValues, 'Account');

        const productPayload = [];
        this.alignedProducts.forEach((product) => {
            const productRenderer = this.template.querySelector(
                `c-rating-form-renderer[data-product-id="${product.product2Id}"]`
            );
            const values = this.collectRendererValues(
                productRenderer,
                this.productValuesById[product.product2Id] || product.valuesJson || '{}'
            );
            productPayload.push(
                ...this.buildFieldPayload(values, 'Account_Territory_Product_Fields__c')
            );
        });

        const payload = [...accountPayload, ...territoryPayload, ...productPayload];

        this.isSaving = true;
        try {
            if (navigator.onLine && !isOfflineMode()) {
                await saveVisitRatings({
                    visitId: this.visitId,
                    sessionId: this.sessionId,
                    layoutId: this.layoutId,
                    values: payload
                });
            } else {
                await queueOfflineAction({
                    actionType: 'SAVE_VISIT_RATINGS',
                    clientSessionKey: this.sessionId,
                    visitId: this.visitId,
                    layoutId: this.layoutId,
                    ratingsJson: JSON.stringify(payload)
                });
            }
            this.dispatchEvent(new CustomEvent('saved'));
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Ratings saved',
                    message: 'Visit ratings captured.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}