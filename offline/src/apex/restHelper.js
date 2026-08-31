export async function plannerApiFetch(path, options = {}) {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const headers = { Accept: 'application/json', ...(options.headers || {}) };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    if (options.body && !headers['Content-Type']) {
        headers['Content-Type'] = 'application/json';
    }
    const fullUrl = `${String(restBase).replace(/\/$/, '')}${path}`;
    const response = await fetch(fullUrl, {
        method: options.method || 'GET',
        credentials: token ? 'omit' : 'same-origin',
        headers,
        body: options.body
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
    if (response.status === 204) {
        return null;
    }
    return response.json();
}
