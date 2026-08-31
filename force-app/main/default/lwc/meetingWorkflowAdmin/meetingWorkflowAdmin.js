import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import listWorkflows from '@salesforce/apex/MeetingWorkflowAdminController.listWorkflows';
import getMeetingRecordTypes from '@salesforce/apex/MeetingWorkflowAdminController.getMeetingRecordTypes';
import getWorkflowDetail from '@salesforce/apex/MeetingWorkflowAdminController.getWorkflowDetail';
import publishWorkflow from '@salesforce/apex/MeetingWorkflowAdminController.publishWorkflow';
import seedTemplates from '@salesforce/apex/MeetingWorkflowAdminController.seedTemplates';
import createDraftWorkflow from '@salesforce/apex/MeetingWorkflowAdminController.createDraftWorkflow';
import cloneWorkflow from '@salesforce/apex/MeetingWorkflowAdminController.cloneWorkflow';
import saveStatuses from '@salesforce/apex/MeetingWorkflowAdminController.saveStatuses';
import saveRelatedListMatrix from '@salesforce/apex/MeetingWorkflowAdminController.saveRelatedListMatrix';
import saveApprovalSetup from '@salesforce/apex/MeetingWorkflowAdminController.saveApprovalSetup';
import saveRolePolicyBundle from '@salesforce/apex/MeetingWorkflowAdminController.saveRolePolicyBundle';

const RELATED_LISTS = [
    { key: 'attendees', label: 'Attendees', relatedObject: 'Meeting_Member__c', recordTypeFilter: 'Attendee;Non_Profiled_Attendee;Write_In' },
    { key: 'speakers', label: 'Speakers', relatedObject: 'Meeting_Member__c', recordTypeFilter: 'Speaker' },
    { key: 'colleagues', label: 'Colleagues / Users', relatedObject: 'Meeting_Member__c', recordTypeFilter: 'Colleague' },
    { key: 'expense-est', label: 'Expenses (Estimate)', relatedObject: 'Meeting_Expense__c', recordTypeFilter: 'Estimate' },
    { key: 'expense-act', label: 'Expenses (Actual)', relatedObject: 'Meeting_Expense__c', recordTypeFilter: 'Actual' },
    { key: 'locations', label: 'Logistics / Locations', relatedObject: 'Meeting_Location__c', recordTypeFilter: '' },
    { key: 'products', label: 'Products', relatedObject: 'Meeting_Product__c', recordTypeFilter: '' },
    { key: 'topics', label: 'Topics', relatedObject: 'Meeting_Topic__c', recordTypeFilter: '' },
    { key: 'budgets', label: 'Budgets', relatedObject: 'Meeting_Budget__c', recordTypeFilter: '' },
    { key: 'allocations', label: 'Expense Allocations', relatedObject: 'Meeting_Expense_Allocation__c', recordTypeFilter: '' }
];

const ACCESS_OPTIONS = [
    { label: 'Hidden', value: 'hidden' },
    { label: 'View only', value: 'view' },
    { label: 'Can add & edit', value: 'modify' }
];

const FIRST_APPROVER_OPTIONS = [
    { label: "Owner's manager", value: 'OwnerManager' },
    { label: 'No first approver', value: 'None' }
];

const SECOND_APPROVER_OPTIONS = [
    { label: 'None', value: 'None' },
    { label: 'Users in role(s)', value: 'UsersInRole' },
    { label: "Owner's manager's manager", value: 'OwnerManagerManager' },
    { label: 'Public group', value: 'PublicGroup' }
];

const FAMILY_OPTIONS = [
    { label: 'GPM', value: 'GPM' },
    { label: 'NLM', value: 'NLM' }
];

let localKey = 0;
function nextKey(prefix) {
    localKey += 1;
    return `${prefix}-${localKey}`;
}

function cellKey(listKey, statusValue) {
    return `${listKey}::${statusValue}`;
}

export default class MeetingWorkflowAdmin extends LightningElement {
    accessOptions = ACCESS_OPTIONS;
    firstApproverOptions = FIRST_APPROVER_OPTIONS;
    secondApproverOptions = SECOND_APPROVER_OPTIONS;
    familyOptions = FAMILY_OPTIONS;

    @track rows = [];
    @track recordTypeOptions = [];
    @track selectedId;
    @track detail;
    @track draftStatuses = [];
    @track matrixRows = [];
    @track skipRules = [];

    firstApproverMode = 'OwnerManager';
    secondApproverMode = 'None';
    secondApproverRoles = '';
    secondApproverGroup = '';
    ownerProfileFilter = '';
    createManagerAsApprover = true;
    showPublishConfirm = false;
    showNewModal = false;
    newName = '';
    newRecordType = '';
    newFamily = 'GPM';
    wiredListResult;
    busy = false;
    errorMessage;

    @wire(listWorkflows)
    wiredList(result) {
        this.wiredListResult = result;
        const { data, error } = result;
        if (data) {
            this.rows = data.map((row) => ({
                ...row,
                statusLabel: row.isArchived ? 'Archived' : row.isPublished ? 'Published' : 'Draft'
            }));
            this.errorMessage = undefined;
        } else if (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    @wire(getMeetingRecordTypes)
    wiredRecordTypes({ data, error }) {
        if (data) {
            this.recordTypeOptions = data.map((rt) => ({ label: rt.label, value: rt.value }));
            if (!this.newRecordType && data.length) {
                this.newRecordType = data[0].value;
            }
        } else if (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasSelection() {
        return !!this.selectedId;
    }

    get isEditable() {
        return this.detail?.isEditable === true;
    }

    get readOnlyBanner() {
        return this.hasSelection && !this.isEditable;
    }

    get workflow() {
        return this.detail?.workflow || {};
    }

    get workflowName() {
        return this.workflow.Name || '';
    }

    get workflowTypeLabel() {
        const match = this.recordTypeOptions.find((rt) => rt.value === this.workflow.Meeting_Record_Type__c);
        return match ? match.label : this.workflow.Meeting_Record_Type__c || '';
    }

    get versionLabel() {
        return this.workflow.Version__c != null ? `v${this.workflow.Version__c}` : 'Not published';
    }

    get statusBadge() {
        if (this.workflow.Is_Published__c) {
            return 'Published';
        }
        if (this.workflow.Is_Draft__c) {
            return 'Draft';
        }
        return 'Archived';
    }

    get typeCards() {
        const byType = {};
        this.recordTypeOptions.forEach((rt) => {
            byType[rt.value] = {
                value: rt.value,
                label: rt.label,
                published: null,
                draft: null,
                statusText: 'No workflow yet',
                actionLabel: 'Create workflow'
            };
        });
        this.rows.forEach((row) => {
            if (!byType[row.meetingRecordType]) {
                byType[row.meetingRecordType] = {
                    value: row.meetingRecordType,
                    label: row.meetingRecordType,
                    published: null,
                    draft: null
                };
            }
            const card = byType[row.meetingRecordType];
            if (row.isPublished) {
                card.published = row;
            } else if (row.isDraft) {
                card.draft = row;
            }
        });
        return Object.values(byType).map((card) => {
            if (card.draft && card.published) {
                card.statusText = `Published ${card.published.version ? 'v' + card.published.version : ''} · Draft in progress`;
                card.actionLabel = 'Continue draft';
            } else if (card.draft) {
                card.statusText = 'Draft — not live yet';
                card.actionLabel = 'Edit draft';
            } else if (card.published) {
                card.statusText = `Live · version ${card.published.version || 1}`;
                card.actionLabel = 'Open';
            } else {
                card.statusText = 'No workflow yet';
                card.actionLabel = 'Create workflow';
            }
            return card;
        });
    }

    get publishLogs() {
        return this.detail?.publishLogs || [];
    }

    get showSecondRole() {
        return this.secondApproverMode === 'UsersInRole';
    }

    get showSecondGroup() {
        return this.secondApproverMode === 'PublicGroup';
    }

    get statusOptions() {
        return this.draftStatuses.map((row) => ({
            label: row.Status_Label__c || row.Status_Value__c,
            value: row.Status_Value__c
        }));
    }

    async handleOpenType(event) {
        const typeValue = event.currentTarget.dataset.type;
        const card = this.typeCards.find((item) => item.value === typeValue);
        if (!card) {
            return;
        }
        if (card.draft) {
            await this.openWorkflow(card.draft.id);
            return;
        }
        if (card.published) {
            await this.openWorkflow(card.published.id);
            return;
        }
        this.newRecordType = typeValue;
        this.newName = `${card.label} workflow`;
        this.showNewModal = true;
    }

    async openWorkflow(workflowId) {
        this.busy = true;
        this.selectedId = workflowId;
        try {
            this.detail = await getWorkflowDetail({ workflowId });
            this.hydrateFromDetail();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    hydrateFromDetail() {
        this.draftStatuses = (this.detail?.statuses || []).map((row) => ({
            ...row,
            _key: row.Id || nextKey('status')
        }));
        this.buildMatrix();
        const rule = (this.detail?.approverRules || [])[0] || {};
        this.firstApproverMode = rule.First_Approver_Mode__c || 'OwnerManager';
        this.secondApproverMode = rule.Second_Approver_Mode__c || 'None';
        this.secondApproverRoles = rule.Second_Approver_Roles__c || '';
        this.secondApproverGroup = rule.Second_Approver_Group__c || '';
        this.ownerProfileFilter = rule.Owner_Profile_Filter__c || '';
        this.createManagerAsApprover = this.workflow.Create_Manager_As_Approver__c !== false;
        this.skipRules = (this.detail?.skipRules || []).map((row) => ({
            ...row,
            _key: row.Id || nextKey('skip')
        }));
    }

    buildMatrix() {
        const accessByKey = {};
        (this.detail?.rolePolicies || [])
            .filter((policy) => policy.Role_Key__c === 'Organizer')
            .forEach((policy) => {
                (policy.Related_Policies__r || []).forEach((related) => {
                    const list = RELATED_LISTS.find(
                        (item) =>
                            item.relatedObject === related.Related_Object__c &&
                            (item.recordTypeFilter || '') === (related.Record_Type_Filter__c || '')
                    );
                    if (!list) {
                        return;
                    }
                    let access = 'view';
                    if (related.Is_Visible__c === false) {
                        access = 'hidden';
                    } else if (related.Can_Create__c || related.Can_Edit__c) {
                        access = 'modify';
                    }
                    accessByKey[cellKey(list.key, policy.Status_Value__c)] = access;
                });
            });

        this.matrixRows = RELATED_LISTS.map((list) => ({
            ...list,
            cells: this.draftStatuses.map((status) => ({
                statusValue: status.Status_Value__c,
                statusLabel: status.Status_Label__c || status.Status_Value__c,
                key: cellKey(list.key, status.Status_Value__c),
                access: accessByKey[cellKey(list.key, status.Status_Value__c)] || 'view'
            }))
        }));
    }

    handleBack() {
        this.selectedId = undefined;
        this.detail = undefined;
        this.showPublishConfirm = false;
    }

    closeNewModal() {
        this.showNewModal = false;
    }

    handleNewName(event) {
        this.newName = event.detail.value;
    }

    handleNewFamily(event) {
        this.newFamily = event.detail.value;
    }

    async createNew() {
        if (!(this.newName || '').trim() || !this.newRecordType) {
            this.toast('Missing fields', 'Name and meeting type are required.', 'error');
            return;
        }
        this.busy = true;
        try {
            const id = await createDraftWorkflow({
                meetingRecordType: this.newRecordType,
                name: this.newName.trim(),
                family: this.newFamily
            });
            this.showNewModal = false;
            await refreshApex(this.wiredListResult);
            await this.openWorkflow(id);
            this.toast('Created', 'Draft workflow created. Add stages, then related-list and approval rules.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async cloneToDraft() {
        if (!this.selectedId) {
            return;
        }
        this.busy = true;
        try {
            const id = await cloneWorkflow({ sourceWorkflowId: this.selectedId });
            await refreshApex(this.wiredListResult);
            await this.openWorkflow(id);
            this.toast('Draft created', 'You can edit this copy. Publish when it should go live.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    addStatus() {
        const nextOrder =
            this.draftStatuses.reduce((max, row) => Math.max(max, Number(row.Sort_Order__c) || 0), 0) + 10;
        this.draftStatuses = [
            ...this.draftStatuses,
            {
                _key: nextKey('status'),
                Status_Value__c: '',
                Status_Label__c: '',
                Sort_Order__c: nextOrder,
                Is_Terminal__c: false
            }
        ];
        this.buildMatrix();
    }

    handleStatusField(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.draftStatuses = this.draftStatuses.map((row) =>
            row._key === key ? { ...row, [field]: value } : row
        );
        this.buildMatrix();
    }

    moveStatus(event) {
        const key = event.currentTarget.dataset.key;
        const direction = event.currentTarget.dataset.direction;
        const index = this.draftStatuses.findIndex((row) => row._key === key);
        const swapWith = direction === 'up' ? index - 1 : index + 1;
        if (index < 0 || swapWith < 0 || swapWith >= this.draftStatuses.length) {
            return;
        }
        const copy = [...this.draftStatuses];
        const current = copy[index];
        copy[index] = copy[swapWith];
        copy[swapWith] = current;
        this.draftStatuses = copy.map((row, idx) => ({ ...row, Sort_Order__c: (idx + 1) * 10 }));
        this.buildMatrix();
    }

    removeStatus(event) {
        const key = event.currentTarget.dataset.key;
        this.draftStatuses = this.draftStatuses.filter((row) => row._key !== key);
        this.buildMatrix();
    }

    async saveStatusPath() {
        if (!this.isEditable) {
            return;
        }
        this.busy = true;
        try {
            await saveStatuses({
                workflowId: this.selectedId,
                statuses: this.draftStatuses.map((row) => ({
                    Id: row.Id,
                    Status_Value__c: row.Status_Value__c,
                    Status_Label__c: row.Status_Label__c,
                    Sort_Order__c: Number(row.Sort_Order__c) || 0,
                    Is_Terminal__c: row.Is_Terminal__c === true
                }))
            });
            await this.openWorkflow(this.selectedId);
            this.toast('Saved', 'Stages updated. The meeting Path uses this order after you publish.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    handleMatrixAccess(event) {
        const listKey = event.target.dataset.listKey;
        const statusValue = event.target.dataset.status;
        const access = event.detail.value;
        this.matrixRows = this.matrixRows.map((row) => {
            if (row.key !== listKey) {
                return row;
            }
            return {
                ...row,
                cells: row.cells.map((cell) =>
                    cell.statusValue === statusValue ? { ...cell, access } : cell
                )
            };
        });
    }

    async saveMatrix() {
        if (!this.isEditable) {
            return;
        }
        this.busy = true;
        try {
            const cells = [];
            this.matrixRows.forEach((row) => {
                row.cells.forEach((cell) => {
                    cells.push({
                        statusValue: cell.statusValue,
                        relatedObject: row.relatedObject,
                        recordTypeFilter: row.recordTypeFilter,
                        accessLevel: cell.access
                    });
                });
            });
            await saveRelatedListMatrix({ workflowId: this.selectedId, cells });
            await this.openWorkflow(this.selectedId);
            this.toast('Saved', 'Related list access by stage is saved.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    handleApprovalField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this[field] = value;
    }

    addSkip() {
        const first = this.draftStatuses[0]?.Status_Value__c || 'PendingApproval';
        const lastWorking =
            this.draftStatuses.find((row) => !row.Is_Terminal__c && row.Status_Value__c !== first)?.Status_Value__c ||
            'Approved';
        this.skipRules = [
            ...this.skipRules,
            {
                _key: nextKey('skip'),
                Priority__c: (this.skipRules.length + 1) * 10,
                Record_Types__c: '*',
                Condition_Type__c: 'OwnerTitleContains',
                Condition_Values__c: '',
                From_Status__c: first,
                To_Status__c: lastWorking
            }
        ];
    }

    handleSkipField(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.skipRules = this.skipRules.map((row) => (row._key === key ? { ...row, [field]: value } : row));
    }

    removeSkip(event) {
        const key = event.currentTarget.dataset.key;
        this.skipRules = this.skipRules.filter((row) => row._key !== key);
    }

    async saveApprovals() {
        if (!this.isEditable) {
            return;
        }
        this.busy = true;
        try {
            await saveApprovalSetup({
                workflowId: this.selectedId,
                setup: {
                    firstApproverMode: this.firstApproverMode,
                    secondApproverMode: this.secondApproverMode,
                    secondApproverRoles: this.secondApproverRoles,
                    secondApproverGroup: this.secondApproverGroup,
                    ownerProfileFilter: this.ownerProfileFilter,
                    createManagerAsApprover: this.createManagerAsApprover,
                    skipRules: this.skipRules.map((row) => ({
                        Id: row.Id,
                        Priority__c: Number(row.Priority__c) || 0,
                        Record_Types__c: row.Record_Types__c || '*',
                        Condition_Type__c: row.Condition_Type__c || 'OwnerTitleContains',
                        Condition_Values__c: row.Condition_Values__c,
                        From_Status__c: row.From_Status__c,
                        To_Status__c: row.To_Status__c
                    }))
                }
            });
            await this.ensureDefaultActions();
            await this.openWorkflow(this.selectedId);
            this.toast('Saved', 'Approval routing is saved.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async ensureDefaultActions() {
        const statuses = this.draftStatuses.filter((row) => row.Status_Value__c);
        if (statuses.length < 2) {
            return;
        }
        const first = statuses[0];
        const second = statuses[1];
        const cancelled = statuses.find((row) => row.Status_Value__c === 'Cancelled');
        const approved = statuses.find((row) => row.Status_Value__c === 'Approved') || statuses[statuses.length - 1];

        const existingOrganizer = (this.detail?.rolePolicies || []).find(
            (policy) => policy.Status_Value__c === first.Status_Value__c && policy.Role_Key__c === 'Organizer'
        );
        await saveRolePolicyBundle({
            workflowId: this.selectedId,
            bundle: {
                policy: {
                    Id: existingOrganizer?.Id,
                    Status_Value__c: first.Status_Value__c,
                    Role_Key__c: 'Organizer',
                    Can_Edit_Meeting__c: true,
                    Can_Delete_Meeting__c: true
                },
                actions: [
                    {
                        Action_Key__c: 'SubmitForApproval',
                        Label__c: 'Submit for Approval',
                        Target_Status__c: second.Status_Value__c,
                        Sort_Order__c: 10
                    },
                    cancelled
                        ? {
                              Action_Key__c: 'Cancel',
                              Label__c: 'Cancel Meeting',
                              Target_Status__c: 'Cancelled',
                              Requires_Reason__c: true,
                              Sort_Order__c: 20
                          }
                        : null
                ].filter(Boolean)
            }
        });

        const pending = statuses.find((row) => (row.Status_Value__c || '').toLowerCase().includes('pending'));
        if (pending) {
            const pendingIndex = statuses.findIndex((row) => row.Status_Value__c === pending.Status_Value__c);
            const next = statuses[pendingIndex + 1] || approved;
            const existingApprover = (this.detail?.rolePolicies || []).find(
                (policy) => policy.Status_Value__c === pending.Status_Value__c && policy.Role_Key__c === 'Approver'
            );
            await saveRolePolicyBundle({
                workflowId: this.selectedId,
                bundle: {
                    policy: {
                        Id: existingApprover?.Id,
                        Status_Value__c: pending.Status_Value__c,
                        Role_Key__c: 'Approver',
                        Can_Edit_Meeting__c: false,
                        Can_Delete_Meeting__c: false
                    },
                    actions: [
                        {
                            Action_Key__c: 'Approve',
                            Label__c: 'Approve',
                            Target_Status__c: next.Status_Value__c,
                            Sort_Order__c: 10
                        },
                        {
                            Action_Key__c: 'Reject',
                            Label__c: 'Reject',
                            Target_Status__c: first.Status_Value__c,
                            Requires_Reason__c: true,
                            Sort_Order__c: 20
                        }
                    ]
                }
            });
        }
    }

    handlePublishSelected() {
        this.showPublishConfirm = true;
    }

    closePublishConfirm() {
        this.showPublishConfirm = false;
    }

    async confirmPublish() {
        this.showPublishConfirm = false;
        this.busy = true;
        try {
            const result = await publishWorkflow({ workflowId: this.selectedId });
            if (result.success) {
                this.toast('Published', result.message + ' Meetings of this type now use these stages and rules.', 'success');
                await refreshApex(this.wiredListResult);
                await this.openWorkflow(this.selectedId);
            } else {
                this.toast('Publish failed', result.message, 'error');
            }
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleSeed() {
        this.busy = true;
        try {
            const result = await seedTemplates({ publish: true });
            this.toast('Seed complete', result.message, 'success');
            await refreshApex(this.wiredListResult);
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}