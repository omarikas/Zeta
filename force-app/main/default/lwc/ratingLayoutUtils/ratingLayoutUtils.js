const SECTION_ORDER = ['account', 'accountTerritory', 'accountTerritoryProduct'];

const SECTION_LABELS = {
    account: 'Account Ratings',
    accountTerritory: 'Account Territory Ratings',
    accountTerritoryProduct: 'Account Territory Product Ratings'
};

const SECTION_LABELS_HCO = {
    account: 'Organization Ratings',
    accountTerritory: 'Organization Territory Ratings',
    accountTerritoryProduct: 'Organization Product Ratings'
};

const HCP_CLASSIFICATION_OPTIONS = [
    { label: 'A1', value: 'A1' },
    { label: 'A2', value: 'A2' },
    { label: 'A3', value: 'A3' },
    { label: 'B1', value: 'B1' },
    { label: 'B2', value: 'B2' },
    { label: 'B3', value: 'B3' },
    { label: 'C1', value: 'C1' },
    { label: 'C2', value: 'C2' },
    { label: 'C3', value: 'C3' }
];

const KOL_TYPE_OPTIONS = [
    { label: 'High Prescriber', value: 'High Prescriber' },
    { label: 'Key Scientific Leader', value: 'Key Scientific Leader' }
];

const SHARED_TERRITORY_FIELDS = [
    {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: 'HCP_Classification__c',
        label: 'Classification',
        widget: 'picklist',
        order: 10,
        options: HCP_CLASSIFICATION_OPTIONS
    },
    {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: 'Is_Speaker__c',
        label: 'Is Speaker',
        widget: 'toggle',
        order: 20
    },
    {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: 'Is_KOL__c',
        label: 'Is KOL',
        widget: 'toggle',
        order: 30
    },
    {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: 'KOL_In_What__c',
        label: 'KOL Type',
        widget: 'picklist',
        order: 40,
        options: KOL_TYPE_OPTIONS
    }
];

const SHARED_PRODUCT_FIELDS = [
    {
        objectApiName: 'Account_Territory_Product_Fields__c',
        fieldApiName: 'Potential__c',
        label: 'Potentiality',
        widget: 'numberDonut',
        order: 10
    },
    {
        objectApiName: 'Account_Territory_Product_Fields__c',
        fieldApiName: 'Penetration__c',
        label: 'Penetration',
        widget: 'numberDonut',
        order: 20
    }
];

const DEFAULT_HCO_LAYOUT = {
    version: 2,
    accountVariant: 'HCO',
    sections: {
        account: [],
        accountTerritory: SHARED_TERRITORY_FIELDS.map((field) => ({ ...field })),
        accountTerritoryProduct: SHARED_PRODUCT_FIELDS.map((field) => ({ ...field }))
    }
};

const DEFAULT_LAYOUT = {
    version: 2,
    accountVariant: 'HCP',
    sections: {
        account: [],
        accountTerritory: SHARED_TERRITORY_FIELDS.map((field) => ({ ...field })),
        accountTerritoryProduct: SHARED_PRODUCT_FIELDS.map((field) => ({ ...field }))
    }
};

function legacyFieldToV2(field) {
    const widget =
        field.widget ||
        (field.type === 'toggle'
            ? 'toggle'
            : field.type === 'number'
              ? 'numberDonut'
              : field.type === 'picklist'
                ? 'dotScale'
                : 'textValue');
    return {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: field.key || field.fieldApiName,
        label: field.label,
        widget,
        order: field.order || 10,
        options: field.options || [],
        readOnly: field.readOnly === true
    };
}

export function parseLayoutJson(json) {
    if (!json) {
        return JSON.parse(JSON.stringify(DEFAULT_LAYOUT));
    }
    try {
        const parsed = JSON.parse(json);
        if (parsed.version === 2 && parsed.sections) {
            return parsed;
        }
        if (parsed.layoutId && parsed.fields) {
            return {
                version: 2,
                sections: {
                    account: [],
                    accountTerritory: (parsed.fields || []).map(legacyFieldToV2),
                    accountTerritoryProduct: []
                }
            };
        }
        if (Array.isArray(parsed)) {
            return {
                version: 2,
                sections: {
                    account: [],
                    accountTerritory: parsed.map(legacyFieldToV2),
                    accountTerritoryProduct: []
                }
            };
        }
        if (parsed.fields && Array.isArray(parsed.fields)) {
            return {
                version: 2,
                sections: {
                    account: [],
                    accountTerritory: parsed.fields.map(legacyFieldToV2),
                    accountTerritoryProduct: []
                }
            };
        }
    } catch (e) {
        // fall through
    }
    return JSON.parse(JSON.stringify(DEFAULT_LAYOUT));
}

export function serializeLayout(layout) {
    const normalized = parseLayoutJson(JSON.stringify(layout));
    SECTION_ORDER.forEach((sectionKey) => {
        normalized.sections[sectionKey] = (normalized.sections[sectionKey] || [])
            .slice()
            .sort((a, b) => (a.order || 0) - (b.order || 0))
            .map((field, index) => ({
                ...field,
                order: (index + 1) * 10
            }));
    });
    return JSON.stringify(normalized);
}

export function getSectionCounts(layout) {
    const parsed = typeof layout === 'string' ? parseLayoutJson(layout) : layout;
    return {
        accountCount: (parsed.sections.account || []).length,
        territoryCount: (parsed.sections.accountTerritory || []).length,
        productCount: (parsed.sections.accountTerritoryProduct || []).length
    };
}

export function flattenLayoutFields(layout) {
    const parsed = typeof layout === 'string' ? parseLayoutJson(layout) : layout;
    const sectionLabels =
        parsed.accountVariant === 'HCO' ? SECTION_LABELS_HCO : SECTION_LABELS;
    const rows = [];
    SECTION_ORDER.forEach((sectionKey) => {
        (parsed.sections[sectionKey] || []).forEach((field) => {
            rows.push({
                ...field,
                sectionKey,
                sectionLabel: sectionLabels[sectionKey]
            });
        });
    });
    return rows.sort((a, b) => (a.order || 0) - (b.order || 0));
}

export function getDefaultHcoLayout() {
    return JSON.parse(JSON.stringify(DEFAULT_HCO_LAYOUT));
}

export function getDefaultLayout() {
    return JSON.parse(JSON.stringify(DEFAULT_LAYOUT));
}

export { SECTION_ORDER, SECTION_LABELS, SECTION_LABELS_HCO };