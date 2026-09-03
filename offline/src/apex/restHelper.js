// Network status tracking - MANUAL MODE ONLY
// Auto-detection has been disabled. User must manually toggle offline/online mode.

export function isOffline() {
    // No longer auto-detect - this is kept for backward compatibility
    // but always returns false since mode is now manual
    return false;
}

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
    console.log('[REST] Fetching:', fullUrl);
    console.log('[REST] Token present:', !!token);
    console.log('[REST] Token (first 20 chars):', token ? token.substring(0, 20) + '...' : 'none');
    let response;
    try {
        // Add timeout to prevent hanging requests
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 second timeout
        response = await fetch(fullUrl, {
            method: options.method || 'GET',
            credentials: token ? 'omit' : 'same-origin',
            headers,
            body: options.body,
            signal: controller.signal
        });
        clearTimeout(timeoutId);
    } catch (fetchError) {
        // CORS errors throw a TypeError: "Failed to fetch" or "NetworkError"
        console.error('[REST] Fetch failed (possible CORS/network error):', fetchError.message);
        // No longer auto-detect offline status - user must manually toggle
        throw new Error(`Network error - possible CORS issue: ${fetchError.message}`);
    }
    console.log('[REST] Response status:', response.status);
    console.log('[REST] Response type:', response.type);
    console.log('[REST] Content-Type:', response.headers.get('content-type'));

    if (!response.ok) {
        let detail = `HTTP ${response.status}`;
        try {
            const failed = await response.json();
            detail = failed?.message || detail;
        } catch (_parseError) {
            // Keep the HTTP status message when the body is not JSON.
            const text = await response.text();
            console.error('[REST] Non-JSON error response:', text.substring(0, 1000));
            detail = `${detail} - ${text.substring(0, 200)}`;
        }
        throw new Error(detail);
    }
    if (response.status === 204) {
        return null;
    }
    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('[REST] Expected JSON but got:', contentType, text.substring(0, 1000));
        throw new Error(`Expected JSON response but got ${contentType || 'unknown'}: ${text.substring(0, 200)}`);
    }
    return response.json();
}
