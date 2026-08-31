const TOGGLE_FIELDS = new Set(['Is_KOL__c', 'Has_KOLs__c']);

export function hasMeaningfulValue(value) {
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
}

export function mergeRatingValues(fallback, live) {
    const merged = { ...(fallback || {}) };
    if (!live) {
        return merged;
    }
    for (const [fieldApiName, liveValue] of Object.entries(live)) {
        if (typeof liveValue === 'boolean' || TOGGLE_FIELDS.has(fieldApiName)) {
            merged[fieldApiName] = liveValue;
        } else if (hasMeaningfulValue(liveValue)) {
            merged[fieldApiName] = liveValue;
        }
    }
    return merged;
}