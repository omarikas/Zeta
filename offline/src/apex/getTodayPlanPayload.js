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
    console.log('[getTodayPlan] Fetching:', path);
    console.log('[getTodayPlan] Token present:', !!token);
    const response = await fetch(path, {
        method: 'GET',
        credentials: token ? 'omit' : 'same-origin',
        headers
    });
    console.log('[getTodayPlan] Response status:', response.status);
    console.log('[getTodayPlan] Content-Type:', response.headers.get('content-type'));
    if (!response.ok) {
        let detail = `HTTP ${response.status}`;
        try {
            const failed = await response.json();
            detail = failed?.message || detail;
        } catch (_parseError) {
            const text = await response.text();
            console.error('[getTodayPlan] Non-JSON error:', text.substring(0, 500));
            detail = `${detail} - ${text.substring(0, 200)}`;
        }
        throw new Error(detail);
    }
    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('[getTodayPlan] Expected JSON but got:', contentType, text.substring(0, 500));
        throw new Error(`Expected JSON but got ${contentType}: ${text.substring(0, 200)}`);
    }
    return response.json();
}
