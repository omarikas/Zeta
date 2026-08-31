import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import openCourse from '@salesforce/apex/MyLearningController.openCourse';
import startLesson from '@salesforce/apex/MyLearningController.startLesson';
import markLessonComplete from '@salesforce/apex/MyLearningController.markLessonComplete';

export default class LearningCoursePlayer extends LightningElement {
    @api courseInstanceId;
    _initialPlayer;
    @track player;
    @track selectedItem;
    busy = false;

    @api
    get initialPlayer() {
        return this._initialPlayer;
    }
    set initialPlayer(value) {
        this._initialPlayer = value;
        if (value) {
            this.applyPlayer(value);
        }
    }

    get curriculum() {
        return (this.player?.curriculum || []).map((item) => {
            const selected = this.selectedItem?.instanceId === item.instanceId;
            return {
                ...item,
                itemClass: `curriculum-item${selected ? ' is-selected' : ''}${
                    item.completed ? ' is-complete' : ''
                }`,
                iconName: this.iconForType(item.materialType),
                statusIcon: item.completed ? 'utility:success' : 'utility:radio_button'
            };
        });
    }

    get progressLabel() {
        return `${Math.round(this.player?.progress || 0)}%`;
    }

    get progressStyle() {
        return `width:${Math.round(this.player?.progress || 0)}%`;
    }

    get isQuiz() {
        return this.selectedItem?.materialType === 'Quiz';
    }

    get isContent() {
        return (
            this.selectedItem &&
            ['Video', 'PDF', 'Lesson'].includes(this.selectedItem.materialType)
        );
    }

    get canMarkComplete() {
        return this.isContent && !this.selectedItem?.completed;
    }

    get showCertificateCta() {
        return this.player?.canShowCertificate === true;
    }

    get previousDisabled() {
        return !this.hasPrevious;
    }

    get nextDisabled() {
        return !this.hasNext;
    }

    get hasPrevious() {
        return this.currentIndex > 0;
    }

    get hasNext() {
        return (
            this.currentIndex >= 0 &&
            this.currentIndex < (this.player?.curriculum?.length || 0) - 1
        );
    }

    get currentIndex() {
        if (!this.selectedItem || !this.player?.curriculum) {
            return -1;
        }
        return this.player.curriculum.findIndex(
            (item) => item.instanceId === this.selectedItem.instanceId
        );
    }

    applyPlayer(player) {
        this.player = player;
        const selectedId = player.selectedInstanceId;
        this.selectedItem =
            (player.curriculum || []).find((item) => item.instanceId === selectedId) ||
            (player.curriculum || [])[0] ||
            null;
        if (this.selectedItem?.instanceId) {
            startLesson({ instanceId: this.selectedItem.instanceId }).catch(() => {});
        }
    }

    iconForType(type) {
        switch (type) {
            case 'Video':
                return 'utility:video';
            case 'PDF':
                return 'utility:file';
            case 'Quiz':
                return 'utility:question';
            default:
                return 'utility:knowledge_base';
        }
    }

    async handleSelectLesson(event) {
        const instanceId = event.currentTarget.dataset.id;
        const item = (this.player.curriculum || []).find((row) => row.instanceId === instanceId);
        if (!item) {
            return;
        }
        this.selectedItem = item;
        try {
            await startLesson({ instanceId });
        } catch (error) {
            this.toast('Unable to start lesson', error?.body?.message || error?.message, 'error');
        }
    }

    async handleMarkComplete() {
        if (!this.selectedItem?.instanceId) {
            return;
        }
        this.busy = true;
        try {
            const player = await markLessonComplete({ instanceId: this.selectedItem.instanceId });
            this.applyPlayer(player);
            this.dispatchEvent(
                new CustomEvent('refresh', {
                    detail: {
                        player,
                        showCertificate: player.canShowCertificate === true
                    }
                })
            );
            if (player.canShowCertificate) {
                this.dispatchEvent(
                    new CustomEvent('showcertificate', {
                        detail: { courseInstanceId: this.courseInstanceId }
                    })
                );
            } else {
                this.goNext();
            }
        } catch (error) {
            this.toast('Unable to complete lesson', error?.body?.message || error?.message, 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleQuizComplete(event) {
        const detail = event.detail || {};
        try {
            const player = await openCourse({
                courseInstanceId: this.courseInstanceId,
                selectedMaterialId: this.selectedItem?.materialId
            });
            this.applyPlayer(player);
            this.dispatchEvent(
                new CustomEvent('refresh', {
                    detail: {
                        player,
                        showCertificate: detail.canShowCertificate === true
                    }
                })
            );
            if (detail.canShowCertificate) {
                this.dispatchEvent(
                    new CustomEvent('showcertificate', {
                        detail: { courseInstanceId: this.courseInstanceId }
                    })
                );
            }
        } catch (error) {
            this.toast('Unable to refresh course', error?.body?.message || error?.message, 'error');
        }
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleShowCertificate() {
        this.dispatchEvent(
            new CustomEvent('showcertificate', {
                detail: { courseInstanceId: this.courseInstanceId }
            })
        );
    }

    goPrevious() {
        if (!this.hasPrevious) {
            return;
        }
        const item = this.player.curriculum[this.currentIndex - 1];
        this.selectedItem = item;
        startLesson({ instanceId: item.instanceId }).catch(() => {});
    }

    goNext() {
        if (!this.hasNext) {
            return;
        }
        const item = this.player.curriculum[this.currentIndex + 1];
        this.selectedItem = item;
        startLesson({ instanceId: item.instanceId }).catch(() => {});
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}