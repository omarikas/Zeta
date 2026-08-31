import { plannerApiFetch } from './restHelper.js';

export default async function getPromotionalProjects(params = {}) {
    const query = new URLSearchParams();
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`/services/apexrest/planner/v1/projects${suffix}`);
}
