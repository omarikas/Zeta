import { plannerApiFetch } from './restHelper.js';

export default async function syncOfflineActions(params = {}) {
    console.log('[OfflineSync] Sending pending outbox actions to Salesforce backend...', params);
    try {
        const result = await plannerApiFetch('/services/apexrest/planner/v1/outbox', {
            method: 'POST',
            body: JSON.stringify(params)
        });
        console.log('[OfflineSync] Sync completed with result:', result);
        return result;
    } catch (error) {
        console.error('[OfflineSync] Sync failed with error:', error);
        throw error;
    }
}
