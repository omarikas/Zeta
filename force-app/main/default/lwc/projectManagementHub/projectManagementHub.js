import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getProjects from '@salesforce/apex/ProjectManagementController.getProjects';
import createProject from '@salesforce/apex/ProjectManagementController.createProject';
import { getProjectTypeConfig, getStatusClass } from 'c/projectTypeUtils';

const CAMPAIGN_RECORD_TYPE = 'Campaign_Project';

export default class ProjectManagementHub extends NavigationMixin(LightningElement) {
    @track projects = [];
    @track selectedBu = 'ALL';
    @track selectedStatus = 'ALL';
    @track showCreateModal = false;
    @track isSaving = false;
    @track createForm = {
        name: '',
        recordTypeDeveloperName: 'Campaign_Project',
        status: 'Planning',
        businessUnit: 'GIT',
        campaignType: '',
        startDate: null,
        endDate: null,
        totalBudget: null,
        description: ''
    };

    wiredProjectsResult;
    error;
    isLoading = true;

    buOptions = [
        { label: 'All BUs', value: 'ALL' },
        { label: 'GIT', value: 'GIT' },
        { label: 'Diabetes', value: 'Diabetes' },
        { label: 'Cluster', value: 'Cluster' },
        { label: 'CHC', value: 'CHC' }
    ];

    filterBuOptions = [
        { label: 'GIT', value: 'GIT' },
        { label: 'Diabetes', value: 'Diabetes' },
        { label: 'Cluster', value: 'Cluster' },
        { label: 'CHC', value: 'CHC' }
    ];

    statusOptions = [
        { label: 'All Statuses', value: 'ALL' },
        { label: 'Planning', value: 'Planning' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'Completed', value: 'Completed' },
        { label: 'On Hold', value: 'On Hold' }
    ];

    createStatusOptions = [
        { label: 'Planning', value: 'Planning' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'Completed', value: 'Completed' },
        { label: 'On Hold', value: 'On Hold' }
    ];

    recordTypeOptions = [
        { label: 'Campaign Project', value: 'Campaign_Project' },
        { label: 'Frequent Evaluation Project', value: 'Frequent_Evaluation_Project' }
    ];

    campaignTypeOptions = [
        { label: 'Chemipharm 360', value: 'Chemipharm 360' },
        { label: 'Chemipharm Competition', value: 'Chemipharm Competition' },
        { label: 'Promotional Events', value: 'Promotional Events' },
        { label: 'Signage', value: 'Signage' },
        { label: 'E-commerce', value: 'E-commerce' },
        { label: 'Pharmacy Brochures', value: 'Pharmacy Brochures' },
        { label: 'Other', value: 'Other' }
    ];

    @wire(getProjects, { businessUnit: '$selectedBu', statusFilter: '$selectedStatus' })
    wiredProjects(result) {
        this.wiredProjectsResult = result;
        const { data, error } = result;
        if (data) {
            this.projects = data.map((project) => {
                const progressPercent = Math.min(100, Math.max(0, project.progressPercent || 0));
                const budgetPercent = Math.min(100, Math.max(0, project.budgetUtilizationPercent || 0));
                const budgetTrackingAvailable = project.budgetTrackingAvailable !== false;
                const typeConfig = getProjectTypeConfig(project.recordTypeName);
                return {
                    ...project,
                    typeIconName: typeConfig.iconName,
                    typeIconClass: `pm-hub-type-icon ${typeConfig.cssClass}`,
                    progressDisplay: `${Math.round(progressPercent)}%`,
                    progressBarStyle: `width: ${progressPercent}%`,
                    roundTableDisplay: `${project.roundTableDone || 0} / ${project.roundTableTarget || 0}`,
                    budgetDisplay: this.formatBudget(
                        project.budgetSpent,
                        project.totalBudget,
                        budgetTrackingAvailable
                    ),
                    budgetPercentDisplay: budgetTrackingAvailable
                        ? `${Math.round(budgetPercent)}% utilized`
                        : (project.budgetTrackingLabel || 'Budget tracking coming soon'),
                    budgetBarStyle: `width: ${budgetTrackingAvailable ? budgetPercent : 0}%`,
                    openTaskDisplay: project.openTaskCount || 0,
                    teamSizeDisplay: project.teamSize || 0,
                    statusClass: getStatusClass(project.status),
                    buChipClass: 'pm-hub-bu-chip',
                    kpis: (project.kpis || []).map((kpi) => {
                        const attainment = Math.min(
                            100,
                            Math.max(0, Math.round(kpi.attainmentPercent || 0))
                        );
                        return {
                            ...kpi,
                            attainmentDisplay: `${attainment}%`,
                            kpiBarStyle: `width: ${attainment}%`
                        };
                    })
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unable to load projects.';
            this.projects = [];
        }
        this.isLoading = false;
    }

    get hasProjects() {
        return this.projects && this.projects.length > 0;
    }

    get projectCountLabel() {
        const count = this.projects?.length || 0;
        return `${count} project${count === 1 ? '' : 's'}`;
    }

    get showFilteredEmpty() {
        return !this.isLoading && !this.error && !this.hasProjects && this.hasActiveFilters;
    }

    get showInitialEmpty() {
        return !this.isLoading && !this.error && !this.hasProjects && !this.hasActiveFilters;
    }

    get hasActiveFilters() {
        return this.selectedBu !== 'ALL' || this.selectedStatus !== 'ALL';
    }

    get showCampaignTypeField() {
        return this.createForm.recordTypeDeveloperName === CAMPAIGN_RECORD_TYPE;
    }

    buildEmptyCreateForm() {
        return {
            name: '',
            recordTypeDeveloperName: CAMPAIGN_RECORD_TYPE,
            status: 'Planning',
            businessUnit: 'GIT',
            campaignType: '',
            startDate: null,
            endDate: null,
            totalBudget: null,
            description: ''
        };
    }

    handleBuChange(event) {
        this.isLoading = true;
        this.selectedBu = event.detail.value;
    }

    handleStatusChange(event) {
        this.isLoading = true;
        this.selectedStatus = event.detail.value;
    }

    handleNewProject() {
        this.createForm = this.buildEmptyCreateForm();
        this.showCreateModal = true;
    }

    handleCloseCreateModal() {
        if (this.isSaving) {
            return;
        }
        this.showCreateModal = false;
    }

    handleCreateFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) {
            return;
        }
        this.createForm = {
            ...this.createForm,
            [field]: event.detail.value
        };
    }

    async handleCreateProject() {
        const nameInput = this.template.querySelector('[data-field="name"]');
        if (nameInput && !nameInput.reportValidity()) {
            return;
        }
        if (!this.createForm.name?.trim()) {
            this.showToast('Validation', 'Project name is required.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const projectId = await createProject({
                name: this.createForm.name.trim(),
                recordTypeDeveloperName: this.createForm.recordTypeDeveloperName,
                status: this.createForm.status,
                businessUnit: this.createForm.businessUnit,
                campaignType: this.showCampaignTypeField ? this.createForm.campaignType : null,
                startDate: this.createForm.startDate || null,
                endDate: this.createForm.endDate || null,
                totalBudget: this.createForm.totalBudget ? Number(this.createForm.totalBudget) : null,
                description: this.createForm.description?.trim() || null
            });

            this.showCreateModal = false;
            this.showToast('Success', 'Project created successfully.', 'success');
            await refreshApex(this.wiredProjectsResult);
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: projectId,
                    objectApiName: 'Pharma_Project__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.showToast(
                'Unable to create project',
                error.body?.message || error.message || 'Unexpected error.',
                'error'
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleProjectClick(event) {
        const projectId = event.currentTarget?.dataset?.id;
        if (!projectId) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: projectId,
                objectApiName: 'Pharma_Project__c',
                actionName: 'view'
            }
        });
    }

    handleProjectKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleProjectClick(event);
        }
    }

    getStatusClass(status) {
        switch (status) {
            case 'In Progress':
                return 'pm-hub-status pm-hub-status--progress';
            case 'Completed':
                return 'pm-hub-status pm-hub-status--completed';
            case 'On Hold':
                return 'pm-hub-status pm-hub-status--hold';
            default:
                return 'pm-hub-status pm-hub-status--planning';
        }
    }

    formatBudget(spent, total, isAvailable = true) {
        if (!isAvailable) {
            return 'Coming soon';
        }
        const s = spent || 0;
        const t = total || 0;
        return t > 0 ? `${s.toLocaleString()} / ${t.toLocaleString()}` : `${s.toLocaleString()}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}