import { LightningElement, track } from 'lwc';
import getMonthlyTimecardSummary from '@salesforce/apex/FieldRepHomeController.getMonthlyTimecardSummary';

export default class FieldRepHomeMonthlyTimecard extends LightningElement {
    @track isLoading = true;
    @track summary = {};

    connectedCallback() {
        void this.loadSummary();
    }

    async loadSummary() {
        this.isLoading = true;
        try {
            const data = await getMonthlyTimecardSummary({ contextUserId: null });
            this.summary = {
                ...data,
                tiles: this.buildTiles(data)
            };
        } catch (e) {
            this.summary = { tiles: [] };
        } finally {
            this.isLoading = false;
        }
    }

    buildTiles(data) {
        const tiles = [
            {
                id: 'field',
                label: 'Field days',
                value: data?.fieldDays ?? 0,
                help: 'Working weekdays minus public holidays, annual vacation, conference, and sick leave.'
            },
            {
                id: 'coached',
                label: 'Coached',
                value: data?.coachedDays ?? 0,
                help: 'Days this month where you received coaching visits.'
            },
            {
                id: 'activities',
                label: 'Activities recorded',
                value: data?.activityDays ?? 0,
                help: 'Days with submitted field activities on the system.'
            },
            {
                id: 'leaves',
                label: 'Leaves',
                value: data?.leaveDays ?? 0,
                help: 'Approved time-off days this month.'
            }
        ];
        if (data?.isManager) {
            tiles.splice(2, 0, {
                id: 'coaching',
                label: 'Coaching',
                value: data?.coachingDays ?? 0,
                help: 'Days you delivered coaching visits to your team.'
            });
        }
        if (data?.submittedCalls > 0) {
            tiles.push({
                id: 'calls',
                label: 'Submitted calls',
                value: data.submittedCalls,
                help: 'Total submitted calls recorded on your time card.'
            });
        }
        return tiles;
    }

    get hasTiles() {
        return (this.summary?.tiles || []).length > 0;
    }

    get monthLabel() {
        return this.summary?.monthLabel || 'This month';
    }
}