import { LightningElement, api, wire } from 'lwc';
import getProjectTimeline from '@salesforce/apex/ProjectManagementService.getProjectTimeline';
import createProjectMilestone from '@salesforce/apex/ProjectManagementService.createProjectMilestone';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { formatDisplayDate } from 'c/projectTypeUtils';

const TYPE_LABELS = {
    start: 'Kickoff',
    end: 'Target End',
    milestone: 'Milestone',
    kpi: 'KPI',
    activity: 'Activity',
    task: 'Task'
};

const STATUS_OPTIONS = [
    { label: 'Planned', value: 'Planned' },
    { label: 'Complete', value: 'Complete' }
];

export default class ProjectTimeline extends LightningElement {
    @api recordId;
    timeline;
    error;
    isLoading = true;
    showMilestoneModal = false;
    isSaving = false;
    milestoneName = '';
    milestoneDate;
    milestoneDescription = '';
    milestoneStatus = 'Planned';
    selectedMilestone;

    wiredTimelineResult;

    statusOptions = STATUS_OPTIONS;

    @wire(getProjectTimeline, { projectId: '$recordId' })
    wiredTimeline(result) {
        this.wiredTimelineResult = result;
        const { data, error } = result;
        this.isLoading = false;
        if (data) {
            this.timeline = {
                ...data,
                progressPercent: Math.round(data.progressPercent || 0),
                progressStyle: `width: ${Math.round(data.progressPercent || 0)}%`,
                todayMarkerStyle: `left: ${Math.round(data.progressPercent || 0)}%`,
                startDateDisplay: formatDisplayDate(data.startDate),
                endDateDisplay: formatDisplayDate(data.endDate),
                events: (data.events || []).map((event) => this.decorateEvent(event))
            };
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unable to load project timeline.';
            this.timeline = undefined;
        }
    }

    decorateEvent(event) {
        const typeLabel = TYPE_LABELS[event.eventType] || 'Event';
        const isMilestone = event.eventType === 'milestone';
        return {
            ...event,
            dateDisplay: formatDisplayDate(event.eventDate),
            typeLabel,
            isMilestone,
            markerClass: `proj-timeline-marker proj-timeline-marker--${event.eventType || 'default'}`,
            itemClass: event.isComplete
                ? 'proj-timeline-item proj-timeline-item--complete'
                : 'proj-timeline-item',
            markerStyle: `left: ${event.positionPercent || 0}%`,
            listItemClass: isMilestone
                ? 'proj-timeline-item proj-timeline-item--milestone'
                : event.isComplete
                    ? 'proj-timeline-item proj-timeline-item--complete'
                    : 'proj-timeline-item'
        };
    }

    get hasTimeline() {
        return this.timeline != null;
    }

    get hasEvents() {
        return this.timeline?.events?.length > 0;
    }

    get hasMilestones() {
        return (this.timeline?.events || []).some((event) => event.eventType === 'milestone');
    }

    get milestoneEvents() {
        return (this.timeline?.events || []).filter((event) => event.eventType === 'milestone');
    }

    get emptyMessage() {
        if (!this.hasMilestones) {
            return 'No milestones yet — add your first milestone.';
        }
        if (this.timeline?.startDate || this.timeline?.endDate) {
            return 'Add KPIs, tasks, or project activities to populate the timeline.';
        }
        return 'Set project start and end dates to enable the executive timeline.';
    }

    get isViewMode() {
        return this.selectedMilestone != null && !this.isSaving;
    }

    get modalTitle() {
        return this.isViewMode ? 'Milestone Details' : 'Add Milestone';
    }

    get isSaveDisabled() {
        return this.isSaving || !this.milestoneName?.trim();
    }

    handleOpenAddMilestone() {
        this.resetMilestoneForm();
        this.showMilestoneModal = true;
    }

    handleCloseModal() {
        this.showMilestoneModal = false;
        this.selectedMilestone = null;
        this.resetMilestoneForm();
    }

    handleMilestoneClick(event) {
        const milestoneId = event.currentTarget.dataset.id;
        const milestone = (this.timeline?.events || []).find((item) => item.id === milestoneId);
        if (!milestone) {
            return;
        }
        this.selectedMilestone = milestone;
        this.milestoneName = milestone.title;
        this.milestoneDate = milestone.eventDate;
        this.milestoneDescription = milestone.subtitle === 'Project milestone' ? '' : milestone.subtitle;
        this.milestoneStatus = milestone.status || 'Planned';
        this.showMilestoneModal = true;
    }

    handleNameChange(event) {
        this.milestoneName = event.target.value;
    }

    handleDateChange(event) {
        this.milestoneDate = event.target.value;
    }

    handleDescriptionChange(event) {
        this.milestoneDescription = event.target.value;
    }

    handleStatusChange(event) {
        this.milestoneStatus = event.detail.value;
    }

    async handleSaveMilestone() {
        if (!this.milestoneName?.trim()) {
            return;
        }
        if (this.selectedMilestone) {
            this.handleCloseModal();
            return;
        }

        this.isSaving = true;
        try {
            await createProjectMilestone({
                projectId: this.recordId,
                name: this.milestoneName.trim(),
                targetDate: this.milestoneDate || null,
                description: this.milestoneDescription || null,
                status: this.milestoneStatus || 'Planned'
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Milestone added',
                    message: 'The project timeline has been updated.',
                    variant: 'success'
                })
            );
            this.handleCloseModal();
            await refreshApex(this.wiredTimelineResult);
        } catch (saveError) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save milestone',
                    message: saveError.body?.message || saveError.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    resetMilestoneForm() {
        this.milestoneName = '';
        this.milestoneDate = null;
        this.milestoneDescription = '';
        this.milestoneStatus = 'Planned';
        this.selectedMilestone = null;
    }
}