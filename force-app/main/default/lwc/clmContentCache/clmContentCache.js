import getPdfBase64ForPlayer from '@salesforce/apex/ClmPdfViewerController.getPdfBase64ForPlayer';
import {
    getAsset,
    hashUrl,
    putAsset
} from 'c/clmOfflineStore';

export const APEX_DOWNLOAD_MAX_BYTES = 4500000;

const DIRECT_DOWNLOAD_API_VERSION = 'v62.0';

async function toOwnedUint8Array(value) {
    if (!value) {
        return null;
    }
    if (value instanceof Blob) {
        return new Uint8Array(await value.arrayBuffer());
    }
    if (value instanceof Uint8Array) {
        return value.slice();
    }
    if (value instanceof ArrayBuffer) {
        return new Uint8Array(value.slice(0));
    }
    if (ArrayBuffer.isView(value)) {
        return new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
    }
    return new Uint8Array(value);
}

function base64ToUint8Array(base64) {
    const raw = window.atob(base64);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i += 1) {
        bytes[i] = raw.charCodeAt(i);
    }
    return bytes;
}

async function fetchBytesFromUrl(url, credentials = 'same-origin') {
    const response = await fetch(url, { credentials });
    if (!response.ok) {
        throw new Error(`Unable to load asset (HTTP ${response.status}).`);
    }
    return response.arrayBuffer();
}

export function exceedsApexDownloadLimit(contentSize) {
    return contentSize != null && Number(contentSize) > APEX_DOWNLOAD_MAX_BYTES;
}

export function buildNativeContentUrl(contentDocumentId, publicContentUrl, pageNumber) {
    const base =
        (publicContentUrl && String(publicContentUrl).trim()) ||
        (contentDocumentId
            ? `/sfc/servlet.shepherd/document/download/${encodeURIComponent(contentDocumentId)}`
            : null);
    if (!base) {
        return null;
    }
    const page = pageNumber != null ? Number(pageNumber) : null;
    if (!page || Number.isNaN(page) || page < 1) {
        return base;
    }
    const withoutHash = base.split('#')[0];
    return `${withoutHash}#page=${page}`;
}

/**
 * Streams raw file bytes for decks too large to return through Apex (heap).
 * Uses the standard REST VersionData endpoint, which returns binary and honors
 * an OAuth bearer token (offline PWA / Capacitor). In native Lightning the
 * relative URL is generally unreachable, so callers fall back to an error.
 */
async function downloadVersionDataDirect(contentVersionId) {
    if (!contentVersionId) {
        throw new Error('Presentation file is missing a content version.');
    }
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const url = `${String(restBase).replace(/\/$/, '')}/services/data/${DIRECT_DOWNLOAD_API_VERSION}/sobjects/ContentVersion/${encodeURIComponent(contentVersionId)}/VersionData`;
    const headers = { Accept: 'application/octet-stream' };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const response = await fetch(url, {
        method: 'GET',
        credentials: token ? 'omit' : 'same-origin',
        headers
    });
    if (!response.ok) {
        throw new Error(`Unable to download presentation content (HTTP ${response.status}).`);
    }
    return response.arrayBuffer();
}

async function downloadBytesFromNetwork(contentDocumentId, contentSize, options = {}) {
    if (!contentDocumentId) {
        throw new Error('Presentation file is missing.');
    }

    if (exceedsApexDownloadLimit(contentSize)) {
        // Large decks cannot be returned through Apex (heap) - stream the
        // raw bytes via the standard REST VersionData endpoint instead.
        return downloadVersionDataDirect(options.contentVersionId);
    }

    try {
        const base64 = await getPdfBase64ForPlayer({ contentDocumentId });
        if (!base64) {
            throw new Error('Unable to download presentation content.');
        }
        return base64ToUint8Array(base64).buffer;
    } catch (apexError) {
        if (apexError?.code === 'LARGE_FILE') {
            throw apexError;
        }
        const apexMessage = apexError?.body?.message || apexError?.message;
        const error = new Error(apexMessage || 'Unable to download presentation content.');
        if (/too large/i.test(apexMessage || '')) {
            error.code = 'LARGE_FILE';
        }
        throw error;
    }
}

export async function getPdfBytes(contentDocumentId, fetchNetwork = true, options = {}) {
    if (!contentDocumentId) {
        return null;
    }
    const { contentSize } = options;
    const assetKey = `pdf_${contentDocumentId}`;
    const cached = await getAsset(assetKey);
    if (cached?.blob) {
        try {
            const cachedBytes = await toOwnedUint8Array(cached.blob);
            if (cachedBytes?.byteLength) {
                return cachedBytes;
            }
        } catch (cacheError) {
            // Detached or corrupt cache — fall through to network.
        }
    }
    // Note: navigator.onLine is unreliable in Capacitor WebView
    // Always try to fetch - let network failures be handled gracefully
    if (!fetchNetwork) {
        return null;
    }
    const buffer = await downloadBytesFromNetwork(contentDocumentId, contentSize, options);
    const bytes = await toOwnedUint8Array(buffer);
    try {
        await putAsset(assetKey, bytes.slice().buffer, { contentDocumentId, type: 'pdf' });
    } catch (cacheError) {
        // Caching is best-effort; the player can still open the in-memory copy.
    }
    return bytes;
}

export async function downloadContentBytes(contentDocumentId, fetchNetwork = true, options = {}) {
    const bytes = await getPdfBytes(contentDocumentId, fetchNetwork, options);
    if (!bytes) {
        throw new Error('Unable to download presentation content.');
    }
    return bytes.slice().buffer;
}

export async function getSlideBlob(url, fetchNetwork = true) {
    if (!url) {
        return null;
    }
    const assetKey = hashUrl(url);
    const cached = await getAsset(assetKey);
    if (cached?.blob) {
        return cached.blob instanceof Blob ? cached.blob : new Blob([cached.blob]);
    }
    // Note: navigator.onLine is unreliable in Capacitor WebView
    // Always try to fetch - let network failures be handled gracefully
    if (!fetchNetwork) {
        return null;
    }
    // Slide preview URLs that redirect to file.force.com will fail CORS; ignore and fall back.
    try {
        const buffer = await fetchBytesFromUrl(url);
        const blob = new Blob([buffer]);
        await putAsset(assetKey, blob, { url, type: 'slide' });
        return blob;
    } catch (error) {
        return null;
    }
}

export async function prefetchPresentationAssets(manifestEntry, onProgress) {
    if (!manifestEntry) {
        return;
    }
    const tasks = [];
    if (
        manifestEntry.formatType === 'PDF' &&
        manifestEntry.contentDocumentId
    ) {
        tasks.push({
            label: manifestEntry.name,
            run: () =>
                getPdfBytes(manifestEntry.contentDocumentId, true, {
                    contentSize: manifestEntry.contentSize,
                    contentVersionId: manifestEntry.contentVersionId
                })
        });
    }
    (manifestEntry.sequences || []).forEach((sequence) => {
        const url = sequence.slideImageUrl || sequence.thumbnailUrl;
        if (url) {
            tasks.push({
                label: sequence.sequenceName || url,
                run: () => getSlideBlob(url, true)
            });
        }
    });

    let completed = 0;
    for (const task of tasks) {
        try {
            await task.run();
        } catch (error) {
            // Continue prefetching remaining assets.
            // eslint-disable-next-line no-console
            console.warn('CLM prefetch failed', task.label, error);
        }
        completed += 1;
        if (onProgress) {
            onProgress({ completed, total: tasks.length, presentationName: manifestEntry.name });
        }
    }
}

export function createObjectUrl(blob) {
    if (!blob) {
        return null;
    }
    return URL.createObjectURL(blob instanceof Blob ? blob : new Blob([blob]));
}
