import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMyCourses from '@salesforce/apex/MyLearningController.getMyCourses';
import openCourse from '@salesforce/apex/MyLearningController.openCourse';

export default class MyLearning extends LightningElement {
    @track courses = [];
    @track player;
    @track showCertificate = false;
    courseInstanceId;
    loading = true;
    errorMessage;

    @wire(getMyCourses)
    wiredCourses({ data, error }) {
        this.loading = false;
        if (data) {
            this.courses = data.map((c) => ({
                ...c,
                progressLabel: `${Math.round(c.progress || 0)}%`,
                progressStyle: `width:${Math.round(c.progress || 0)}%`
            }));
            this.errorMessage = null;
        } else if (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load learning.';
        }
    }

    get hasCourses() {
        return this.courses.length > 0;
    }

    get showCatalog() {
        return !this.player && !this.showCertificate;
    }

    get showPlayer() {
        return !!this.player && !this.showCertificate;
    }

    async handleContinue(event) {
        const instanceId = event.currentTarget.dataset.id;
        this.loading = true;
        try {
            this.player = await openCourse({
                courseInstanceId: instanceId,
                selectedMaterialId: null
            });
            this.courseInstanceId = instanceId;
            this.showCertificate = false;
        } catch (error) {
            this.toast('Unable to open course', error?.body?.message || error?.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    handleShowCertificateFromCard(event) {
        this.courseInstanceId = event.currentTarget.dataset.id;
        this.player = null;
        this.showCertificate = true;
    }

    handleShowCertificate(event) {
        this.courseInstanceId = event.detail?.courseInstanceId || this.courseInstanceId;
        this.showCertificate = true;
    }

    handleBackToCatalog() {
        this.player = null;
        this.showCertificate = false;
        this.courseInstanceId = null;
    }

    handlePlayerRefresh(event) {
        this.player = event.detail?.player || this.player;
        if (event.detail?.showCertificate) {
            this.showCertificate = true;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}