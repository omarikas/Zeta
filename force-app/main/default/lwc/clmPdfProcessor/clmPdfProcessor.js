const PDF_LOAD_TIMEOUT_MS = 90000;
const PDF_PAGE_TIMEOUT_MS = 60000;

export function withTimeout(promise, timeoutMs, message) {
    return new Promise((resolve, reject) => {
        const timer = window.setTimeout(() => {
            reject(new Error(message));
        }, timeoutMs);
        Promise.resolve(promise)
            .then((value) => {
                window.clearTimeout(timer);
                resolve(value);
            })
            .catch((error) => {
                window.clearTimeout(timer);
                reject(error);
            });
    });
}

export function countPdfPagesFromBuffer(arrayBuffer) {
    try {
        const text = new TextDecoder('latin1').decode(new Uint8Array(arrayBuffer));
        const pageMatches = text.match(/\/Type\s*\/Page(?!s)/g);
        if (pageMatches && pageMatches.length > 0) {
            return pageMatches.length;
        }
        let maxCount = 0;
        const countMatches = text.matchAll(/\/Count\s+(\d+)/g);
        for (const match of countMatches) {
            const value = Number(match[1]);
            if (value > maxCount) {
                maxCount = value;
            }
        }
        return maxCount > 0 ? maxCount : 1;
    } catch (e) {
        return 1;
    }
}

function clonePdfData(bytes) {
    if (bytes instanceof Uint8Array) {
        return bytes.slice();
    }
    if (bytes instanceof ArrayBuffer) {
        return new Uint8Array(bytes.slice(0));
    }
    if (ArrayBuffer.isView(bytes)) {
        return new Uint8Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    }
    return bytes;
}

export function readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const result = reader.result || '';
            resolve(String(result).split(',')[1] || '');
        };
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
    });
}

export async function openPdfDocument(pdfjsLib, bytes, options = {}) {
    const timeoutMs = options.timeoutMs || PDF_LOAD_TIMEOUT_MS;
    const timeoutMessage = options.timeoutMessage || 'Timed out loading PDF.';
    const preferMainThread = options.preferMainThread === true;

    const loadWithWorker = () =>
        withTimeout(pdfjsLib.getDocument({ data: clonePdfData(bytes) }).promise, timeoutMs, timeoutMessage);

    const loadOnMainThread = () =>
        withTimeout(
            pdfjsLib.getDocument({ data: clonePdfData(bytes), disableWorker: true }).promise,
            timeoutMs,
            `${timeoutMessage} (main thread).`
        );

    if (preferMainThread) {
        try {
            return await loadOnMainThread();
        } catch (mainThreadError) {
            return loadWithWorker();
        }
    }

    try {
        return await loadWithWorker();
    } catch (workerError) {
        return loadOnMainThread();
    }
}

export async function renderPdfSlideImages(pdfjsLib, arrayBuffer, pageCount, options = {}) {
    if (!pdfjsLib?.getDocument) {
        throw new Error('PDF library is not available.');
    }

    const bytes = clonePdfData(arrayBuffer);
    const onProgress = typeof options.onProgress === 'function' ? options.onProgress : null;
    const pdf = await openPdfDocument(pdfjsLib, bytes, {
        timeoutMessage: 'Timed out loading PDF for preview.'
    });
    const images = [];
    const total = Math.min(pageCount || pdf.numPages, pdf.numPages);

    for (let pageNum = 1; pageNum <= total; pageNum += 1) {
        if (onProgress) {
            onProgress(pageNum, total);
        }

        let renderTask = null;
        try {
            const page = await withTimeout(
                pdf.getPage(pageNum),
                PDF_PAGE_TIMEOUT_MS,
                `Timed out loading page ${pageNum}.`
            );
            const viewport = page.getViewport({ scale: 1.5 });
            const canvas = document.createElement('canvas');
            canvas.width = viewport.width;
            canvas.height = viewport.height;
            const context = canvas.getContext('2d');
            renderTask = page.render({ canvasContext: context, viewport });
            await withTimeout(
                renderTask.promise,
                PDF_PAGE_TIMEOUT_MS,
                `Timed out rendering page ${pageNum}.`
            );
            const base64Png = canvas.toDataURL('image/png').split(',')[1];
            images.push({
                pageNumber: pageNum,
                base64Png,
                fileName: `slide-${pageNum}.png`
            });
        } catch (pageError) {
            if (renderTask?.cancel) {
                try {
                    renderTask.cancel();
                } catch (cancelError) {
                    // Ignore cancellation errors for failed pages.
                }
            }
        } finally {
            renderTask = null;
        }
    }

    return images;
}