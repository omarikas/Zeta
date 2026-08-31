import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import createPresentationDraft from '@salesforce/apex/ClmAdminController.createPresentationDraft';
import attachSlideImages from '@salesforce/apex/ClmAdminController.attachSlideImages';
import generateSequencesFromPageCount from '@salesforce/apex/ClmAdminController.generateSequencesFromPageCount';
import getSequences from '@salesforce/apex/ClmAdminController.getSequences';
import getPresentationDraft from '@salesforce/apex/ClmAdminController.getPresentationDraft';
import saveSequences from '@salesforce/apex/ClmAdminController.saveSequences';
import finalizePresentation from '@salesforce/apex/ClmAdminController.finalizePresentation';
import getProductOptions from '@salesforce/apex/ClmAdminController.getProductOptions';
import {
    countPdfPagesFromBuffer,
    readFileAsBase64,
    renderPdfSlideImages,
    withTimeout
} from 'c/clmPdfProcessor';

const SLIDE_IMAGE_BATCH_SIZE = 5;
const PDF_INIT_TIMEOUT_MS = 30000;
const PDF_PREVIEW_TOTAL_TIMEOUT_MS = 300000;

const STEPS = ['upload', 'sequences', 'setup'];
const MESSAGE_OPTIONS = [
    { label: 'EFFICACY', value: 'EFFICACY' },
    { label: 'INDICATION', value: 'INDICATION' },
    { label: 'SAFETY', value: 'SAFETY' },
    { label: 'SIDE EFFECTS', value: 'SIDE EFFECTS' },
    { label: 'USAGE', value: 'USAGE' },
    { label: 'DOSING', value: 'DOSING' },
    { label: 'SUPPORT', value: 'SUPPORT' }
];

export default class ClmPresentationWizard extends LightningElement {
    @api presentationId;

    currentStep = 0;
    draftPresentationId;
    fileName = '';
    formatType = 'PDF';
    pageCount = 1;
    sequences = [];
    productOptions = [];
    presentationProductIds = [];
    pickerProductIds = [];
    pickerMessageNames = [];
    selectedSequenceKeys = new Set();

    name = '';
    status = 'Available';
    productId;
    startDate;
    endDate;
    playerGesture = 'Tap Bottom';
    pinchZoom = 'Enabled';
    doubleTapZoom = 'Enabled';
    tags = '';
    publicContentUrl = '';
    allowEmail = false;
    territoryIdsJson = '[]';
    allowUnaligned = true;

    isSaving = false;
    isUploading = false;
    uploadProgress = 0;
    uploadStatus = '';
    pdfJsReady = false;

    formatOptions = [
        { label: 'PDF', value: 'PDF' },
        { label: 'HTML', value: 'HTML' },
        { label: 'ZIP', value: 'ZIP' }
    ];

    statusOptions = [
        { label: 'Available', value: 'Available' },
        { label: 'Draft', value: 'Draft' },
        { label: 'Unavailable', value: 'Unavailable' }
    ];

    messageOptions = MESSAGE_OPTIONS;

    @wire(getProductOptions)
    wiredProducts({ data }) {
        this.productOptions = data || [];
    }

    connectedCallback() {
        if (this.presentationId) {
            this.draftPresentationId = this.presentationId;
            this.currentStep = 1;
            this.loadPresentationDraft();
        }
    }

    get stepLabel() {
        return `Step ${this.currentStep + 1} of ${STEPS.length}`;
    }

    get isUploadStep() {
        return this.currentStep === 0;
    }

    get isSequenceStep() {
        return this.currentStep === 1;
    }

    get isSetupStep() {
        return this.currentStep === 2;
    }

    get canGoNext() {
        if (this.isUploading) {
            return false;
        }
        if (this.isUploadStep) {
            return !!this.draftPresentationId;
        }
        if (this.isSequenceStep) {
            return this.sequences.length > 0;
        }
        return !!this.name;
    }

    get isNextDisabled() {
        return !this.canGoNext || this.isSaving;
    }

    get isBackDisabled() {
        return this.isUploadStep || this.isUploading;
    }

    get sequenceRows() {
        return (this.sequences || []).map((seq) => ({
            ...seq,
            rowKey: seq.id || `seq-${seq.sequenceOrder}`,
            thumbnailUrl: seq.slideImageUrl || seq.thumbnailUrl,
            pageLabel: `Page ${seq.pageNumber || seq.sequenceOrder}`,
            isSelected: this.selectedSequenceKeys.has(seq.id || `seq-${seq.sequenceOrder}`)
        }));
    }

    get allSequencesSelected() {
        return this.sequences.length > 0 && this.selectedSequenceKeys.size === this.sequences.length;
    }

    get productsJson() {
        const names = this.presentationProductIds
            .map((id) => this.productOptions.find((opt) => opt.value === id)?.label)
            .filter(Boolean);
        return JSON.stringify({
            productIds: this.presentationProductIds,
            productNames: names
        });
    }

    get productIdsJsonForTerritory() {
        return JSON.stringify(this.presentationProductIds || []);
    }

    async handleFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.fileName = file.name;
        this.isUploading = true;
        this.isSaving = true;
        this.uploadProgress = 0;
        this.uploadStatus = 'Starting upload...';

        try {
            let pageCount = 1;

            let pdfBuffer;
            if (this.formatType === 'PDF') {
                this.uploadProgress = 10;
                this.uploadStatus = 'Reading PDF...';
                pdfBuffer = await file.arrayBuffer();
                pageCount = countPdfPagesFromBuffer(pdfBuffer);
                this.uploadProgress = 25;
                this.uploadStatus = `Creating ${pageCount} sequence${pageCount === 1 ? '' : 's'}...`;
            } else {
                this.uploadProgress = 15;
                this.uploadStatus = 'Uploading presentation file...';
            }

            const base64 = await readFileAsBase64(file);
            this.uploadProgress = 50;
            this.uploadStatus = 'Uploading presentation file...';
            const result = await createPresentationDraft({
                fileName: file.name,
                formatType: this.formatType,
                base64Data: base64,
                pageCount
            });

            this.draftPresentationId = result.presentationId;
            this.sequences = result.sequences || [];
            this.pageCount = result.pageCount || this.sequences.length || 1;
            this.name = file.name.replace(/\.[^.]+$/, '');

            if (this.formatType === 'PDF' && pdfBuffer) {
                await this.extractAndAttachSlideImages(pdfBuffer, this.pageCount);
            }

            this.uploadProgress = 100;
            this.uploadStatus = 'Upload complete';
            this.currentStep = 1;
            this.toast(
                'Upload complete',
                `Created ${this.pageCount} sequence${this.pageCount === 1 ? '' : 's'}.`,
                'success'
            );
        } catch (error) {
            this.toast('Upload failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
            this.isUploading = false;
        }
    }

    handleFormatChange(event) {
        this.formatType = event.detail.value;
    }

    handlePageCountChange(event) {
        this.pageCount = Number(event.detail.value) || 1;
    }

    async handleGenerateSequences() {
        if (!this.draftPresentationId) {
            return;
        }
        this.isSaving = true;
        try {
            this.sequences = await generateSequencesFromPageCount({
                presentationId: this.draftPresentationId,
                fileName: this.fileName || 'presentation',
                pageCount: this.pageCount
            });
            this.pageCount = this.sequences.length;
            this.toast('Sequences generated', `${this.sequences.length} slides created.`, 'success');
        } catch (error) {
            this.toast('Sequence generation failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleSequenceFieldChange(event) {
        const index = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : event.detail?.value ?? event.target.value;
        this.sequences = this.sequences.map((seq, idx) =>
            idx === index ? { ...seq, [field]: value } : seq
        );
    }

    handlePresentationProductsChange(event) {
        this.presentationProductIds = event.detail.value || [];
        if (this.presentationProductIds.length > 0) {
            this.productId = this.presentationProductIds[0];
        }
    }

    handlePickerProductsChange(event) {
        this.pickerProductIds = event.detail.value || [];
    }

    handlePickerMessagesChange(event) {
        this.pickerMessageNames = event.detail.value || [];
    }

    handleSequenceSelect(event) {
        const key = event.target.dataset.key;
        const checked = event.target.checked;
        const next = new Set(this.selectedSequenceKeys);
        if (checked) {
            next.add(key);
        } else {
            next.delete(key);
        }
        this.selectedSequenceKeys = next;
    }

    handleSelectAllSequences(event) {
        if (event.target.checked) {
            this.selectedSequenceKeys = new Set(
                this.sequences.map((seq) => seq.id || `seq-${seq.sequenceOrder}`)
            );
        } else {
            this.selectedSequenceKeys = new Set();
        }
    }

    handleApplyProductsMessages() {
        const productLabels = this.pickerProductIds
            .map((id) => this.productOptions.find((opt) => opt.value === id)?.label)
            .filter(Boolean)
            .join('; ');
        const messageLabels = (this.pickerMessageNames || []).join('; ');
        if (!productLabels && !messageLabels) {
            this.toast('Nothing to apply', 'Select products or messages first.', 'warning');
            return;
        }
        if (this.selectedSequenceKeys.size === 0) {
            this.toast('Select slides', 'Check one or more slides in the grid.', 'warning');
            return;
        }

        this.sequences = this.sequences.map((seq) => {
            const key = seq.id || `seq-${seq.sequenceOrder}`;
            if (!this.selectedSequenceKeys.has(key)) {
                return seq;
            }
            return {
                ...seq,
                productNames: productLabels || seq.productNames,
                messageNames: messageLabels || seq.messageNames
            };
        });
        this.toast('Applied', 'Products and messages updated on selected slides.', 'success');
    }

    applyPresentationProductsToEmptySlides() {
        if (!this.presentationProductIds?.length) {
            return;
        }
        const productLabels = this.presentationProductIds
            .map((id) => this.productOptions.find((opt) => opt.value === id)?.label)
            .filter(Boolean)
            .join('; ');
        if (!productLabels) {
            return;
        }
        this.sequences = this.sequences.map((seq) => ({
            ...seq,
            productNames: seq.productNames?.trim() ? seq.productNames : productLabels
        }));
    }

    syncSequencesFromDom() {
        const inputs = this.template.querySelectorAll('[data-index][data-field]');
        if (!inputs?.length || !this.sequences?.length) {
            return;
        }
        const sequences = [...this.sequences];
        inputs.forEach((input) => {
            const index = Number(input.dataset.index);
            const field = input.dataset.field;
            if (Number.isNaN(index) || !field || index < 0 || index >= sequences.length) {
                return;
            }
            const value = field === 'isMandatory' ? input.checked : input.value ?? '';
            sequences[index] = { ...sequences[index], [field]: value };
        });
        this.sequences = sequences;
    }

    async loadPresentationDraft() {
        if (!this.draftPresentationId) {
            return;
        }
        const draft = await getPresentationDraft({ presentationId: this.draftPresentationId });
        if (draft) {
            this.name = draft.name;
            this.status = draft.status;
            this.formatType = draft.formatType;
            this.productId = draft.productId;
            this.territoryIdsJson = draft.territoryIdsJson || '[]';
            this.allowUnaligned = draft.allowUnaligned === true;
            try {
                const parsed = JSON.parse(draft.products || '{}');
                this.presentationProductIds = parsed.productIds || [];
            } catch (e) {
                this.presentationProductIds = [];
            }
        }
        await this.loadSequences();
    }

    async loadSequences() {
        if (!this.draftPresentationId) {
            return;
        }
        this.sequences = await getSequences({ presentationId: this.draftPresentationId });
        this.pageCount = this.sequences.length || 1;
    }

    async handleSaveSequences() {
        if (!this.draftPresentationId) {
            return;
        }
        this.isSaving = true;
        try {
            this.applyPresentationProductsToEmptySlides();
            this.syncSequencesFromDom();
            this.sequences = await saveSequences({
                presentationId: this.draftPresentationId,
                sequences: this.sequences
            });
            this.pageCount = this.sequences.length || 1;
            this.selectedSequenceKeys = new Set();
            this.toast('Sequences saved', 'Slide metadata updated.', 'success');
        } catch (error) {
            this.toast('Save failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleTerritoryChange(event) {
        this.territoryIdsJson = event.detail.territoryIdsJson;
        this.allowUnaligned = event.detail.allowUnaligned;
    }

    handleSetupChange(event) {
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : event.detail?.value ?? event.target.value;
        this[field] = value;
    }

    async handleNext() {
        if (this.isSequenceStep) {
            await this.handleSaveSequences();
        }
        if (this.currentStep < STEPS.length - 1) {
            this.currentStep += 1;
        }
    }

    handleBack() {
        if (this.currentStep > 0) {
            this.currentStep -= 1;
        }
    }

    async handleFinish() {
        if (!this.draftPresentationId) {
            this.toast('Cannot save', 'Upload a presentation first.', 'error');
            return;
        }
        if (!this.name?.trim()) {
            this.toast('Name required', 'Enter a presentation name.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await finalizePresentation({
                presentationId: this.draftPresentationId,
                name: this.name.trim(),
                status: this.status,
                formatType: this.formatType,
                productId: this.productId || this.presentationProductIds[0],
                products: this.productsJson,
                startDate: this.startDate,
                endDate: this.endDate,
                playerGesture: this.playerGesture,
                pinchZoom: this.pinchZoom,
                doubleTapZoom: this.doubleTapZoom,
                tags: this.tags,
                publicContentUrl: this.publicContentUrl,
                allowEmail: this.allowEmail,
                territoryIdsJson: this.territoryIdsJson,
                allowUnaligned: this.allowUnaligned
            });
            this.toast('Presentation saved', this.name, 'success');
            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            this.toast('Finalize failed', error?.body?.message || error?.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async ensurePdfJs() {
        if (this.pdfJsReady && window.pdfjsLib) {
            return window.pdfjsLib;
        }
        await withTimeout(
            loadScript(this, `${PDFJS}/pdf.min.js`),
            PDF_INIT_TIMEOUT_MS,
            'PDF library failed to load.'
        );
        if (!window.pdfjsLib) {
            throw new Error('PDF library failed to initialize.');
        }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = `${PDFJS}/pdf.worker.min.js`;
        this.pdfJsReady = true;
        return window.pdfjsLib;
    }

    async extractAndAttachSlideImages(arrayBuffer, pageCount) {
        try {
            await withTimeout(
                this.renderAndSaveSlidePreviews(arrayBuffer, pageCount),
                PDF_PREVIEW_TOTAL_TIMEOUT_MS,
                'Slide preview generation timed out.'
            );
        } catch (error) {
            this.toast(
                'Slide previews skipped',
                'The PDF uploaded, but slide previews could not be generated. The player will use PDF rendering.',
                'warning'
            );
        }
    }

    async renderAndSaveSlidePreviews(arrayBuffer, pageCount) {
        this.uploadProgress = 60;
        this.uploadStatus = 'Rendering slide previews...';
        const pdfjsLib = await withTimeout(
            this.ensurePdfJs(),
            PDF_INIT_TIMEOUT_MS,
            'PDF library failed to initialize.'
        );
        const images = await renderPdfSlideImages(pdfjsLib, arrayBuffer, pageCount, {
            onProgress: (pageNum, total) => {
                const renderProgress = 60 + Math.round((pageNum / total) * 25);
                this.uploadProgress = renderProgress;
                this.uploadStatus = `Rendering slide previews (${pageNum} of ${total})...`;
            }
        });

        if (!images.length) {
            throw new Error('No slide previews were generated.');
        }

        for (let index = 0; index < images.length; index += SLIDE_IMAGE_BATCH_SIZE) {
            const batch = images.slice(index, index + SLIDE_IMAGE_BATCH_SIZE);
            const progress = 85 + Math.round(((index + batch.length) / images.length) * 14);
            this.uploadProgress = progress;
            this.uploadStatus = `Saving slide previews (${Math.min(index + batch.length, images.length)} of ${images.length})...`;
            this.sequences = await attachSlideImages({
                presentationId: this.draftPresentationId,
                images: batch
            });
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}