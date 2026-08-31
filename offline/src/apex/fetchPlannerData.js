import { plannerApiFetch } from './restHelper.js';

export default async function fetchPlannerData(params = {}) {
    const query = new URLSearchParams();
    if (params.weekStart) query.set('weekStart', params.weekStart);
    if (params.weekEnd) query.set('weekEnd', params.weekEnd);
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`/services/apexrest/planner/v1/week${suffix}`);
}
