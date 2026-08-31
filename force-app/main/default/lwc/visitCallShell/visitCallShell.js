import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getCallReportPayload from '@salesforce/apex/VisitCallReportController.getCallReportPayload';
import saveCallReport from '@salesforce/apex/VisitCallReportController.saveCallReport';
import getWhatsAppSurveyContext from '@salesforce/apex/VisitSurveyLinkController.getWhatsAppSurveyContext';
import buildSurveyUrl from '@salesforce/apex/VisitSurveyLinkController.buildSurveyUrl';
import buildWhatsAppMessage from '@salesforce/apex/VisitSurveyLinkController.buildWhatsAppMessage';
import buildMeetingReminderMessage from '@salesforce/apex/VisitSurveyLinkController.buildMeetingReminderMessage';
import { getVisitStatusOptions, validateVisitStatusChange } from 'c/visitStatusUtils';
import { getVisitPayload, putVisitPayload } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

const SECTIONS = [
    { id: 'details', label: 'Details' },
    { id: 'affiliations', label: 'Affiliations' },
    { id: 'attendees', label: 'Attendees' },
    { id: 'products', label: 'Products' },
    { id: 'samples', label: 'Dispense' },
    { id: 'presentations', label: 'Presentations' }
];

const HCP_RECORD_TYPES = new Set(['SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount', 'Business_Contact']);

function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    return new Date(value).toLocaleString([], {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

function formatDate(value) {
    if (!value) {
        return '';
    }
    return new Date(value).toISOString().slice(0, 10);
}

export default class VisitCallShell extends NavigationMixin(LightningElement) {
    @api recordId;

    payload;
    wiredPayloadResult;
    isSaving = false;
    usingCachedPayload = false;
    activeSection = 'details';

    statusValue = 'Draft';
    visitObjective = '';
    visitNotes = '';
    nextVisitDate = '';
    cancellationReason = '';
    attendees = [];
    products = [];
    samples = [];

    showWhatsAppModal = false;
    showCoachingModal = false;
    showMedicalInquiryModal = false;
    coachingEventId;
    medicalInquiryCount = 0;
    whatsappLoading = false;
    whatsappError;
    surveyContext;
    selectedPhoneKey;
    selectedProductName;
    whatsappMessagePreview = '';

    connectedCallback() {
        if (isOfflineMode()) {
            this.loadCachedPayload();
        }
    }

    showReminderModal = false;
    reminderLoading = false;
    reminderError;
    reminderContext;
    selectedReminderPhoneKey;
    reminderMessagePreview = '';

    @wire(getCallReportPayload, { visitId: '$recordId' })
    wiredPayload(result) {
        this.wiredPayloadResult = result;
        if (result.data) {
            this.applyPayload(result.data);
            this.usingCachedPayload = false;
            putVisitPayload(this.recordId, result.data).catch(() => {
                // Best effort cache.
            });
        } else if (result.error || isOfflineMode()) {
            this.loadCachedPayload();
        }
    }

    get offlineHint() {
        return this.usingCachedPayload ? 'Showing cached visit data from device' : '';
    }

    async loadCachedPayload() {
        if (!this.recordId) {
            return;
        }
        try {
            const cached = await getVisitPayload(this.recordId);
            if (cached) {
                this.applyPayload(cached);
                this.usingCachedPayload = true;
            }
        } catch (error) {
            this.usingCachedPayload = false;
        }
    }

    get isLoading() {
        if (this.usingCachedPayload) {
            return false;
        }
        return !this.wiredPayloadResult || this.wiredPayloadResult.loading;
    }

    get errorMessage() {
        return this.wiredPayloadResult?.error?.body?.message || this.wiredPayloadResult?.error?.message;
    }

    get visit() {
        return this.payload?.visit;
    }

    get isLocked() {
        return this.visit?.isLocked;
    }

    get statusOptions() {
        return getVisitStatusOptions(this.visit?.startDateTime);
    }

    get showCancellationReason() {
        return this.statusValue === 'Cancelled';
    }

    get navSections() {
        return SECTIONS.map((section) => ({
            ...section,
            className:
                section.id === this.activeSection
                    ? 'nav-item nav-item-active'
                    : 'nav-item'
        }));
    }

    get isDetailsSection() {
        return this.activeSection === 'details';
    }

    get isAffiliationsSection() {
        return this.activeSection === 'affiliations';
    }

    get isAttendeesSection() {
        return this.activeSection === 'attendees';
    }

    get isProductsSection() {
        return this.activeSection === 'products';
    }

    get isSamplesSection() {
        return this.activeSection === 'samples';
    }

    get selectedBrandIds() {
        const ids = new Set();
        for (const row of this.products || []) {
            if (row.productType === 'Brand' && row.productId) {
                ids.add(row.productId);
            } else if (row.parentProductId) {
                ids.add(row.parentProductId);
            }
        }
        return [...ids];
    }

    get isPresentationsSection() {
        return this.activeSection === 'presentations';
    }

    get accountBadgeLabel() {
        const devName = this.visit?.accountRecordTypeDeveloperName || '';
        if (HCP_RECORD_TYPES.has(devName)) {
            return 'HCP';
        }
        if (devName === 'Institution_HCO') {
            return 'HCO';
        }
        return this.visit?.accountRecordTypeName || 'Account';
    }

    get accountBadgeClass() {
        return HCP_RECORD_TYPES.has(this.visit?.accountRecordTypeDeveloperName || '')
            ? 'account-badge account-badge-hcp'
            : 'account-badge account-badge-hco';
    }

    get statusBadgeClass() {
        const status = this.visit?.status || 'Draft';
        return `status-badge status-badge-${(status || 'draft').toLowerCase()}`;
    }

    get isDoubleVisit() {
        return this.visit?.isDoubleVisit === true;
    }

    get hasLinkedCoachingEvent() {
        return !!(this.coachingEventId || this.visit?.coachingEventId);
    }

    get coachingButtonLabel() {
        return this.hasLinkedCoachingEvent ? 'Open Coaching Form' : 'Create Coaching Event';
    }

    get medicalInquiryButtonLabel() {
        return this.medicalInquiryCount > 0
            ? `Record Medical Inquiry (${this.medicalInquiryCount})`
            : 'Record Medical Inquiry';
    }

    get accountMetaLine() {
        return [this.visit?.accountSpecialty, this.visit?.accountCity].filter(Boolean).join(' · ');
    }

    get startLabel() {
        return formatDateTime(this.visit?.startDateTime);
    }

    get endLabel() {
        return formatDateTime(this.visit?.endDateTime);
    }

    handleOpenAccount() {
        if (!this.visit?.accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.visit.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    applyPayload(data) {
        this.payload = data;
        const visit = data.visit;
        this.statusValue = visit.status || 'Draft';
        this.visitObjective = visit.visitObjective || '';
        this.visitNotes = visit.visitNotes || '';
        this.nextVisitDate = formatDate(visit.nextVisitDate);
        this.cancellationReason = visit.cancellationReason || '';
        this.attendees = data.attendees || [];
        this.products = data.products || [];
        this.samples = data.samples || [];
        this.coachingEventId = visit.coachingEventId;
    }

    handleCoachingAction() {
        this.showCoachingModal = true;
    }

    handleCloseCoachingModal() {
        this.showCoachingModal = false;
    }

    async handleCoachingCreated() {
        await refreshApex(this.wiredPayloadResult);
    }

    async handleCoachingSubmitted() {
        await refreshApex(this.wiredPayloadResult);
    }

    handleMedicalInquiryAction() {
        this.showMedicalInquiryModal = true;
    }

    handleCloseMedicalInquiryModal() {
        this.showMedicalInquiryModal = false;
    }

    handleMedicalInquiryCreated() {
        this.medicalInquiryCount += 1;
    }

    handleNavClick(event) {
        this.activeSection = event.currentTarget.dataset.section;
    }

    handleStatusChange(event) {
        this.statusValue = event.detail.value;
        if (this.statusValue !== 'Cancelled') {
            this.cancellationReason = '';
        }
    }

    handleObjectiveChange(event) {
        this.visitObjective = event.detail.value;
    }

    handleNotesChange(event) {
        this.visitNotes = event.detail.value;
    }

    handleNextVisitChange(event) {
        this.nextVisitDate = event.detail.value;
    }

    handleCancellationChange(event) {
        this.cancellationReason = event.detail.value;
    }

    handleAttendeesChange(event) {
        this.attendees = event.detail.attendees;
    }

    handleProductsChange(event) {
        this.products = event.detail.products;
    }

    handleSamplesChange(event) {
        this.samples = event.detail.samples;
    }

    async handleSave() {
        const validationMessage = validateVisitStatusChange(
            this.statusValue,
            this.visit?.startDateTime,
            this.cancellationReason
        );
        if (validationMessage) {
            this.showToast('Validation', validationMessage, 'error');
            return;
        }
        this.isSaving = true;
        try {
            const saveRequest = {
                visitId: this.recordId || this.payload?.visit?.id,
                status: this.statusValue,
                visitObjective: this.visitObjective,
                visitNotes: this.visitNotes,
                clmPresentation: this.payload?.visit?.clmPresentation || null,
                nextVisitDate: this.nextVisitDate || null,
                cancellationReason: this.cancellationReason || null,
                attendees: this.attendees,
                products: this.products,
                samples: this.samples,
                clmSessions: []
            };

            if (!saveRequest.visitId) {
                this.showToast('Save failed', 'Visit Id is required.', 'error');
                return;
            }

            if (isOfflineMode()) {
                const offlinePayload = {
                    visit: {
                        ...this.payload?.visit,
                        status: this.statusValue,
                        visitObjective: this.visitObjective,
                        visitNotes: this.visitNotes,
                        nextVisitDate: this.nextVisitDate || null,
                        cancellationReason: this.cancellationReason || null
                    },
                    attendees: this.attendees,
                    products: this.products,
                    samples: this.samples,
                    clmSessions: this.payload?.clmSessions || []
                };
                await putVisitPayload(this.recordId || saveRequest.visitId, offlinePayload);
                await queueOfflineAction({
                    actionType: 'SAVE_CALL_REPORT',
                    visitId: saveRequest.visitId,
                    clientActionKey: `save_call_${saveRequest.visitId}_${Date.now()}`,
                    callReportJson: JSON.stringify(saveRequest)
                });
                this.applyPayload(offlinePayload);
                this.showToast(
                    'Saved offline',
                    'Visit changes will sync when you are back online.',
                    'success'
                );
                return;
            }

            const saved = await saveCallReport({ requestJson: JSON.stringify(saveRequest) });
            this.applyPayload(saved);
            await putVisitPayload(saveRequest.visitId, saved);
            await refreshApex(this.wiredPayloadResult);
            this.showToast('Visit saved', saved.visit.accountName, 'success');
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    get reminderPhoneOptions() {
        return (this.reminderContext?.phoneOptions || []).map((row) => ({
            label: row.label,
            value: row.key
        }));
    }

    get reminderSendDisabled() {
        return (
            this.reminderLoading ||
            !!this.reminderError ||
            !this.selectedReminderPhoneKey ||
            !this.reminderMessagePreview
        );
    }

    get phoneOptions() {
        return (this.surveyContext?.phoneOptions || []).map((row) => ({
            label: row.label,
            value: row.key
        }));
    }

    get productOptions() {
        return (this.surveyContext?.products || []).map((row) => ({
            label: row.productName,
            value: row.productName
        }));
    }

    get whatsappSendDisabled() {
        return (
            this.whatsappLoading ||
            !!this.whatsappError ||
            !this.selectedPhoneKey ||
            !this.selectedProductName
        );
    }

    async handleOpenWhatsAppModal() {
        this.showWhatsAppModal = true;
        this.whatsappLoading = true;
        this.whatsappError = undefined;
        try {
            this.surveyContext = await getWhatsAppSurveyContext({ visitId: this.recordId });
            if (!this.surveyContext?.phoneOptions?.length) {
                this.whatsappError = 'No phone numbers found on the account or attendees.';
            } else if (!this.surveyContext?.products?.length) {
                this.whatsappError = 'No territory products available for this visit.';
            } else {
                this.selectedPhoneKey = this.surveyContext.phoneOptions[0].key;
                this.selectedProductName = this.surveyContext.products[0].productName;
                await this.refreshWhatsAppPreview();
            }
        } catch (error) {
            this.whatsappError = this.reduceError(error);
        } finally {
            this.whatsappLoading = false;
        }
    }

    handleCloseWhatsAppModal() {
        this.showWhatsAppModal = false;
    }

    async handlePhoneChange(event) {
        this.selectedPhoneKey = event.detail.value;
        await this.refreshWhatsAppPreview();
    }

    async handleProductChange(event) {
        this.selectedProductName = event.detail.value;
        await this.refreshWhatsAppPreview();
    }

    async refreshWhatsAppPreview() {
        if (!this.selectedPhoneKey || !this.selectedProductName) {
            this.whatsappMessagePreview = '';
            return;
        }
        const phoneRow = (this.surveyContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedPhoneKey
        );
        const surveyUrl = await buildSurveyUrl({
            visitId: this.recordId,
            productName: this.selectedProductName
        });
        this.whatsappMessagePreview = await buildWhatsAppMessage({
            firstName: phoneRow?.firstName,
            productName: this.selectedProductName,
            surveyUrl
        });
    }

    async handleSendWhatsApp() {
        const phoneRow = (this.surveyContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedPhoneKey
        );
        if (!phoneRow?.phone) {
            this.showToast('WhatsApp', 'Select a valid phone number.', 'error');
            return;
        }
        const digits = phoneRow.phone.replace(/[^0-9]/g, '');
        if (!digits) {
            this.showToast('WhatsApp', 'Phone number is not valid for WhatsApp.', 'error');
            return;
        }
        if (!this.whatsappMessagePreview) {
            await this.refreshWhatsAppPreview();
        }
        const url = `https://wa.me/${digits}?text=${encodeURIComponent(this.whatsappMessagePreview)}`;
        window.open(url, '_blank');
        this.handleCloseWhatsAppModal();
        this.showToast('WhatsApp', 'Opening WhatsApp with the survey message.', 'success');
    }

    async handleOpenReminderModal() {
        this.showReminderModal = true;
        this.reminderLoading = true;
        this.reminderError = undefined;
        try {
            this.reminderContext = await getWhatsAppSurveyContext({ visitId: this.recordId });
            if (!this.reminderContext?.phoneOptions?.length) {
                this.reminderError = 'No phone numbers found on the account or attendees.';
            } else {
                this.selectedReminderPhoneKey = this.reminderContext.phoneOptions[0].key;
                await this.refreshReminderPreview();
            }
        } catch (error) {
            this.reminderError = this.reduceError(error);
        } finally {
            this.reminderLoading = false;
        }
    }

    handleCloseReminderModal() {
        this.showReminderModal = false;
    }

    async handleReminderPhoneChange(event) {
        this.selectedReminderPhoneKey = event.detail.value;
        await this.refreshReminderPreview();
    }

    async refreshReminderPreview() {
        if (!this.selectedReminderPhoneKey) {
            this.reminderMessagePreview = '';
            return;
        }
        const phoneRow = (this.reminderContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedReminderPhoneKey
        );
        if (!phoneRow) {
            this.reminderMessagePreview = '';
            return;
        }
        this.reminderMessagePreview = await buildMeetingReminderMessage({
            visitId: this.recordId,
            recipientAccountName: phoneRow.accountName || phoneRow.firstName
        });
    }

    async handleSendReminderWhatsApp() {
        const phoneRow = (this.reminderContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedReminderPhoneKey
        );
        if (!phoneRow?.phone) {
            this.showToast('WhatsApp', 'Select a valid phone number.', 'error');
            return;
        }
        const digits = phoneRow.phone.replace(/[^0-9]/g, '');
        if (!digits) {
            this.showToast('WhatsApp', 'Phone number is not valid for WhatsApp.', 'error');
            return;
        }
        if (!this.reminderMessagePreview) {
            await this.refreshReminderPreview();
        }
        const url = `https://wa.me/${digits}?text=${encodeURIComponent(this.reminderMessagePreview)}`;
        window.open(url, '_blank');
        this.handleCloseReminderModal();
        this.showToast('WhatsApp', 'Opening WhatsApp with the meeting reminder.', 'success');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}