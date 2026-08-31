import { plannerApiFetch } from './restHelper.js';

export default async function getMapAccounts(params = {}) {
    const query = new URLSearchParams();
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`/services/apexrest/planner/v1/accounts/map${suffix}`);
}
