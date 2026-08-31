export const COLLECTIONS_STORAGE_PREFIX = 'fieldRepPlanner.collections.';

export function getCollectionsStorageKey(userId) {
    return `${COLLECTIONS_STORAGE_PREFIX}${userId || 'anonymous'}`;
}

export function loadAccountCollections(userId) {
    if (typeof window === 'undefined') {
        return [];
    }
    try {
        const raw = window.localStorage.getItem(getCollectionsStorageKey(userId));
        if (!raw) {
            return [];
        }
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed?.collections) ? parsed.collections : [];
    } catch (error) {
        return [];
    }
}

export function getCollectionAccountIds(collection) {
    if (!collection) {
        return [];
    }
    if (Array.isArray(collection.accountIds) && collection.accountIds.length) {
        return collection.accountIds.filter(Boolean);
    }
    return (collection.accounts || []).map((account) => account?.id).filter(Boolean);
}

export function saveAccountCollections(userId, collections) {
    if (typeof window === 'undefined') {
        return false;
    }
    try {
        window.localStorage.setItem(
            getCollectionsStorageKey(userId),
            JSON.stringify({ collections: collections || [] })
        );
        return true;
    } catch (error) {
        return false;
    }
}