const TODAY_PLAN_PATH = '/services/apexrest/planner/v1/home/today-plan';

export default async function getTodayPlanPayload(params = {}) {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const headers = { Accept: 'application/json' };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const query = new URLSearchParams();
    if (params.planDate) {
        query.set('planDate', params.planDate);
    }
    if (params.contextUserId) {
        query.set('contextUserId', params.contextUserId);
    }
    const suffix = query.toString() ? `?${query.toString()}` : '';
    const path = `${String(restBase).replace(/\/$/, '')}${TODAY_PLAN_PATH}${suffix}`;
    const response = await fetch(path, {
        method: 'GET',
        credentials: token ? 'omit' : 'same-origin',
        headers
    });
    if (!response.ok) {
        let detail = `HTTP ${response.status}`;
        try {
            const failed = await response.json();
            detail = failed?.message || detail;
        } catch (_parseError) {
            // Keep the HTTP status message when the body is not JSON.
        }
        throw new Error(detail);
    }
    return response.json();
}
