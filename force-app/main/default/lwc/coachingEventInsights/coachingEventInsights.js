import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import MANAGER_SCORE from '@salesforce/schema/Coaching_Event__c.Manager_Total_Score__c';
import EMPLOYEE_SCORE from '@salesforce/schema/Coaching_Event__c.Employee_Total_Score__c';
import PREVIOUS_SCORE from '@salesforce/schema/Coaching_Event__c.Previous_Score__c';
import SECTION_SCORES_JSON from '@salesforce/schema/Coaching_Event__c.Section_Scores_JSON__c';
import ACTION_PLAN from '@salesforce/schema/Coaching_Event__c.Recommended_Action_Plan__c';
import STATUS from '@salesforce/schema/Coaching_Event__c.Status__c';

const FIELDS = [
    MANAGER_SCORE,
    EMPLOYEE_SCORE,
    PREVIOUS_SCORE,
    SECTION_SCORES_JSON,
    ACTION_PLAN,
    STATUS
];

function formatScore(value) {
    if (value == null || value === '') {
        return '—';
    }
    return `${Number(value).toFixed(1)}%`;
}

function parseInsights(sectionScoresJson) {
    const strengths = [];
    const weaknesses = [];

    if (!sectionScoresJson) {
        return { strengths, weaknesses };
    }

    try {
        const sections = JSON.parse(sectionScoresJson);
        Object.keys(sections).forEach((sectionName) => {
            const section = sections[sectionName];
            (section.strengths || []).forEach((item) => {
                strengths.push({ id: `${sectionName}-s-${item}`, label: item, section: sectionName });
            });
            (section.weaknesses || []).forEach((item) => {
                weaknesses.push({ id: `${sectionName}-w-${item}`, label: item, section: sectionName });
            });
        });
    } catch (e) {
        // ignore malformed JSON
    }

    return { strengths, weaknesses };
}

export default class CoachingEventInsights extends LightningElement {
    @api recordId;

    managerScore;
    employeeScore;
    previousScore;
    status;
    actionPlan;
    strengths = [];
    weaknesses = [];

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data }) {
        if (!data) {
            return;
        }

        this.managerScore = getFieldValue(data, MANAGER_SCORE);
        this.employeeScore = getFieldValue(data, EMPLOYEE_SCORE);
        this.previousScore = getFieldValue(data, PREVIOUS_SCORE);
        this.status = getFieldValue(data, STATUS);
        this.actionPlan = getFieldValue(data, ACTION_PLAN);

        const parsed = parseInsights(getFieldValue(data, SECTION_SCORES_JSON));
        this.strengths = parsed.strengths;
        this.weaknesses = parsed.weaknesses;
    }

    get managerScoreDisplay() {
        return formatScore(this.managerScore);
    }

    get employeeScoreDisplay() {
        return formatScore(this.employeeScore);
    }

    get previousScoreDisplay() {
        return formatScore(this.previousScore);
    }

    get hasScores() {
        return this.managerScore != null || this.employeeScore != null;
    }

    get hasStrengths() {
        return this.strengths.length > 0;
    }

    get hasWeaknesses() {
        return this.weaknesses.length > 0;
    }

    get hasActionPlan() {
        return Boolean(this.actionPlan);
    }

    get actionPlanItems() {
        if (!this.actionPlan) {
            return [];
        }
        return this.actionPlan
            .split('\n')
            .map((line) => line.trim())
            .filter((line) => line.length > 0)
            .map((line, index) => ({ id: `action-${index}`, text: line }));
    }

    get scoreDelta() {
        if (this.managerScore == null || this.previousScore == null) {
            return null;
        }
        return Number(this.managerScore) - Number(this.previousScore);
    }

    get scoreDeltaDisplay() {
        if (this.scoreDelta == null) {
            return null;
        }
        const sign = this.scoreDelta > 0 ? '+' : '';
        return `${sign}${this.scoreDelta.toFixed(1)}%`;
    }

    get scoreDeltaClass() {
        if (this.scoreDelta == null) {
            return 'delta-neutral';
        }
        if (this.scoreDelta > 0) {
            return 'delta-positive';
        }
        if (this.scoreDelta < 0) {
            return 'delta-negative';
        }
        return 'delta-neutral';
    }

    get statusBadgeClass() {
        const base = 'status-badge';
        const normalized = (this.status || '').toLowerCase().replace(/\s+/g, '-');
        return `${base} status-${normalized}`;
    }
}