import { plannerApiFetch } from './restHelper.js';

export default async function getMyRequests(params = {}) {
    const limitSize = params.limitSize || 10;
    const data = await plannerApiFetch(
        `/services/apexrest/planner/v1/time-off?limitSize=${encodeURIComponent(limitSize)}`,
        { method: 'GET' }
    );
    return Array.isArray(data) ? data : (data && data.records) || [];
}