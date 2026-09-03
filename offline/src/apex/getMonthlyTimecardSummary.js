// Offline stub for FieldRepHomeController.getMonthlyTimecardSummary (Aura-only
// in the org, so not reachable directly). Tries a REST route on the Planner
// service; if that route is not deployed yet, resolves to an empty summary so
// the Monthly Timecard component still renders its base tiles (zeros) instead
// of disappearing. Real numbers appear automatically once the endpoint exists.
const TIMECARD_PATH = '/services/apexrest/planner/v1/home/monthly-timecard';

export default async function getMonthlyTimecardSummary({ contextUserId } = {}) {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const headers = { Accept: 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;

    const qs = contextUserId ? `?contextUserId=${encodeURIComponent(contextUserId)}` : '';
    const url = `${String(restBase).replace(/\/$/, '')}${TIMECARD_PATH}${qs}`;

    try {
        const response = await fetch(url, {
            method: 'GET',
            credentials: token ? 'omit' : 'same-origin',
            headers
        });
        const contentType = response.headers.get('content-type') || '';
        if (!response.ok || !contentType.includes('application/json')) {
            return {};
        }
        return await response.json();
    } catch (_err) {
        // Offline or endpoint missing — render empty summary.
        return {};
    }
}
