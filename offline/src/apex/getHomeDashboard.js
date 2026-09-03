const HOME_DASHBOARD_PATH = '/services/apexrest/planner/v1/home/dashboard';

export default async function getHomeDashboard() {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const headers = { Accept: 'application/json' };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const path = `${String(restBase).replace(/\/$/, '')}${HOME_DASHBOARD_PATH}`;
    console.log('[getHomeDashboard] Fetching:', path);
    console.log('[getHomeDashboard] Token present:', !!token);
    const response = await fetch(path, {
        method: 'GET',
        credentials: token ? 'omit' : 'same-origin',
        headers
    });
    console.log('[getHomeDashboard] Response status:', response.status);
    console.log('[getHomeDashboard] Content-Type:', response.headers.get('content-type'));
    if (!response.ok) {
        let detail = `HTTP ${response.status}`;
        try {
            const failed = await response.json();
            detail = failed?.message || detail;
        } catch (_parseError) {
            const text = await response.text();
            console.error('[getHomeDashboard] Non-JSON error:', text.substring(0, 500));
            detail = `${detail} - ${text.substring(0, 200)}`;
        }
        throw new Error(detail);
    }
    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('[getHomeDashboard] Expected JSON but got:', contentType, text.substring(0, 500));
        throw new Error(`Expected JSON but got ${contentType}: ${text.substring(0, 200)}`);
    }
    return response.json();
}
