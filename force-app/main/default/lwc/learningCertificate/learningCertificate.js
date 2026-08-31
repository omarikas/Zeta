import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCertificate from '@salesforce/apex/MyLearningController.getCertificate';

export default class LearningCertificate extends LightningElement {
    _courseInstanceId;
    certificate;
    loading = true;
    errorMessage;

    @api
    get courseInstanceId() {
        return this._courseInstanceId;
    }
    set courseInstanceId(value) {
        this._courseInstanceId = value;
        if (value) {
            this.load();
        }
    }

    async load() {
        this.loading = true;
        this.errorMessage = null;
        try {
            this.certificate = await getCertificate({ courseInstanceId: this.courseInstanceId });
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Certificate unavailable.';
        } finally {
            this.loading = false;
        }
    }

    renderedCallback() {
        const host = this.template.querySelector('.certificate-html');
        if (host && this.certificate?.renderedHtml) {
            host.innerHTML = this.certificate.renderedHtml;
        }
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handlePrint() {
        window.print();
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}