import { LightningElement, api, wire } from 'lwc';
import getTerritoryProducts from '@salesforce/apex/VisitCallReportController.getTerritoryProducts';

const DISPENSE_TYPES = new Set(['Sample', 'Brand Reminder']);

export default class VisitSampleGrid extends LightningElement {
    @api visitId;
    @api samples = [];
    @api attendees = [];
    @api disabled = false;
    @api scopedBrandIds = [];

    territoryProducts = [];

    @wire(getTerritoryProducts, { visitId: '$visitId' })
    wiredProducts({ data }) {
        if (data) {
            this.territoryProducts = data;
        }
    }

    get scopedBrandIdSet() {
        return new Set((this.scopedBrandIds || []).filter(Boolean).map((id) => String(id)));
    }

    get hasScopedBrands() {
        return this.scopedBrandIdSet.size > 0;
    }

    get addDisabled() {
        return this.disabled || !this.hasScopedBrands;
    }

    get productOptions() {
        const brandIds = this.scopedBrandIdSet;
        return (this.territoryProducts || [])
            .filter((row) => DISPENSE_TYPES.has(row.productType))
            .filter((row) => {
                if (brandIds.size === 0) {
                    return false;
                }
                return row.parentProductId && brandIds.has(String(row.parentProductId));
            })
            .map((row) => ({
                label: row.brandName
                    ? `${row.productName} (${row.brandName})`
                    : row.productName,
                value: row.productId,
                row
            }))
            .filter((opt, index, all) => all.findIndex((item) => item.value === opt.value) === index)
            .sort((a, b) => String(a.label || '').localeCompare(String(b.label || '')));
    }

    get displaySamples() {
        return (this.samples || []).map((row, index) => ({
            ...row,
            key: row.id || `sample-${index}`,
            imageUrl: row.imageUrl || this.resolveImageUrl(row)
        }));
    }

    resolveImageUrl(row) {
        if (!row.productId) {
            return null;
        }
        const match = (this.productOptions || []).find((opt) => opt.value === row.productId);
        return match?.row?.imageUrl || null;
    }

    get attendeeOptions() {
        return (this.attendees || []).map((row) => ({
            label: row.accountName,
            value: row.id || row.accountId
        }));
    }

    handleAddRow() {
        if (this.disabled || !this.hasScopedBrands) {
            return;
        }
        const next = [
            ...(this.samples || []),
            {
                productId: null,
                productName: '',
                imageUrl: null,
                visitAttendeeId: null,
                attendeeName: '',
                quantity: 1,
                lotNumber: '',
                sampleInventoryId: null
            }
        ];
        this.emitChange(next);
    }

    handleRemoveRow(event) {
        const index = Number(event.currentTarget.dataset.index);
        const next = (this.samples || []).filter((_, idx) => idx !== index);
        this.emitChange(next);
    }

    handleFieldChange(event) {
        const index = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const value = event.detail.value;
        const next = (this.samples || []).map((row, idx) => {
            if (idx !== index) {
                return row;
            }
            if (field === 'productId') {
                const product = (this.productOptions || []).find((opt) => opt.value === value);
                return {
                    ...row,
                    productId: value,
                    productName: product?.row?.productName || product?.label || '',
                    imageUrl: product?.row?.imageUrl || null,
                    sampleInventoryId: null,
                    lotNumber: '',
                    inventoryOnHand: null,
                    inventoryExpiry: null
                };
            }
            if (field === 'visitAttendeeId') {
                const attendee = (this.attendees || []).find(
                    (a) => (a.id || a.accountId) === value
                );
                return {
                    ...row,
                    visitAttendeeId: value,
                    attendeeName: attendee?.accountName
                };
            }
            if (field === 'quantity') {
                const qty = value === '' || value == null ? null : Number(value);
                return { ...row, quantity: qty };
            }
            return { ...row, [field]: value };
        });
        this.emitChange(next);
    }

    emitChange(samples) {
        this.dispatchEvent(
            new CustomEvent('sampleschange', {
                detail: { samples },
                bubbles: true,
                composed: true
            })
        );
    }
}