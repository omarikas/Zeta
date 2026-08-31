import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import JSZIP_URL from '@salesforce/resourceUrl/jszip';
import PDFJS_URL from '@salesforce/resourceUrl/pdfjs';
import { getSlideBlob, createObjectUrl, downloadContentBytes, getPdfBytes, exceedsApexDownloadLimit, APEX_DOWNLOAD_MAX_BYTES } from 'c/clmContentCache';
import { openPdfDocument } from 'c/clmPdfProcessor';
import { getManifestEntry, putLocalSession } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';
import startSession from '@salesforce/apex/ClmMetricsController.startSession';
import startAdHocPresentation from '@salesforce/apex/ClmMetricsController.startAdHocPresentation';
import logSlideEvent from '@salesforce/apex/ClmMetricsController.logSlideEvent';
import completeSession from '@salesforce/apex/ClmMetricsController.completeSession';
import cancelSession from '@salesforce/apex/ClmMetricsController.cancelSession';
import saveMessageResponses from '@salesforce/apex/ClmMetricsController.saveMessageResponses';
import getSessionMessageResponses from '@salesforce/apex/ClmMetricsController.getSessionMessageResponses';

const SLIDE_IMAGE_LOAD_TIMEOUT_MS = 15000;
const PDF_INIT_TIMEOUT_MS = 60000;
const SENTIMENTS = [
    { emoji: '😊', label: 'Happy', value: 'Positive' },
    { emoji: '😐', label: 'Neutral', value: 'Neutral' },
    { emoji: '☹️', label: 'Sad', value: 'Negative' }
];

function createClientSessionKey() {
    if (window.crypto?.randomUUID) {
        return window.crypto.randomUUID();
    }
    return `clm_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

export default class ClmPlayer extends LightningElement {
    @api visitId;
    @api presentationId;
    @api presentationName;
    @api adHoc = false;

    @track session;
    @track currentIndex = 0;
    @track isSessionLoading = true;
    @track slideImageReady = false;
    @track slideImageLoadFailed = false;
    @track trackingPaused = false;
    @track dwellAccumulator = 0;
    @track pdfLoadError;
    @track pdfLoadingStatus;
    @track showMessageOverlay = false;
    @track overlayMessages = [];
    @track isSavingMessageResponse = false;
    @track resolvedSlideUrl;
    @track isOfflineSession = false;
    @track htmlFrameUrl;
    @track htmlLoadError;
    @track htmlLoadingStatus;
    @track pdfViewerSrc;
    @track useNativePdfViewer = false;

    timerId;
    slideImageLoadTimerId;
    visibilityHandler;
    preloadedUrls = new Set();
    objectUrls = new Set();
    pdfCanvasRetryCount = 0;
    pdfSlideReady = false;
    htmlSlideReady = false;
    pdfJsReady = false;
    pdfDoc = null;
    pdfLoading = false;
    pdfRenderTask = null;
    pdfLoadScheduled = false;
    pendingNavigation = null;
    messageResponses = [];
    capturedMessageNames = new Set();
    clientSessionKey;
    jsZipReady = false;
    htmlPackageReady = false;
    htmlPackageLoading = false;
    htmlBlobByPath = new Map();
    htmlTextByPath = new Map();
    htmlFrameObjectUrl = null;

    connectedCallback() {
        this.visibilityHandler = () => {
            if (document.hidden) {
                this.pauseTracking();
            }
        };
        this.viewerMessageHandler = (event) => this.handleViewerMessage(event);
        document.addEventListener('visibilitychange', this.visibilityHandler);
        window.addEventListener('message', this.viewerMessageHandler);
        this.bootstrapSession();
    }

    disconnectedCallback() {
        this.clearTimer();
        this.clearSlideImageLoadTimer();
        this.cancelPdfRender();
        this.clearHtmlBlobCache();
        this.revokeObjectUrls();
        document.removeEventListener('visibilitychange', this.visibilityHandler);
        window.removeEventListener('message', this.viewerMessageHandler);
    }

    renderedCallback() {
        if (this.pdfLoadScheduled && this.needsPdfRendering && !this.pdfLoading) {
            this.pdfLoadScheduled = false;
            this.renderCurrentPdfPage();
        }
    }

    async bootstrapSession() {
        this.isSessionLoading = true;
        this.pdfLoadError = null;
        this.pdfDoc = null;
        this.useNativePdfViewer = false;
        this.pdfViewerSrc = null;
        this.cancelPdfRender();
        try {
            if (this.adHoc) {
                if (isOfflineMode()) {
                    this.session = await this.bootstrapOfflineAdHocSession();
                    this.isOfflineSession = true;
                } else {
                    this.session = await startAdHocPresentation({ presentationId: this.presentationId });
                    this.visitId = this.session.visitId;
                }
            } else if (isOfflineMode()) {
                this.session = await this.bootstrapOfflineSession();
                this.isOfflineSession = true;
            } else {
                this.session = await startSession({
                    visitId: this.visitId,
                    presentationId: this.presentationId
                });
            }
            this.currentIndex = 0;
            await this.loadExistingMessageResponses();
            await this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
        } catch (error) {
            this.showToast('Unable to start presentation', this.reduceError(error), 'error');
            this.dispatchClose();
        } finally {
            this.isSessionLoading = false;
            if (this.needsPdfRendering) {
                this.pdfSlideReady = false;
                this.renderCurrentPdfPage();
            }
            if (this.needsHtmlRendering) {
                this.htmlSlideReady = false;
                this.resolveCurrentHtmlFrame();
            }
        }
    }

    async bootstrapOfflineSession() {
        const manifest = await getManifestEntry(this.presentationId);
        if (!manifest) {
            throw new Error('Presentation is not cached. Open Field Home while online first.');
        }
        this.clientSessionKey = createClientSessionKey();
        const session = {
            id: this.clientSessionKey,
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: manifest.presentationId || manifest.id,
            presentationName: manifest.name || this.presentationName,
            formatType: manifest.formatType,
            contentDocumentId: manifest.contentDocumentId,
            status: 'Active',
            productName: manifest.productName,
            productImageUrl: manifest.imageUrl,
            slideCount: manifest.slideCount,
            sequences: manifest.sequences || [],
            trackingPaused: false
        };
        await putLocalSession({
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: session.presentationId,
            session,
            messageResponses: []
        });
        await queueOfflineAction({
            actionType: 'START_SESSION',
            clientSessionKey: this.clientSessionKey,
            visitId: this.visitId,
            presentationId: session.presentationId,
            startedAtIso: new Date().toISOString()
        });
        return session;
    }

    async bootstrapOfflineAdHocSession() {
        const manifest = await getManifestEntry(this.presentationId);
        if (!manifest) {
            throw new Error('Presentation is not cached. Open Field Home while online first.');
        }
        this.clientSessionKey = createClientSessionKey();
        const clientVisitKey = createClientSessionKey();
        this.visitId = clientVisitKey;
        const session = {
            id: this.clientSessionKey,
            clientSessionKey: this.clientSessionKey,
            clientVisitKey,
            visitId: clientVisitKey,
            presentationId: manifest.presentationId || manifest.id,
            presentationName: manifest.name || this.presentationName,
            formatType: manifest.formatType,
            contentDocumentId: manifest.contentDocumentId,
            status: 'Active',
            productName: manifest.productName,
            productImageUrl: manifest.imageUrl,
            slideCount: manifest.slideCount,
            sequences: manifest.sequences || [],
            trackingPaused: false
        };
        await putLocalSession({
            clientSessionKey: this.clientSessionKey,
            visitId: clientVisitKey,
            presentationId: session.presentationId,
            session,
            messageResponses: []
        });
        await queueOfflineAction({
            actionType: 'START_ADHOC_SESSION',
            clientSessionKey: this.clientSessionKey,
            clientVisitKey,
            presentationId: session.presentationId,
            startedAtIso: new Date().toISOString()
        });
        return session;
    }

    getSessionKey() {
        return this.session?.serverSessionId || this.session?.clientSessionKey || this.session?.id;
    }

    getServerSessionId() {
        if (this.session?.serverSessionId) {
            return this.session.serverSessionId;
        }
        const id = String(this.session?.id || '');
        if (id && id !== this.clientSessionKey && /^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(id)) {
            return id;
        }
        return null;
    }

    async loadExistingMessageResponses() {
        const serverSessionId = this.getServerSessionId();
        if (!serverSessionId) {
            const local = this.session?.messageResponses;
            if (local?.length) {
                this.applyMessageResponses(local);
            }
            return;
        }
        try {
            const rows = await getSessionMessageResponses({ sessionId: serverSessionId });
            this.applyMessageResponses(rows || []);
        } catch (error) {
            if (!isOfflineMode()) {
                this.showToast('Message sync warning', this.reduceError(error), 'warning');
            }
        }
    }

    applyMessageResponses(rows) {
        this.messageResponses = (rows || []).map((row, index) => ({
            productName: row.productName,
            messageName: row.messageName,
            sentiment: row.sentiment,
            sortOrder: row.sortOrder || index + 1
        }));
        this.capturedMessageNames = new Set(
            this.messageResponses
                .map((row) => (row.messageName || '').trim().toUpperCase())
                .filter(Boolean)
        );
    }

    get sequences() {
        return this.session?.sequences || [];
    }

    get currentSequence() {
        return this.sequences[this.currentIndex] || null;
    }

    get needsPdfRendering() {
        // Large PDFs cannot be fetched/Apex-loaded; use page rendition images instead.
        return (
            this.session?.formatType === 'PDF' &&
            !!this.session?.contentDocumentId &&
            !this.usesPdfRenditions
        );
    }

    get usesPdfRenditions() {
        return (
            (this.session?.formatType || '').toUpperCase() === 'PDF' &&
            !!this.session?.contentVersionId &&
            exceedsApexDownloadLimit(this.session?.contentSize)
        );
    }

    get needsHtmlRendering() {
        const format = (this.session?.formatType || '').toUpperCase();
        return (format === 'HTML' || format === 'ZIP') && !!this.session?.contentDocumentId;
    }

    get slideCounterLabel() {
        if (this.isSessionLoading) {
            return 'Loading…';
        }
        if (!this.sequences.length) {
            return '0 of 0';
        }
        return `${this.currentIndex + 1} of ${this.sequences.length}`;
    }

    get currentSlideUrl() {
        if (this.slideImageLoadFailed) {
            return null;
        }
        return this.resolvedSlideUrl;
    }

    get showPdfViewer() {
        if (this.isSessionLoading || this.currentSlideUrl || this.pdfLoadError || this.usesPdfRenditions) {
            return false;
        }
        return this.needsPdfRendering && !!this.currentSequence;
    }

    get showPdfCanvas() {
        return this.showPdfViewer && !this.useNativePdfViewer;
    }

    get showNativePdfViewer() {
        // Intentionally unused for large files (download URLs force save-to-disk).
        return false;
    }

    get showHtmlViewer() {
        if (this.isSessionLoading || this.currentSlideUrl || this.htmlLoadError) {
            return false;
        }
        return this.needsHtmlRendering && !!this.currentSequence && !!this.htmlFrameUrl;
    }

    get showPlaceholder() {
        return (
            !this.isSessionLoading &&
            !!this.currentSequence &&
            !this.currentSlideUrl &&
            !this.showPdfViewer &&
            !this.showHtmlViewer &&
            !this.pdfLoadError &&
            !this.htmlLoadError
        );
    }

    get showStageSpinner() {
        return (
            !this.pdfLoadError &&
            !this.htmlLoadError &&
            (this.isSessionLoading ||
                (this.currentSlideUrl && !this.slideImageReady) ||
                (this.showPdfViewer && !this.pdfSlideReady) ||
                (this.needsHtmlRendering && !this.htmlSlideReady && !this.htmlLoadError))
        );
    }

    get stageLoadingLabel() {
        if (this.isSessionLoading) {
            return 'Starting presentation…';
        }
        if (this.htmlLoadingStatus) {
            return this.htmlLoadingStatus;
        }
        if (this.pdfLoadingStatus) {
            return this.pdfLoadingStatus;
        }
        if (this.showPdfViewer || this.needsHtmlRendering) {
            return 'Loading slide…';
        }
        return 'Loading slide…';
    }

    get showPauseOverlay() {
        return this.trackingPaused && !this.showMessageOverlay;
    }

    get showOfflineBanner() {
        return this.isOfflineSession || isOfflineMode();
    }

    get trackingToggleLabel() {
        return this.trackingPaused ? 'Resume Tracking' : 'Pause Tracking';
    }

    get trackingIconName() {
        return this.trackingPaused ? 'utility:play' : 'utility:pause';
    }

    get thumbnailItems() {
        return this.sequences.map((seq, index) => ({
            key: seq.id,
            label: seq.sequenceName,
            pageLabel: `P${seq.pageNumber || index + 1}`,
            url: seq.thumbnailUrl || seq.slideImageUrl,
            className: index === this.currentIndex ? 'thumb thumb-active' : 'thumb',
            isActive: index === this.currentIndex,
            index
        }));
    }

    get canGoBack() {
        return this.currentIndex > 0;
    }

    get canGoForward() {
        return this.currentIndex < this.sequences.length - 1;
    }

    get isPreviousDisabled() {
        return this.isSessionLoading || this.showMessageOverlay || !this.canGoBack;
    }

    get isNextDisabled() {
        return this.isSessionLoading || this.showMessageOverlay || !this.canGoForward;
    }

    get isCompleteDisabled() {
        return this.isSessionLoading || this.showMessageOverlay || !this.session?.id;
    }

    get overlayProductName() {
        const seq = this.currentSequence;
        return (
            this.session?.productName ||
            this.parseDelimitedValues(seq?.productNames)[0] ||
            this.presentationName
        );
    }

    get isMessageOverlaySaveDisabled() {
        return (
            this.isSavingMessageResponse ||
            !this.overlayMessages.length ||
            !this.overlayMessages.every((message) => !!message.sentiment)
        );
    }

    get sentimentOptions() {
        return SENTIMENTS;
    }

    get hasSlideMessages() {
        return this.parseDelimitedValues(this.currentSequence?.messageNames).length > 0;
    }

    get uncapturedMessageCount() {
        return this.getUncapturedMessagesForCurrentSlide().length;
    }

    get slideMessageButtonLabel() {
        if (!this.hasSlideMessages) {
            return '';
        }
        if (this.uncapturedMessageCount > 0) {
            return this.uncapturedMessageCount === 1
                ? 'Capture Message'
                : `Capture ${this.uncapturedMessageCount} Messages`;
        }
        return 'Message Captured';
    }

    get slideMessageButtonClass() {
        return this.uncapturedMessageCount > 0
            ? 'slide-message-btn slide-message-btn-pending'
            : 'slide-message-btn slide-message-btn-done';
    }

    get overlayMessagesWithOptions() {
        return (this.overlayMessages || []).map((message) => ({
            ...message,
            options: SENTIMENTS.map((option) => ({
                ...option,
                key: `${message.key}_${option.value}`,
                className:
                    message.sentiment === option.value
                        ? 'message-sentiment-btn message-sentiment-btn-selected'
                        : 'message-sentiment-btn'
            }))
        }));
    }

    handleSlideImageLoad() {
        this.clearSlideImageLoadTimer();
        this.slideImageReady = true;
    }

    handleSlideImageError() {
        this.clearSlideImageLoadTimer();
        if (
            this.usesPdfRenditions &&
            this.resolvedSlideUrl &&
            this.resolvedSlideUrl.includes('rendition=SVGZ')
        ) {
            // Fall back to raster thumbnail rendition if SVGZ is unavailable.
            this.resolvedSlideUrl = this.buildPdfRenditionUrl(this.currentPdfPage(), false);
            this.slideImageLoadFailed = false;
            this.slideImageReady = false;
            this.startSlideImageLoadTimer();
            return;
        }
        this.slideImageLoadFailed = true;
        this.slideImageReady = true;
        if (this.needsPdfRendering) {
            this.pdfSlideReady = false;
            this.renderCurrentPdfPage();
        } else if (this.usesPdfRenditions) {
            this.pdfLoadError =
                'Unable to preview this slide. Ask your admin to re-upload the deck with slide images, or enable PDF “Execute in Browser” under File Upload and Download Security.';
            this.showToast('Slide load failed', this.pdfLoadError, 'error');
        }
    }

    clearSlideImageLoadTimer() {
        if (this.slideImageLoadTimerId) {
            window.clearTimeout(this.slideImageLoadTimerId);
            this.slideImageLoadTimerId = null;
        }
    }

    startSlideImageLoadTimer() {
        this.clearSlideImageLoadTimer();
        if (!this.currentSlideUrl) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.slideImageLoadTimerId = window.setTimeout(() => {
            this.slideImageLoadTimerId = null;
            if (!this.slideImageReady && !this.slideImageLoadFailed) {
                this.handleSlideImageError();
            }
        }, SLIDE_IMAGE_LOAD_TIMEOUT_MS);
    }

    currentPdfPage() {
        return this.currentSequence?.pageNumber || this.currentIndex + 1;
    }

    currentHtmlEntry() {
        return this.currentSequence?.htmlEntryPoint || 'index.html';
    }

    async ensurePdfJsReady() {
        if (this.pdfJsReady && window.pdfjsLib) {
            return window.pdfjsLib;
        }
        await loadScript(this, `${PDFJS_URL}/pdf.min.js`);
        if (!window.pdfjsLib) {
            throw new Error('PDF library failed to initialize.');
        }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = `${PDFJS_URL}/pdf.worker.min.js`;
        this.pdfJsReady = true;
        return window.pdfjsLib;
    }

    prepareNativePdfViewer() {
        if (!this.session?.contentDocumentId && !this.session?.publicContentUrl) {
            throw new Error('Presentation file is missing.');
        }
        this.useNativePdfViewer = true;
        this.pdfDoc = null;
        this.pdfLoadError = null;
        this.pdfSlideReady = false;
        this.pdfLoadingStatus = 'Opening presentation…';
        const page = this.currentPdfPage();
        // Route through VF so Lightning CSP can frame the org page; VF then navigates to Files.
        const params = new URLSearchParams({
            page: String(page),
            t: String(Date.now())
        });
        if (this.session.contentDocumentId) {
            params.set('docId', this.session.contentDocumentId);
        }
        if (this.session.publicContentUrl) {
            params.set('publicUrl', this.session.publicContentUrl);
        }
        this.pdfViewerSrc = `/apex/ClmPdfViewer?${params.toString()}`;
    }

    handleNativePdfLoad() {
        this.pdfSlideReady = true;
        this.pdfLoadError = null;
        this.pdfLoadingStatus = null;
    }

    async ensurePdfDocumentLoaded() {
        if (this.pdfDoc || !this.session?.contentDocumentId) {
            return;
        }
        if (exceedsApexDownloadLimit(this.session?.contentSize)) {
            const error = new Error('LARGE_FILE');
            error.code = 'LARGE_FILE';
            throw error;
        }
        this.pdfLoadingStatus = 'Downloading presentation…';
        const bytes = await getPdfBytes(this.session.contentDocumentId, navigator.onLine, {
            contentSize: this.session?.contentSize
        });
        if (!bytes) {
            throw new Error('Unable to download presentation content.');
        }
        const pdfjsLib = await this.ensurePdfJsReady();
        this.pdfLoadingStatus = 'Opening presentation…';
        this.pdfDoc = await openPdfDocument(pdfjsLib, bytes, {
            preferMainThread: true,
            timeoutMs: PDF_INIT_TIMEOUT_MS,
            timeoutMessage: 'Timed out loading PDF.'
        });
    }

    async renderCurrentPdfPage() {
        if (!this.needsPdfRendering || this.pdfLoading) {
            return;
        }
        this.pdfLoading = true;
        this.pdfLoadError = null;
        this.pdfSlideReady = false;
        if (!this.pdfLoadingStatus) {
            this.pdfLoadingStatus = 'Loading presentation…';
        }
        try {
            if (exceedsApexDownloadLimit(this.session?.contentSize) && this.session?.contentVersionId) {
                this.slideImageLoadFailed = false;
                await this.resolveCurrentSlideUrl();
                this.slideImageReady = !this.currentSlideUrl;
                if (this.currentSlideUrl) {
                    this.startSlideImageLoadTimer();
                }
                this.pdfSlideReady = true;
                this.pdfLoadingStatus = null;
                return;
            }

            await this.ensurePdfDocumentLoaded();
            const canvas = this.template.querySelector('.slide-pdf-canvas');
            if (!canvas) {
                this.pdfLoadScheduled = true;
                return;
            }
            const pageNum = Math.min(
                Math.max(this.currentPdfPage(), 1),
                this.pdfDoc.numPages || 1
            );
            this.pdfLoadingStatus = 'Rendering slide…';
            const page = await this.pdfDoc.getPage(pageNum);
            const viewport = page.getViewport({ scale: 1.5 });
            const context = canvas.getContext('2d');
            canvas.width = viewport.width;
            canvas.height = viewport.height;
            this.cancelPdfRender();
            this.pdfRenderTask = page.render({ canvasContext: context, viewport });
            await this.pdfRenderTask.promise;
            this.pdfRenderTask = null;
            this.pdfSlideReady = true;
            this.pdfLoadError = null;
            this.pdfLoadingStatus = null;
        } catch (error) {
            if (error?.name === 'RenderingCancelledException') {
                return;
            }
            if (error?.code === 'LARGE_FILE' || /too large|LARGE_FILE|native viewer/i.test(error?.message || '')) {
                if (this.session?.contentVersionId) {
                    // Switch to rendition images instead of a download URL.
                    this.session = {
                        ...this.session,
                        contentSize: this.session.contentSize || APEX_DOWNLOAD_MAX_BYTES + 1
                    };
                    this.useNativePdfViewer = false;
                    this.pdfViewerSrc = null;
                    this.slideImageLoadFailed = false;
                    await this.resolveCurrentSlideUrl();
                    this.slideImageReady = !this.currentSlideUrl;
                    if (this.currentSlideUrl) {
                        this.startSlideImageLoadTimer();
                    }
                    this.pdfSlideReady = true;
                    this.pdfLoadingStatus = null;
                    return;
                }
                this.pdfLoadError =
                    'This presentation is too large to load. Re-upload under 4 MB, or generate slide images in the CLM wizard.';
            } else {
                this.pdfDoc = null;
                this.pdfLoadError = this.reduceError(error);
            }
            this.pdfSlideReady = true;
            this.pdfLoadingStatus = null;
            if (this.pdfLoadError) {
                this.showToast('Slide load failed', this.pdfLoadError, 'error');
            }
        } finally {
            this.pdfLoading = false;
        }
    }

    handleViewerMessage(event) {
        const data = event.data;
        if (!data || typeof data !== 'object') {
            return;
        }
        if (data.type === 'clm-pdf-ready') {
            this.pdfSlideReady = true;
            this.pdfLoadError = null;
            this.pdfLoadingStatus = null;
            return;
        }
        if (data.type === 'clm-pdf-error') {
            this.pdfLoadError = data.message || 'Unable to load slide.';
            this.pdfSlideReady = true;
            this.pdfLoadingStatus = null;
            this.showToast('Slide load failed', this.pdfLoadError, 'error');
            return;
        }
        if (data.type === 'clm-html-ready') {
            this.htmlSlideReady = true;
            this.htmlLoadError = null;
            this.htmlLoadingStatus = null;
            return;
        }
        if (data.type === 'clm-html-error') {
            this.htmlLoadError = data.message || 'Unable to load HTML presentation.';
            this.htmlSlideReady = true;
            this.htmlLoadingStatus = null;
            this.showToast('HTML load failed', this.htmlLoadError, 'error');
        }
    }

    cancelPdfRender() {
        if (this.pdfRenderTask) {
            try {
                this.pdfRenderTask.cancel();
            } catch (e) {
                // ignore cancel races
            }
            this.pdfRenderTask = null;
        }
    }

    handleRetryPdfLoad() {
        this.pdfLoadError = null;
        this.pdfSlideReady = false;
        this.pdfLoadingStatus = null;
        this.pdfDoc = null;
        this.useNativePdfViewer = false;
        this.pdfViewerSrc = null;
        this.renderCurrentPdfPage();
    }

    handleRetryHtmlLoad() {
        this.htmlLoadError = null;
        this.htmlLoadingStatus = null;
        this.htmlSlideReady = false;
        this.resolveCurrentHtmlFrame();
    }

    handleHtmlFrameLoad() {
        this.htmlSlideReady = true;
        this.htmlLoadError = null;
        this.htmlLoadingStatus = null;
    }

    async preloadAdjacentSlides() {
        const indices = [this.currentIndex, this.currentIndex + 1, this.currentIndex - 1];
        for (const index of indices) {
            const seq = this.sequences[index];
            const url = seq?.slideImageUrl || seq?.thumbnailUrl;
            if (!url || this.preloadedUrls.has(url)) {
                continue;
            }
            this.preloadedUrls.add(url);
            try {
                const blob = await getSlideBlob(url, navigator.onLine);
                if (blob) {
                    const objectUrl = createObjectUrl(blob);
                    if (objectUrl) {
                        this.objectUrls.add(objectUrl);
                    }
                }
            } catch (error) {
                const img = new Image();
                img.src = url;
            }
        }
    }

    revokeObjectUrls() {
        this.objectUrls.forEach((url) => URL.revokeObjectURL(url));
        this.objectUrls.clear();
    }

    buildPdfRenditionUrl(pageNumber, highRes = true) {
        const versionId = this.session?.contentVersionId;
        if (!versionId) {
            return null;
        }
        const pageIndex = Math.max(0, (pageNumber || 1) - 1);
        const rendition = highRes ? 'SVGZ' : 'THUMB720BY480';
        return `/sfc/servlet.shepherd/version/renditionDownload?rendition=${rendition}&versionId=${encodeURIComponent(
            versionId
        )}&page=${pageIndex}`;
    }

    async resolveCurrentSlideUrl() {
        this.revokeObjectUrls();
        if (this.usesPdfRenditions) {
            this.resolvedSlideUrl = this.buildPdfRenditionUrl(this.currentPdfPage(), true);
            return;
        }
        const seq = this.currentSequence;
        const url = seq?.slideImageUrl || seq?.thumbnailUrl;
        if (!url) {
            this.resolvedSlideUrl = null;
            return;
        }
        try {
            const blob = await getSlideBlob(url, navigator.onLine);
            if (blob) {
                const objectUrl = createObjectUrl(blob);
                this.objectUrls.add(objectUrl);
                this.resolvedSlideUrl = objectUrl;
                return;
            }
        } catch (error) {
            // Fall back to direct URL below.
        }
        this.resolvedSlideUrl = url;
    }

    async resetSlideReadyState() {
        this.clearSlideImageLoadTimer();
        if (this.usesPdfRenditions) {
            this.slideImageLoadFailed = false;
            await this.resolveCurrentSlideUrl();
            this.slideImageReady = !this.currentSlideUrl;
            if (this.currentSlideUrl) {
                this.startSlideImageLoadTimer();
            }
            return;
        }
        if (this.needsPdfRendering || this.needsHtmlRendering) {
            this.resolvedSlideUrl = null;
            this.slideImageLoadFailed = true;
            this.slideImageReady = true;
        } else {
            this.slideImageLoadFailed = false;
            await this.resolveCurrentSlideUrl();
            this.slideImageReady = !this.currentSlideUrl;
            if (this.currentSlideUrl) {
                this.startSlideImageLoadTimer();
            }
        }
        if (this.needsPdfRendering) {
            await this.renderCurrentPdfPage();
        }
        if (this.needsHtmlRendering) {
            this.htmlSlideReady = false;
            await this.resolveCurrentHtmlFrame();
        }
    }

    async ensureJsZipReady() {
        if (this.jsZipReady && window.JSZip) {
            return window.JSZip;
        }
        await loadScript(this, JSZIP_URL);
        this.jsZipReady = true;
        return window.JSZip;
    }

    async fetchZipBytes(contentDocumentId) {
        return downloadContentBytes(contentDocumentId, navigator.onLine, {
            publicContentUrl: this.session?.publicContentUrl,
            contentSize: this.session?.contentSize
        });
    }

    normalizeZipPath(path) {
        return String(path || '')
            .replace(/\\/g, '/')
            .replace(/^\.\//, '')
            .replace(/^\/+/, '');
    }

    guessMimeType(path) {
        const lower = String(path || '').toLowerCase();
        if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
        if (lower.endsWith('.js')) return 'application/javascript';
        if (lower.endsWith('.css')) return 'text/css';
        if (lower.endsWith('.png')) return 'image/png';
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
        if (lower.endsWith('.gif')) return 'image/gif';
        if (lower.endsWith('.svg')) return 'image/svg+xml';
        if (lower.endsWith('.webp')) return 'image/webp';
        if (lower.endsWith('.mp4')) return 'video/mp4';
        if (lower.endsWith('.woff2')) return 'font/woff2';
        if (lower.endsWith('.woff')) return 'font/woff';
        if (lower.endsWith('.ttf')) return 'font/ttf';
        if (lower.endsWith('.json')) return 'application/json';
        return 'application/octet-stream';
    }

    async ensureHtmlPackageLoaded() {
        if (this.htmlPackageReady || !this.session?.contentDocumentId) {
            return;
        }
        if (this.htmlPackageLoading) {
            return;
        }
        this.htmlPackageLoading = true;
        this.htmlLoadError = null;
        this.htmlLoadingStatus = 'Downloading HTML package…';
        try {
            const JSZip = await this.ensureJsZipReady();
            this.htmlLoadingStatus = 'Unpacking slides…';
            const bytes = await this.fetchZipBytes(this.session.contentDocumentId);
            const zip = await JSZip.loadAsync(bytes);
            this.clearHtmlBlobCache();
            const entries = Object.keys(zip.files).filter((name) => !zip.files[name].dir);
            for (const name of entries) {
                const normalized = this.normalizeZipPath(name);
                if (!normalized || normalized.includes('__MACOSX') || normalized.split('/').pop().startsWith('.')) {
                    continue;
                }
                const lower = normalized.toLowerCase();
                if (lower.endsWith('.html') || lower.endsWith('.htm') || lower.endsWith('.css') || lower.endsWith('.js') || lower.endsWith('.svg')) {
                    const text = await zip.file(name).async('string');
                    this.htmlTextByPath.set(normalized, text);
                    const blob = new Blob([text], { type: this.guessMimeType(normalized) });
                    const url = URL.createObjectURL(blob);
                    this.htmlBlobByPath.set(normalized, url);
                    this.objectUrls.add(url);
                } else {
                    const data = await zip.file(name).async('uint8array');
                    const blob = new Blob([data], { type: this.guessMimeType(normalized) });
                    const url = URL.createObjectURL(blob);
                    this.htmlBlobByPath.set(normalized, url);
                    this.objectUrls.add(url);
                }
            }
            this.htmlPackageReady = true;
            this.htmlLoadingStatus = null;
        } catch (error) {
            this.htmlPackageReady = false;
            throw error;
        } finally {
            this.htmlPackageLoading = false;
        }
    }

    resolveZipRelativePath(basePath, relativePath) {
        const baseParts = this.normalizeZipPath(basePath).split('/');
        baseParts.pop();
        const relParts = this.normalizeZipPath(relativePath).split('/');
        for (const part of relParts) {
            if (!part || part === '.') continue;
            if (part === '..') {
                baseParts.pop();
            } else {
                baseParts.push(part);
            }
        }
        return baseParts.join('/');
    }

    rewriteHtmlAssetUrls(htmlText, entryPath) {
        const replaceRef = (match, quote, ref) => {
            if (!ref || /^(https?:|data:|blob:|\/\/|#|mailto:)/i.test(ref)) {
                return match;
            }
            const resolved = this.resolveZipRelativePath(entryPath, ref);
            const blobUrl = this.htmlBlobByPath.get(resolved);
            if (!blobUrl) {
                return match;
            }
            return match.replace(ref, blobUrl);
        };
        return htmlText
            .replace(/(\s(?:src|href))=(["'])([^"']+)\2/gi, (match, attr, quote, ref) =>
                replaceRef(`${attr}=${quote}${ref}${quote}`, quote, ref)
            )
            .replace(/url\((['"]?)([^'")]+)\1\)/gi, (match, quote, ref) => {
                if (!ref || /^(https?:|data:|blob:|\/\/)/i.test(ref)) {
                    return match;
                }
                const resolved = this.resolveZipRelativePath(entryPath, ref);
                const blobUrl = this.htmlBlobByPath.get(resolved);
                return blobUrl ? `url(${quote || ''}${blobUrl}${quote || ''})` : match;
            });
    }

    async resolveCurrentHtmlFrame() {
        if (!this.needsHtmlRendering) {
            this.htmlFrameUrl = null;
            return;
        }
        try {
            await this.ensureHtmlPackageLoaded();
            const entry = this.normalizeZipPath(this.currentSequence?.htmlEntryPoint);
            if (!entry) {
                throw new Error('HTML entry point is missing on this slide.');
            }
            let htmlText = this.htmlTextByPath.get(entry);
            if (!htmlText) {
                // Try case-insensitive / basename fallback
                const match = [...this.htmlTextByPath.keys()].find(
                    (key) => key.toLowerCase() === entry.toLowerCase() || key.toLowerCase().endsWith('/' + entry.toLowerCase())
                );
                if (!match) {
                    throw new Error(`HTML entry not found in package: ${entry}`);
                }
                htmlText = this.htmlTextByPath.get(match);
                const rewritten = this.rewriteHtmlAssetUrls(htmlText, match);
                if (this.htmlFrameObjectUrl) {
                    URL.revokeObjectURL(this.htmlFrameObjectUrl);
                    this.objectUrls.delete(this.htmlFrameObjectUrl);
                }
                this.htmlFrameObjectUrl = URL.createObjectURL(new Blob([rewritten], { type: 'text/html' }));
                this.objectUrls.add(this.htmlFrameObjectUrl);
                this.htmlFrameUrl = this.htmlFrameObjectUrl;
                this.htmlLoadError = null;
                this.htmlSlideReady = true;
                this.htmlLoadingStatus = null;
                return;
            }
            const rewritten = this.rewriteHtmlAssetUrls(htmlText, entry);
            if (this.htmlFrameObjectUrl) {
                URL.revokeObjectURL(this.htmlFrameObjectUrl);
                this.objectUrls.delete(this.htmlFrameObjectUrl);
            }
            this.htmlFrameObjectUrl = URL.createObjectURL(new Blob([rewritten], { type: 'text/html' }));
            this.objectUrls.add(this.htmlFrameObjectUrl);
            this.htmlFrameUrl = this.htmlFrameObjectUrl;
            this.htmlLoadError = null;
            this.htmlSlideReady = true;
            this.htmlLoadingStatus = null;
        } catch (error) {
            this.htmlFrameUrl = null;
            this.htmlLoadError = this.reduceError(error);
            this.htmlSlideReady = true;
        } finally {
            this.htmlLoadingStatus = null;
        }
    }

    clearHtmlBlobCache() {
        this.htmlBlobByPath.forEach((url) => {
            try {
                URL.revokeObjectURL(url);
            } catch (e) {
                // ignore
            }
            this.objectUrls.delete(url);
        });
        this.htmlBlobByPath.clear();
        this.htmlTextByPath.clear();
        if (this.htmlFrameObjectUrl) {
            try {
                URL.revokeObjectURL(this.htmlFrameObjectUrl);
            } catch (e) {
                // ignore
            }
            this.objectUrls.delete(this.htmlFrameObjectUrl);
            this.htmlFrameObjectUrl = null;
        }
        this.htmlFrameUrl = null;
        this.htmlPackageReady = false;
    }

    parseDelimitedValues(value) {
        return String(value || '')
            .split(/[;,]/)
            .map((item) => item.trim())
            .filter(Boolean);
    }

    getUncapturedMessagesForCurrentSlide() {
        return this.parseDelimitedValues(this.currentSequence?.messageNames).filter(
            (messageName) => !this.capturedMessageNames.has(messageName.toUpperCase())
        );
    }

    initializeMessageOverlay(messageNames) {
        this.overlayMessages = messageNames.map((messageName, index) => ({
            key: `${messageName}_${index}`,
            messageName,
            sentiment: null
        }));
        this.showMessageOverlay = true;
    }

    handleOpenMessageCapture() {
        const uncapturedMessages = this.getUncapturedMessagesForCurrentSlide();
        if (!uncapturedMessages.length) {
            this.showToast('Messages captured', 'All messages on this slide are already saved.', 'info');
            return;
        }
        this.pendingNavigation = null;
        this.initializeMessageOverlay(uncapturedMessages);
    }

    requestNavigation(applyNavigation) {
        const uncapturedMessages = this.getUncapturedMessagesForCurrentSlide();
        if (uncapturedMessages.length > 0) {
            this.pendingNavigation = applyNavigation;
            this.initializeMessageOverlay(uncapturedMessages);
            return;
        }
        applyNavigation();
    }

    handleOverlaySentimentChange(event) {
        const messageName = event.currentTarget.dataset.name;
        const sentiment = event.currentTarget.dataset.sentiment;
        this.overlayMessages = this.overlayMessages.map((message) =>
            message.messageName === messageName ? { ...message, sentiment } : message
        );
    }

    async persistMessageResponses() {
        const serverSessionId = this.getServerSessionId();
        if (serverSessionId && navigator.onLine) {
            await saveMessageResponses({
                sessionId: serverSessionId,
                responses: this.messageResponses
            });
            return;
        }
        await queueOfflineAction({
            actionType: 'SAVE_MESSAGE_RESPONSES',
            clientSessionKey: this.getSessionKey(),
            responsesJson: JSON.stringify(this.messageResponses)
        });
        this.session = {
            ...this.session,
            messageResponses: [...this.messageResponses]
        };
    }

    async handleMessageOverlaySave() {
        if (this.isMessageOverlaySaveDisabled || !this.session?.id) {
            return;
        }
        const productName = this.overlayProductName;
        const newResponses = this.overlayMessages.map((message, index) => ({
            productName,
            messageName: message.messageName,
            sentiment: message.sentiment,
            sortOrder: this.messageResponses.length + index + 1
        }));

        const mergedByName = new Map(
            this.messageResponses.map((row) => [row.messageName.toUpperCase(), row])
        );
        newResponses.forEach((row) => {
            mergedByName.set(row.messageName.toUpperCase(), row);
        });
        this.messageResponses = Array.from(mergedByName.values()).map((row, index) => ({
            ...row,
            sortOrder: index + 1
        }));

        this.isSavingMessageResponse = true;
        try {
            await this.persistMessageResponses();
            newResponses.forEach((row) => {
                this.capturedMessageNames.add(row.messageName.toUpperCase());
            });
            this.showMessageOverlay = false;
            this.overlayMessages = [];
            const continueNavigation = this.pendingNavigation;
            this.pendingNavigation = null;
            if (continueNavigation) {
                continueNavigation();
            }
        } catch (error) {
            this.showToast('Message save failed', this.reduceError(error), 'error');
        } finally {
            this.isSavingMessageResponse = false;
        }
    }

    handleMessageOverlayCancel() {
        this.showMessageOverlay = false;
        this.overlayMessages = [];
        this.pendingNavigation = null;
    }

    pauseTracking() {
        if (this.trackingPaused) {
            return;
        }
        this.flushDwell(true);
        this.trackingPaused = true;
        this.clearTimer();
    }

    resumeTracking() {
        this.trackingPaused = false;
        this.dwellAccumulator = 0;
        this.clearTimer();
        this.timerId = window.setInterval(() => {
            if (!this.trackingPaused) {
                this.dwellAccumulator += 1;
            }
        }, 1000);
    }

    toggleTracking() {
        if (this.trackingPaused) {
            this.resumeTracking();
        } else {
            this.pauseTracking();
        }
    }

    async sendSlideEvent(sequenceId, dwellSeconds, paused) {
        const serverSessionId = this.getServerSessionId();
        if (serverSessionId && navigator.onLine) {
            await logSlideEvent({
                sessionId: serverSessionId,
                sequenceId,
                dwellSeconds,
                trackingPaused: paused
            });
            return;
        }
        await queueOfflineAction({
            actionType: 'LOG_SLIDE_EVENT',
            clientSessionKey: this.getSessionKey(),
            sequenceId,
            dwellSeconds,
            trackingPaused: paused
        });
    }

    flushDwell(paused = false) {
        const seq = this.currentSequence;
        if (!seq || !this.session?.id || this.dwellAccumulator <= 0) {
            if (paused && this.session?.id) {
                this.sendSlideEvent(seq?.id, 0, true).catch(() => {
                    /* ignore pause sync errors */
                });
            }
            return;
        }
        const seconds = this.dwellAccumulator;
        this.dwellAccumulator = 0;
        this.sendSlideEvent(seq.id, seconds, paused).catch((error) => {
            this.showToast('Metric sync failed', this.reduceError(error), 'error');
        });
    }

    handlePrevious() {
        if (!this.canGoBack) {
            return;
        }
        this.requestNavigation(() => {
            this.flushDwell(false);
            this.currentIndex -= 1;
            this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
        });
    }

    handleNext() {
        if (!this.canGoForward) {
            return;
        }
        const current = this.currentSequence;
        if (current?.isMandatory && this.dwellAccumulator < 1) {
            this.showToast('Mandatory slide', 'Spend time on this slide before continuing.', 'warning');
            return;
        }
        this.requestNavigation(() => {
            this.flushDwell(false);
            this.currentIndex += 1;
            this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
        });
    }

    handleThumbClick(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (Number.isNaN(index) || index === this.currentIndex) {
            return;
        }
        const current = this.currentSequence;
        if (index > this.currentIndex && current?.isMandatory && this.dwellAccumulator < 1) {
            this.showToast('Mandatory slide', 'Spend time on this slide before continuing.', 'warning');
            return;
        }
        this.requestNavigation(() => {
            this.flushDwell(false);
            this.currentIndex = index;
            this.resetSlideReadyState();
            this.preloadAdjacentSlides();
            this.resumeTracking();
        });
    }

    handleComplete() {
        this.requestNavigation(() => {
            this.completePresentation();
        });
    }

    async completePresentation() {
        await this.flushDwellAndWait(false);
        this.clearTimer();
        try {
            const serverSessionId = this.getServerSessionId();
            if (serverSessionId && navigator.onLine) {
                this.session = await completeSession({ sessionId: serverSessionId });
            } else {
                await queueOfflineAction({
                    actionType: 'COMPLETE_SESSION',
                    clientSessionKey: this.getSessionKey(),
                    endedAtIso: new Date().toISOString(),
                    slidesPresentedCount: this.session?.slidesPresentedCount,
                    totalDurationSeconds: this.session?.totalDurationSeconds
                });
                this.session = { ...this.session, status: 'Completed' };
            }
            this.dispatchEvent(new CustomEvent('sessioncomplete', { detail: { session: this.session } }));
            this.showToast('Presentation complete', this.presentationName, 'success');
            this.dispatchClose();
        } catch (error) {
            this.showToast('Complete failed', this.reduceError(error), 'error');
        }
    }

    async handleCancel() {
        this.clearTimer();
        try {
            if (this.session?.id) {
                const serverSessionId = this.getServerSessionId();
                if (serverSessionId && navigator.onLine) {
                    await cancelSession({ sessionId: serverSessionId });
                } else {
                    await queueOfflineAction({
                        actionType: 'CANCEL_SESSION',
                        clientSessionKey: this.getSessionKey()
                    });
                }
            }
        } catch (error) {
            this.showToast('Cancel failed', this.reduceError(error), 'warning');
        }
        this.dispatchClose();
    }

    async flushDwellAndWait(paused = false) {
        const seq = this.currentSequence;
        if (!seq || !this.session?.id || this.dwellAccumulator <= 0) {
            if (paused && this.session?.id) {
                try {
                    await this.sendSlideEvent(seq?.id, 0, true);
                } catch (e) {
                    /* ignore pause sync errors */
                }
            }
            return;
        }
        const seconds = this.dwellAccumulator;
        this.dwellAccumulator = 0;
        try {
            await this.sendSlideEvent(seq.id, seconds, paused);
        } catch (error) {
            this.showToast('Metric sync failed', this.reduceError(error), 'error');
        }
    }

    dispatchClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    clearTimer() {
        if (this.timerId) {
            window.clearInterval(this.timerId);
            this.timerId = null;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}