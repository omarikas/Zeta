import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getEvaluationData from '@salesforce/apex/CoachingEventController.getEvaluationData';
import saveEvaluation from '@salesforce/apex/CoachingEventController.saveEvaluation';
import requestSelfEvaluation from '@salesforce/apex/CoachingEventController.requestSelfEvaluation';

function getScaleLabel(question, value) {
    if (value == null) return '';
    const point = (question.scalePoints || []).find((p) => p.value === value);
    return point?.label || String(value);
}

function getScaleWeight(question, value) {
    if (value == null) return 0;
    const point = (question.scalePoints || []).find((p) => p.value === value);
    return point?.weight || 0;
}

function buildAnswerMap(responsesJson) {
    const map = {};
    if (!responsesJson) return map;
    try {
        const parsed = JSON.parse(responsesJson);
        (parsed.answers || []).forEach((a) => {
            map[a.questionId] = { ...a };
        });
    } catch (e) {
        /* ignore */
    }
    return map;
}

function buildSections(questions, answerMap, isEditMode, userRole) {
    const sectionMap = new Map();
    const sorted = [...questions].sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));

    sorted.forEach((q) => {
        if (q.type !== 'scale') return;
        const sectionName = q.section || 'General';
        if (!sectionMap.has(sectionName)) {
            sectionMap.set(sectionName, { name: sectionName, questions: [] });
        }
        const answer = answerMap[q.id] || {};
        const managerValue = answer.managerValue ?? null;
        const employeeValue = answer.employeeValue ?? null;
        const scaleMin = q.scaleMin ?? 1;
        const scaleMax = q.scaleMax ?? 6;
        const pointCount = scaleMax - scaleMin + 1;

        const scalePoints = [];
        for (let v = scaleMin; v <= scaleMax; v++) {
            const pct = pointCount <= 1 ? 0 : ((v - scaleMin) / (pointCount - 1)) * 100;
            scalePoints.push({
                value: v,
                key: `${q.id}_pt_${v}`,
                leftStyle: `left: ${pct}%`,
                isManagerSelected: managerValue === v,
                isEmployeeSelected: employeeValue === v,
                managerVariant: managerValue === v ? 'brand' : 'neutral',
                employeeVariant: employeeValue === v ? 'success' : 'neutral'
            });
        }

        const managerPct =
            managerValue != null && pointCount > 1
                ? ((managerValue - scaleMin) / (pointCount - 1)) * 100
                : null;
        const employeePct =
            employeeValue != null && pointCount > 1
                ? ((employeeValue - scaleMin) / (pointCount - 1)) * 100
                : null;

        const hasGap =
            managerValue != null &&
            employeeValue != null &&
            Math.abs(managerValue - employeeValue) >= 2;

        const canEditManager = isEditMode && (userRole === 'manager' || userRole === 'admin');
        const canEditEmployee = isEditMode && (userRole === 'employee' || userRole === 'admin');

        sectionMap.get(sectionName).questions.push({
            id: q.id,
            label: q.question,
            scaleMin,
            scaleMax,
            scalePoints,
            managerValue,
            employeeValue,
            managerLabel: getScaleLabel(q, managerValue),
            employeeLabel: getScaleLabel(q, employeeValue),
            scaleMinLabel: q.scaleMinLabel || String(scaleMin),
            scaleMaxLabel: q.scaleMaxLabel || String(scaleMax),
            managerMarkerStyle: managerPct != null ? `left: ${managerPct}%` : '',
            employeeMarkerStyle: employeePct != null ? `left: ${employeePct}%` : '',
            managerBadgeStyle: managerPct != null ? `left: ${managerPct}%` : '',
            employeeBadgeStyle: employeePct != null ? `left: ${employeePct}%` : '',
            showManagerMarker: managerValue != null,
            showEmployeeMarker: employeeValue != null,
            managerComments: answer.managerComments || '',
            employeeComments: answer.employeeComments || '',
            hasGap,
            cardClass: hasGap ? 'competency-card gap-highlight' : 'competency-card',
            canEditManager,
            canEditEmployee,
            isManagerReadonly: !canEditManager,
            isEmployeeReadonly: !canEditEmployee,
            showManagerComments: userRole !== 'employee' || isEditMode,
            showEmployeeComments: userRole !== 'manager' || isEditMode
        });
    });

    return Array.from(sectionMap.values());
}

export default class CoachingEventEvaluation extends LightningElement {
    @api recordId;

    @track sections = [];
    @track isEditMode = false;
    @track isLoading = true;
    @track isSaving = false;
    @track managerTotalScore;
    @track employeeTotalScore;
    @track previousScore;
    @track status;
    @track userRole = 'admin';
    @track selfEvaluationRequested = false;
    @track activeSections = [];

    templateQuestions = [];
    answerMap = {};
    wiredDataResult;

    @wire(getEvaluationData, { eventId: '$recordId' })
    wiredData(result) {
        this.wiredDataResult = result;
        const { data, error } = result;
        if (data) {
            this.applyEvaluationData(data);
            this.isLoading = false;
        } else if (error) {
            this.isLoading = false;
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    applyEvaluationData(data) {
        this.managerTotalScore = data.managerTotalScore;
        this.employeeTotalScore = data.employeeTotalScore;
        this.previousScore = data.previousScore;
        this.status = data.status;
        this.userRole = data.userRole;
        this.selfEvaluationRequested = data.selfEvaluationRequested;

        try {
            const template = JSON.parse(data.templateJson || '{}');
            this.templateQuestions = template.questions || [];
        } catch (e) {
            this.templateQuestions = [];
        }

        this.answerMap = buildAnswerMap(data.responsesJson);
        this.rebuildSections();
        if (this.activeSections.length === 0 && this.sections.length > 0) {
            this.activeSections = this.sections.map((s) => s.name);
        }
    }

    rebuildSections() {
        this.sections = buildSections(
            this.templateQuestions,
            this.answerMap,
            this.isEditMode,
            this.userRole
        );
    }

    handleEdit() {
        this.isEditMode = true;
        this.rebuildSections();
    }

    handleCancelEdit() {
        this.isEditMode = false;
        if (this.wiredDataResult?.data) {
            this.applyEvaluationData(this.wiredDataResult.data);
        }
    }

    async handleSave() {
        this.isSaving = true;
        const responsesJson = JSON.stringify({
            version: '1.0',
            eventId: this.recordId,
            templateVersion: '1.2',
            answers: Object.values(this.answerMap),
            computedAt: new Date().toISOString()
        });

        try {
            const result = await saveEvaluation({
                eventId: this.recordId,
                responsesJson,
                status: this.status === 'Draft' || this.status === 'Planned'
                    ? 'Available for Scoring'
                    : this.status
            });
            this.managerTotalScore = result.managerTotalScore;
            this.employeeTotalScore = result.employeeTotalScore;
            this.isEditMode = false;
            this.showToast('Saved', 'Evaluation saved successfully.', 'success');
            getRecordNotifyChange([{ recordId: this.recordId }]);
            await refreshApex(this.wiredDataResult);
        } catch (error) {
            this.showToast('Save Failed', error.body?.message || error.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRequestSelfEval() {
        try {
            await requestSelfEvaluation({ eventId: this.recordId });
            this.selfEvaluationRequested = true;
            this.showToast('Requested', 'Self-evaluation requested from employee.', 'success');
            getRecordNotifyChange([{ recordId: this.recordId }]);
            await refreshApex(this.wiredDataResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    handleScaleClick(event) {
        if (!this.isEditMode) return;
        const questionId = event.currentTarget.dataset.questionId;
        const role = event.currentTarget.dataset.role;
        const value = parseInt(event.currentTarget.dataset.value, 10);

        const question = this.templateQuestions.find((q) => q.id === questionId);
        if (!question) return;

        if (role === 'manager' && this.userRole !== 'manager' && this.userRole !== 'admin') return;
        if (role === 'employee' && this.userRole !== 'employee' && this.userRole !== 'admin') return;

        const existing = this.answerMap[questionId] || { questionId };
        if (role === 'manager') {
            existing.managerValue = value;
            existing.managerScore = getScaleWeight(question, value);
            existing.managerLabel = getScaleLabel(question, value);
        } else {
            existing.employeeValue = value;
            existing.employeeScore = getScaleWeight(question, value);
            existing.employeeLabel = getScaleLabel(question, value);
        }
        this.answerMap = { ...this.answerMap, [questionId]: existing };
        this.rebuildSections();
    }

    handleCommentChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const role = event.currentTarget.dataset.role;
        const value = event.target.value;
        const existing = this.answerMap[questionId] || { questionId };
        if (role === 'manager') {
            existing.managerComments = value;
        } else {
            existing.employeeComments = value;
        }
        this.answerMap = { ...this.answerMap, [questionId]: existing };
    }

    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    handleCollapseAll() {
        this.activeSections = [];
    }

    handleExpandAll() {
        this.activeSections = this.sections.map((s) => s.name);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get formattedManagerScore() {
        return this.managerTotalScore != null ? `${this.managerTotalScore}%` : '—';
    }

    get formattedEmployeeScore() {
        return this.employeeTotalScore != null ? `${this.employeeTotalScore}%` : '—';
    }

    get formattedPreviousScore() {
        return this.previousScore != null ? `${this.previousScore}%` : '—';
    }

    get showRequestSelfEval() {
        return (this.userRole === 'manager' || this.userRole === 'admin') && !this.selfEvaluationRequested;
    }

    get hasSections() {
        return this.sections.length > 0;
    }
}