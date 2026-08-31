import { LightningElement, api, wire } from 'lwc';
import getTerritoryProducts from '@salesforce/apex/VisitCallReportController.getTerritoryProducts';

const TOPIC_OPTIONS = [
    { label: 'Efficacy', value: 'Efficacy' },
    { label: 'Indication', value: 'Indication' },
    { label: 'Safety', value: 'Safety' },
    { label: 'Side Effects', value: 'Side Effects' },
    { label: 'Usage', value: 'Usage' }
];

const SENTIMENT_OPTIONS = [
    { label: 'Negative', value: 'Negative' },
    { label: 'Neutral', value: 'Neutral' },
    { label: 'Positive', value: 'Positive' }
];

const DETAIL_TYPE_OPTIONS = [
    { label: 'Detail', value: 'Detail' },
    { label: 'Reprint', value: 'Reprint' },
    { label: 'Reminder', value: 'Reminder' }
];

export default class VisitProductDetailPanel extends LightningElement {
    @api visitId;
    @api disabled = false;

    _products = [];
    territoryProducts = [];
    activeBrandKeys = [];

    detailTypeOptions = DETAIL_TYPE_OPTIONS;
    sentimentOptions = SENTIMENT_OPTIONS;

    @api
    get products() {
        return this._products;
    }
    set products(value) {
        this._products = Array.isArray(value) ? value : [];
        this.syncActiveBrandsFromProducts();
    }

    @wire(getTerritoryProducts, { visitId: '$visitId' })
    wiredProducts({ data }) {
        if (data) {
            this.territoryProducts = data;
            this.syncActiveBrandsFromProducts();
        }
    }

    get detailTerritoryProducts() {
        const rows = this.territoryProducts || [];
        const detailRows = rows.filter((row) => row.productType === 'Detail');
        return detailRows.length > 0 ? detailRows : rows.filter((row) => row.productType !== 'Sample' && row.productType !== 'Brand Reminder');
    }

    get brandCatalog() {
        const byBrand = new Map();
        for (const row of this.detailTerritoryProducts) {
            const brandKey = this.resolveBrandKey(row);
            if (!byBrand.has(brandKey)) {
                byBrand.set(brandKey, {
                    brandKey,
                    brandId: row.parentProductId || row.productId,
                    brandName: row.brandName || row.productName,
                    imageUrl: row.imageUrl,
                    adoption: row.adoption,
                    loyalty: row.loyalty,
                    productMatrixRating: row.productMatrixRating,
                    targetVisitFrequency: row.targetVisitFrequency,
                    concentrations: []
                });
            }
            const brand = byBrand.get(brandKey);
            if (!brand.imageUrl && row.imageUrl) {
                brand.imageUrl = row.imageUrl;
            }
            if (!brand.adoption && row.adoption) {
                brand.adoption = row.adoption;
            }
            if (!brand.loyalty && row.loyalty) {
                brand.loyalty = row.loyalty;
            }
            if (!brand.productMatrixRating && row.productMatrixRating) {
                brand.productMatrixRating = row.productMatrixRating;
            }
            if (brand.targetVisitFrequency == null && row.targetVisitFrequency != null) {
                brand.targetVisitFrequency = row.targetVisitFrequency;
            }
            if (row.productType === 'Detail' || !row.productType) {
                brand.concentrations.push({
                    productId: row.productId,
                    productName: row.productName,
                    imageUrl: row.imageUrl,
                    strength: row.strength,
                    form: row.form,
                    parentProductId: row.parentProductId || brand.brandId,
                    brandName: row.brandName || brand.brandName,
                    productType: 'Detail',
                    label: this.formatConcentrationLabel(row)
                });
            }
        }
        return [...byBrand.values()].sort((a, b) =>
            String(a.brandName || '').localeCompare(String(b.brandName || ''))
        );
    }

    get brandCatalogByKey() {
        return new Map(this.brandCatalog.map((brand) => [brand.brandKey, brand]));
    }

    get sidebarBrands() {
        const selectedKeys = new Set(this.activeBrandKeys);
        return this.brandCatalog.map((brand) => ({
            ...brand,
            label: this.formatBrandLabel(brand),
            checked: selectedKeys.has(brand.brandKey)
        }));
    }

    get displayBrands() {
        const catalog = this.brandCatalogByKey;
        return (this.activeBrandKeys || [])
            .map((brandKey, index) => {
                const catalogBrand = catalog.get(brandKey);
                const brandRow = this.findBrandRow(brandKey);
                const concentrationRows = this.findConcentrationRows(brandKey);
                const selectedIds = new Set(concentrationRows.map((row) => row.productId));
                const concentrations = (catalogBrand?.concentrations || []).map((conc) => {
                    const saved = concentrationRows.find((row) => row.productId === conc.productId);
                    return {
                        ...conc,
                        checked: selectedIds.has(conc.productId),
                        notes: saved?.notes || '',
                        showNotes: selectedIds.has(conc.productId)
                    };
                });
                const brandName =
                    catalogBrand?.brandName || brandRow?.brandName || brandRow?.productName || 'Brand';
                const imageUrl = catalogBrand?.imageUrl || brandRow?.imageUrl;
                const feedbackSource = brandRow || concentrationRows[0];
                const detailType = brandRow?.detailType || feedbackSource?.detailType || 'Detail';
                const notes = brandRow?.notes || '';
                const messages = brandRow?.messages || (!brandRow ? feedbackSource?.messages || [] : []);
                const topicRows = TOPIC_OPTIONS.map((topic) => {
                    const msgIndex = messages.findIndex((msg) => msg.topic === topic.value);
                    const msg = msgIndex >= 0 ? messages[msgIndex] : null;
                    return {
                        key: `${brandKey}-${topic.value}`,
                        topic: topic.value,
                        label: topic.label,
                        selected: msgIndex >= 0,
                        sentiment: msg?.sentiment || 'Neutral',
                        response: msg?.response || ''
                    };
                });
                return {
                    brandKey,
                    brandId: catalogBrand?.brandId || brandRow?.productId,
                    brandName,
                    imageUrl,
                    key: `brand-${brandKey}`,
                    orderLabel: `#${index + 1}`,
                    canMoveUp: index > 0,
                    canMoveDown: index < this.activeBrandKeys.length - 1,
                    moveUpDisabled: index === 0 || this.disabled,
                    moveDownDisabled: index >= this.activeBrandKeys.length - 1 || this.disabled,
                    concentrations,
                    hasConcentrations: concentrations.length > 0,
                    selectedConcentrationCount: selectedIds.size,
                    detailType,
                    notes,
                    topicRows,
                    adoption: catalogBrand?.adoption,
                    loyalty: catalogBrand?.loyalty,
                    productMatrixRating: catalogBrand?.productMatrixRating
                };
            })
            .filter((brand) => brand.brandName);
    }

    get hasBrands() {
        return this.displayBrands.length > 0;
    }

    get hasSidebarBrands() {
        return this.sidebarBrands.length > 0;
    }

    isBrandRow(row) {
        return row?.productType === 'Brand';
    }

    resolveBrandKey(row) {
        if (!row) {
            return 'unknown';
        }
        if (row.productType === 'Brand') {
            return String(row.productId);
        }
        if (row.parentProductId) {
            return String(row.parentProductId);
        }
        if (row.brandName) {
            return `name:${row.brandName}`;
        }
        return String(row.productId);
    }

    findBrandRow(brandKey) {
        return (this._products || []).find(
            (row) => this.resolveBrandKey(row) === brandKey && this.isBrandRow(row)
        );
    }

    findConcentrationRows(brandKey) {
        return (this._products || []).filter(
            (row) => this.resolveBrandKey(row) === brandKey && !this.isBrandRow(row)
        );
    }

    formatConcentrationLabel(row) {
        if (row.strength) {
            return row.form ? `${row.strength} · ${row.form}` : row.strength;
        }
        return row.productName;
    }

    formatBrandLabel(brand) {
        const parts = [brand.brandName];
        if (brand.adoption) {
            parts.push(`Adoption: ${brand.adoption}`);
        }
        if (brand.loyalty) {
            parts.push(`Loyalty: ${brand.loyalty}`);
        }
        if (brand.productMatrixRating) {
            parts.push(`Matrix: ${brand.productMatrixRating}`);
        }
        if (brand.targetVisitFrequency != null) {
            parts.push(`Freq: ${brand.targetVisitFrequency}`);
        }
        const concCount = brand.concentrations?.length || 0;
        if (concCount > 0) {
            parts.push(`${concCount} conc.`);
        }
        return parts.join(' · ');
    }

    syncActiveBrandsFromProducts() {
        const keysFromProducts = [];
        const seen = new Set();
        for (const row of this._products || []) {
            const brandKey = this.resolveBrandKey(row);
            if (!seen.has(brandKey)) {
                seen.add(brandKey);
                keysFromProducts.push(brandKey);
            }
        }
        const preserved = (this.activeBrandKeys || []).filter((key) => {
            if (seen.has(key)) {
                return false;
            }
            return this.brandCatalogByKey.has(key);
        });
        this.activeBrandKeys = [...keysFromProducts, ...preserved];
    }

    buildBrandProductRow(brand, existing) {
        return {
            id: existing?.id,
            productId: brand.brandId,
            productName: brand.brandName,
            imageUrl: brand.imageUrl,
            productType: 'Brand',
            parentProductId: null,
            brandName: brand.brandName,
            strength: null,
            form: null,
            displayOrder: existing?.displayOrder || 1,
            detailType: existing?.detailType || 'Detail',
            notes: existing?.notes || '',
            messages: this.cloneMessages(existing?.messages || [])
        };
    }

    ensureBrandRow(products, brandKey) {
        const brand = this.brandCatalogByKey.get(brandKey);
        if (!brand) {
            return products;
        }
        const existing = products.find(
            (row) => this.resolveBrandKey(row) === brandKey && this.isBrandRow(row)
        );
        if (existing) {
            return products;
        }
        return [...products, this.buildBrandProductRow(brand, null)];
    }

    handleSidebarToggle(event) {
        if (this.disabled) {
            return;
        }
        const brandKey = event.target.dataset.brandKey;
        const checked = event.target.checked;
        if (!brandKey) {
            return;
        }
        if (checked) {
            if (!this.activeBrandKeys.includes(brandKey)) {
                this.activeBrandKeys = [...this.activeBrandKeys, brandKey];
            }
            const next = this.ensureBrandRow([...(this._products || [])], brandKey);
            this.emitChange(this.normalizeOrder(this.orderByActiveBrands(next)));
        } else {
            this.activeBrandKeys = this.activeBrandKeys.filter((key) => key !== brandKey);
            const next = (this._products || []).filter(
                (row) => this.resolveBrandKey(row) !== brandKey
            );
            this.emitChange(this.normalizeOrder(next));
        }
    }

    handleConcentrationToggle(event) {
        if (this.disabled) {
            return;
        }
        const brandKey = event.target.dataset.brandKey;
        const productId = event.target.dataset.productId;
        const checked = event.target.checked;
        if (!brandKey || !productId) {
            return;
        }

        const brand = this.brandCatalogByKey.get(brandKey);
        const concentration = (brand?.concentrations || []).find(
            (row) => row.productId === productId
        );
        if (!concentration) {
            return;
        }

        let next = this.ensureBrandRow([...(this._products || [])], brandKey);
        if (checked) {
            if (next.some((row) => row.productId === productId)) {
                return;
            }
            next = [
                ...next,
                {
                    productId: concentration.productId,
                    productName: concentration.productName,
                    imageUrl: concentration.imageUrl,
                    productType: 'Detail',
                    parentProductId: concentration.parentProductId || brand.brandId,
                    brandName: concentration.brandName,
                    strength: concentration.strength,
                    form: concentration.form,
                    displayOrder: next.length + 1,
                    detailType: 'Detail',
                    notes: '',
                    messages: []
                }
            ];
        } else {
            next = next.filter((row) => row.productId !== productId);
        }
        this.emitChange(this.normalizeOrder(this.orderByActiveBrands(next)));
    }

    handleConcentrationNotesChange(event) {
        if (this.disabled) {
            return;
        }
        const productId = event.target.dataset.productId;
        const value = event.detail.value;
        const next = (this._products || []).map((row) =>
            row.productId === productId ? { ...row, notes: value } : row
        );
        this.emitChange(next);
    }

    handleRemoveBrand(event) {
        const brandKey = event.currentTarget.dataset.brandKey;
        this.activeBrandKeys = this.activeBrandKeys.filter((key) => key !== brandKey);
        const next = (this._products || []).filter(
            (row) => this.resolveBrandKey(row) !== brandKey
        );
        this.emitChange(this.normalizeOrder(next));
    }

    handleMoveBrand(event) {
        if (this.disabled) {
            return;
        }
        const brandKey = event.currentTarget.dataset.brandKey;
        const direction = event.currentTarget.dataset.direction;
        const list = [...(this.activeBrandKeys || [])];
        const index = list.indexOf(brandKey);
        if (index < 0) {
            return;
        }
        const swapIndex = direction === 'up' ? index - 1 : index + 1;
        if (swapIndex < 0 || swapIndex >= list.length) {
            return;
        }
        [list[index], list[swapIndex]] = [list[swapIndex], list[index]];
        this.activeBrandKeys = list;
        this.emitChange(this.normalizeOrder(this.orderByActiveBrands(this._products || [])));
    }

    updateBrandRow(brandKey, updater) {
        let next = this.ensureBrandRow([...(this._products || [])], brandKey);
        next = next.map((row) => {
            if (this.resolveBrandKey(row) === brandKey && this.isBrandRow(row)) {
                return updater(row);
            }
            return row;
        });
        this.emitChange(this.normalizeOrder(this.orderByActiveBrands(next)));
    }

    handleDetailChange(event) {
        const brandKey = event.target.dataset.brandKey;
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.updateBrandRow(brandKey, (row) => ({ ...row, [field]: value }));
    }

    handleTopicToggle(event) {
        const brandKey = event.target.dataset.brandKey;
        const topic = event.target.dataset.topic;
        const checked = event.target.checked;
        this.updateBrandRow(brandKey, (row) => {
            let messages = [...(row.messages || [])];
            const existingIndex = messages.findIndex((msg) => msg.topic === topic);
            if (checked && existingIndex < 0) {
                messages.push({ topic, sentiment: 'Neutral', response: '' });
            } else if (!checked && existingIndex >= 0) {
                messages = messages.filter((msg) => msg.topic !== topic);
            }
            return { ...row, messages };
        });
    }

    handleSentimentChange(event) {
        const brandKey = event.currentTarget.dataset.brandKey;
        const topic = event.currentTarget.dataset.topic;
        const sentiment = event.currentTarget.dataset.sentiment;
        this.updateBrandRow(brandKey, (row) => ({
            ...row,
            messages: (row.messages || []).map((msg) =>
                msg.topic === topic ? { ...msg, sentiment } : msg
            )
        }));
    }

    handleResponseChange(event) {
        const brandKey = event.target.dataset.brandKey;
        const topic = event.target.dataset.topic;
        const value = event.detail.value;
        this.updateBrandRow(brandKey, (row) => ({
            ...row,
            messages: (row.messages || []).map((msg) =>
                msg.topic === topic ? { ...msg, response: value } : msg
            )
        }));
    }

    orderByActiveBrands(products) {
        const brandOrder = new Map(
            (this.activeBrandKeys || []).map((key, index) => [key, index])
        );
        return [...(products || [])].sort((a, b) => {
            const aKey = this.resolveBrandKey(a);
            const bKey = this.resolveBrandKey(b);
            const aOrder = brandOrder.has(aKey) ? brandOrder.get(aKey) : Number.MAX_SAFE_INTEGER;
            const bOrder = brandOrder.has(bKey) ? brandOrder.get(bKey) : Number.MAX_SAFE_INTEGER;
            if (aOrder !== bOrder) {
                return aOrder - bOrder;
            }
            // Brand row first, then concentrations.
            const aBrand = this.isBrandRow(a) ? 0 : 1;
            const bBrand = this.isBrandRow(b) ? 0 : 1;
            if (aBrand !== bBrand) {
                return aBrand - bBrand;
            }
            return String(a.productName || '').localeCompare(String(b.productName || ''));
        });
    }

    normalizeOrder(products) {
        return products.map((row, index) => ({
            ...row,
            displayOrder: index + 1
        }));
    }

    cloneMessages(messages) {
        return (messages || []).map((msg) => ({
            topic: msg.topic,
            sentiment: msg.sentiment || 'Neutral',
            response: msg.response || ''
        }));
    }

    emitChange(products) {
        this.dispatchEvent(
            new CustomEvent('productschange', {
                detail: { products },
                bubbles: true,
                composed: true
            })
        );
    }
}