import { LightningElement, api } from 'lwc';
import {
    applyCalculatedValues,
    matrixRatingDisplay,
    classificationDisplay,
    productMatrixRatingDisplay,
    numberDonutVisual
} from 'c/ratingCalculations';
import { flattenLayoutFields, parseLayoutJson } from 'c/ratingLayoutUtils';

const DOT_COLORS = ['#2e844a', '#8bc34a', '#ffb75d', '#fe9339', '#ea001e'];

function fieldKey(field) {
    return `${field.objectApiName}.${field.fieldApiName}`;
}

function formatRelativeDate(value) {
    if (!value) {
        return 'Not set';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return String(value);
    }
    const diffDays = Math.round((Date.now() - date.getTime()) / 86400000);
    if (diffDays <= 0) {
        return 'Today';
    }
    if (diffDays === 1) {
        return 'A day ago';
    }
    return `${diffDays} days ago`;
}

function defaultPicklistOptions(fieldApiName) {
    if (fieldApiName === 'KOL_In_What__c') {
        return [
            { label: 'High Prescriber', value: 'High Prescriber' },
            { label: 'Key Scientific Leader', value: 'Key Scientific Leader' }
        ];
    }
    if (fieldApiName === 'KOL_Profile__c') {
        return [
            { label: 'Multiple High Prescribers', value: 'Multiple High Prescribers' },
            { label: 'Department Chiefs', value: 'Department Chiefs' },
            { label: 'Academic Leaders', value: 'Academic Leaders' },
            { label: 'Mixed Influencers', value: 'Mixed Influencers' }
        ];
    }
    return [];
}

function resolveAccountVariant(layoutJson) {
    const layout = parseLayoutJson(layoutJson || '{}');
    return layout.accountVariant || 'HCP';
}

function defaultDotOptions(fieldApiName) {
    if (fieldApiName === 'Potential__c') {
        return [
            { label: 'A', value: 'A' },
            { label: 'B', value: 'B' },
            { label: 'C', value: 'C' }
        ];
    }
    if (fieldApiName === 'Penetration__c') {
        return [
            { label: '1', value: '1' },
            { label: '2', value: '2' },
            { label: '3', value: '3' }
        ];
    }
    if (fieldApiName === 'Adoption__c' || fieldApiName === 'Loyalty__c') {
        return [
            { label: 'H', value: 'H' },
            { label: 'M', value: 'M' },
            { label: 'L', value: 'L' }
        ];
    }
    if (fieldApiName === 'Target_Visit_Frequency__c') {
        return [
            { label: 'Weekly', value: 'Weekly' },
            { label: 'Bi-Weekly', value: 'Bi-Weekly' },
            { label: 'Monthly', value: 'Monthly' },
            { label: 'Quarterly', value: 'Quarterly' },
            { label: 'As Needed', value: 'As Needed' }
        ];
    }
    return [];
}

function decorateField(field, values, readOnly) {
    const key = fieldKey(field);
    let resolvedField = field;
    if (field.fieldApiName === 'KOL_In_What__c') {
        resolvedField = {
            ...field,
            label: 'KOL Reason',
            widget: 'picklist',
            options: field.options?.length ? field.options : defaultPicklistOptions('KOL_In_What__c')
        };
    } else if (field.fieldApiName === 'KOL_Profile__c') {
        resolvedField = {
            ...field,
            label: 'KOL Profile',
            widget: 'picklist',
            options: field.options?.length ? field.options : defaultPicklistOptions('KOL_Profile__c')
        };
    }
    const rawValue = values[resolvedField.fieldApiName] ?? values[key] ?? '';
    const isCalculated = resolvedField.widget === 'calculatedBadge' || resolvedField.readOnly === true;
    const isToggle = resolvedField.widget === 'toggle';
    const isNumberDonut = resolvedField.widget === 'numberDonut';
    const isDotScale = resolvedField.widget === 'dotScale';
    const isPicklist = resolvedField.widget === 'picklist';
    const isDateRelative = resolvedField.widget === 'dateRelative';
    const isTextValue =
        resolvedField.widget === 'textValue' ||
        (!isToggle && !isNumberDonut && !isDotScale && !isPicklist && !isDateRelative && !isCalculated);

    let displayValue = rawValue;
    if (resolvedField.fieldApiName === 'Matrix_Rating__c') {
        displayValue =
            matrixRatingDisplay(values.Potential__c, values.Penetration__c) || rawValue;
    } else if (resolvedField.fieldApiName === 'Classification__c') {
        displayValue =
            classificationDisplay(values.Potential__c, values.Penetration__c) || rawValue;
    } else if (resolvedField.fieldApiName === 'Product_Matrix_Rating__c') {
        displayValue =
            productMatrixRatingDisplay(values.Adoption__c, values.Loyalty__c) || rawValue;
    }

    const numericValue = Number(displayValue);
    const isZero = !Number.isNaN(numericValue) && numericValue === 0;
    const picklistOptions = resolvedField.options?.length
        ? resolvedField.options
        : isPicklist
          ? defaultPicklistOptions(resolvedField.fieldApiName)
          : defaultDotOptions(resolvedField.fieldApiName);
    const options = picklistOptions.map((opt, index) => ({
        label: opt.label,
        value: opt.value,
        dotClass:
            opt.value === displayValue
                ? 'rating-dot rating-dot-active'
                : 'rating-dot',
        color: DOT_COLORS[index % DOT_COLORS.length]
    }));

    const donutVisual = isNumberDonut ? numberDonutVisual(displayValue) : null;
    const donutPercent = donutVisual?.percent ?? 35;
    const donutStyle = donutVisual
        ? `--donut-percent:${donutPercent};--donut-color:${donutVisual.color}`
        : `--donut-percent:${donutPercent}`;
    const donutValueStyle = donutVisual ? `color:${donutVisual.valueColor}` : '';

    return {
        ...resolvedField,
        key,
        rawValue: isToggle ? displayValue === true || displayValue === 'true' : displayValue,
        displayValue: isToggle
            ? displayValue === true || displayValue === 'true'
                ? 'On'
                : 'Off'
            : isDateRelative
              ? formatRelativeDate(displayValue)
              : String(displayValue ?? ''),
        isToggle,
        isNumberDonut,
        isDotScale,
        isPicklist,
        picklistOptions: isPicklist ? picklistOptions : [],
        isDateRelative,
        isTextValue,
        isCalculated,
        isReadOnly: readOnly || isCalculated,
        isZero,
        options: options.map((opt) => ({
            ...opt,
            dotStyle: `--dot-color:${opt.color}`
        })),
        donutPercent,
        donutStyle,
        donutValueStyle,
        cardClass: isCalculated ? 'rating-card rating-card-calculated' : 'rating-card',
        valueClass: isZero ? 'rating-value rating-value-alert' : 'rating-value'
    };
}

export default class RatingFormRenderer extends LightningElement {
    @api readOnly = false;
    @api showSectionHeaders;
    @api showSaveButton = false;
    @api isSaving = false;
    @api sectionFilter;

    values = {};
    _valuesJson = '{}';
    accountVariant = 'HCP';

    @api
    get valuesJson() {
        return this._valuesJson;
    }

    set valuesJson(value) {
        this._valuesJson = value || '{}';
        this.syncValues();
    }

    @api
    set layoutJson(value) {
        this._layoutJson = value;
        this.accountVariant = resolveAccountVariant(value);
        if (this._valuesJson) {
            this.syncValues();
        }
    }

    get layoutJson() {
        return this._layoutJson;
    }

    _layoutJson;
    _numberInputTimer;

    connectedCallback() {
        if (this._layoutJson) {
            this.accountVariant = resolveAccountVariant(this._layoutJson);
        }
        this.syncValues();
    }

    disconnectedCallback() {
        if (this._numberInputTimer) {
            clearTimeout(this._numberInputTimer);
        }
    }

    @api
    getValues() {
        return { ...this.values };
    }

    @api
    flushEditableValues() {
        const nextValues = { ...this.values };

        this.template.querySelectorAll('lightning-input[data-field]').forEach((input) => {
            const fieldApiName = input.dataset.field;
            if (!fieldApiName || input.type !== 'number') {
                return;
            }
            const value = input.value;
            nextValues[fieldApiName] = value === '' || value === null ? null : Number(value);
        });

        this.values = applyCalculatedValues([], nextValues, this.accountVariant);
        return this.getValues();
    }

    syncValues() {
        if (!this._valuesJson) {
            this.values = applyCalculatedValues([], {}, this.accountVariant);
            return;
        }
        try {
            const parsed = JSON.parse(this._valuesJson);
            this.values = applyCalculatedValues([], parsed, this.accountVariant);
        } catch (e) {
            this.values = {};
        }
    }

    get resolvedShowSectionHeaders() {
        return this.showSectionHeaders !== false;
    }

    get hasFields() {
        return this.renderSections.some((section) => section.fields.length > 0);
    }

    get renderSections() {
        const layout = parseLayoutJson(this.layoutJson || '{}');
        const flat = flattenLayoutFields(layout);
        const sectionMap = {};
        flat.forEach((field) => {
            if (field.hidden === true) {
                return;
            }
            if (field.fieldApiName === 'KOL_In_What__c') {
                const isKol =
                    this.values.Is_KOL__c === true || this.values.Is_KOL__c === 'true';
                if (!isKol) {
                    return;
                }
            }
            if (field.fieldApiName === 'KOL_Profile__c') {
                const hasKols =
                    this.values.Has_KOLs__c === true || this.values.Has_KOLs__c === 'true';
                if (!hasKols) {
                    return;
                }
            }
            if (!sectionMap[field.sectionKey]) {
                sectionMap[field.sectionKey] = {
                    key: field.sectionKey,
                    label: field.sectionLabel,
                    fields: []
                };
            }
            sectionMap[field.sectionKey].fields.push(
                decorateField(field, this.values, this.readOnly)
            );
        });
        let sections = Object.values(sectionMap).filter((section) => section.fields.length > 0);
        if (this.sectionFilter) {
            const allowed = this.sectionFilter.split(',').map((key) => key.trim());
            sections = sections.filter((section) => allowed.includes(section.key));
        }
        return sections;
    }

    handleToggle(event) {
        if (this.readOnly) {
            return;
        }
        const fieldApiName = event.target.dataset.field;
        this.values = applyCalculatedValues([], {
            ...this.values,
            [fieldApiName]: event.target.checked
        }, this.accountVariant);
        this.dispatchValueChange(fieldApiName);
    }

    handleInputChange(event) {
        if (this.readOnly) {
            return;
        }
        const fieldApiName = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        this.values = applyCalculatedValues([], {
            ...this.values,
            [fieldApiName]: value
        }, this.accountVariant);
        this.dispatchValueChange(fieldApiName);
    }

    handleNumberInput(event) {
        if (this.readOnly) {
            return;
        }
        const fieldApiName = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        if (this._numberInputTimer) {
            clearTimeout(this._numberInputTimer);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._numberInputTimer = setTimeout(() => {
            this._numberInputTimer = null;
            this.values = applyCalculatedValues([], {
                ...this.values,
                [fieldApiName]: value
            }, this.accountVariant);
            this.dispatchValueChange(fieldApiName);
        }, 400);
    }

    handleDotSelect(event) {
        if (this.readOnly) {
            return;
        }
        const fieldApiName = event.currentTarget.dataset.field;
        const value = event.currentTarget.dataset.value;
        this.values = applyCalculatedValues([], {
            ...this.values,
            [fieldApiName]: value
        }, this.accountVariant);
        this.dispatchValueChange(fieldApiName);
    }

    dispatchValueChange(changedField) {
        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: {
                    values: this.getValues(),
                    changedField
                }
            })
        );
    }

    handleSave() {
        this.dispatchEvent(new CustomEvent('save', { detail: { values: this.getValues() } }));
    }
}