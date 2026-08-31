const HOME_DASHBOARD_PATH = '/services/apexrest/planner/v1/home/dashboard';

export default async function getHomeDashboard() {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const headers = { Accept: 'application/json' };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const path = `${String(restBase).replace(/\/$/, '')}${HOME_DASHBOARD_PATH}`;
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
