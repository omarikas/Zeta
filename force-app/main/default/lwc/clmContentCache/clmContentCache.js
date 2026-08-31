import getPdfBase64ForPlayer from '@salesforce/apex/ClmPdfViewerController.getPdfBase64ForPlayer';
import {
    getAsset,
    hashUrl,
    putAsset
} from 'c/clmOfflineStore';

export const APEX_DOWNLOAD_MAX_BYTES = 4500000;

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
 * Browser fetch to Files redirects to file.force.com and is blocked by CORS
 * from lightning.force.com. Only Apex can return bytes, and only under heap limits.
 */
async function downloadBytesFromNetwork(contentDocumentId, contentSize) {
    if (!contentDocumentId) {
        throw new Error('Presentation file is missing.');
    }
    if (exceedsApexDownloadLimit(contentSize)) {
        const mb = (Number(contentSize) / 1048576).toFixed(1);
        const error = new Error(
            `This presentation is ${mb} MB and cannot be loaded into the player as raw bytes. Use the native viewer.`
        );
        error.code = 'LARGE_FILE';
        throw error;
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
    if (!fetchNetwork || !navigator.onLine) {
        return null;
    }
    if (exceedsApexDownloadLimit(contentSize)) {
        const error = new Error('Presentation exceeds Apex download limit.');
        error.code = 'LARGE_FILE';
        throw error;
    }
    const buffer = await downloadBytesFromNetwork(contentDocumentId, contentSize);
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
    if (!fetchNetwork || !navigator.onLine) {
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
        manifestEntry.contentDocumentId &&
        !exceedsApexDownloadLimit(manifestEntry.contentSize)
    ) {
        tasks.push({
            label: manifestEntry.name,
            run: () =>
                getPdfBytes(manifestEntry.contentDocumentId, true, {
                    contentSize: manifestEntry.contentSize
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
