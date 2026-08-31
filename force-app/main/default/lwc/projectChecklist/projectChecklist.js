import { LightningElement, api, wire } from 'lwc';
import getProjectChecklist from '@salesforce/apex/ProjectManagementService.getProjectChecklist';

export default class ProjectChecklist extends LightningElement {
    @api recordId;
    checklist;
    error;
    isLoading = true;

    @wire(getProjectChecklist, { projectId: '$recordId' })
    wiredChecklist({ data, error }) {
        this.isLoading = false;
        if (data) {
            const progressPercent = Math.round(data.progressPercent || 0);
            this.checklist = {
                ...data,
                progressPercent,
                progressLabel: `${data.completeCount || 0} / ${data.totalCount || 0} complete`,
                ringStyle: `--proj-check-ring: ${progressPercent * 3.6}deg`,
                items: (data.items || []).map((item) => ({
                    ...item,
                    itemClass: item.isComplete
                        ? 'proj-check-item proj-check-item--complete'
                        : 'proj-check-item',
                    iconName: item.isComplete ? 'utility:check' : 'utility:steps'
                }))
            };
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unable to load checklist.';
            this.checklist = undefined;
        }
    }

    get hasChecklist() {
        return this.checklist != null;
    }

    get hasItems() {
        return this.checklist?.items?.length > 0;
    }
}