import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import QUIZ_QUESTIONS_FIELD from '@salesforce/schema/Learning_Material__c.Quiz_Questions__c';
import MATERIAL_TYPE_FIELD from '@salesforce/schema/Learning_Material__c.Material_Type__c';
import Id from '@salesforce/schema/Learning_Material__c.Id';

const FIELDS = [QUIZ_QUESTIONS_FIELD, MATERIAL_TYPE_FIELD];
const JSON_VERSION = '1.1';

function buildEmptyOptions(questionId, count = 4) {
    return Array.from({ length: count }, (_, optIdx) => ({
        value: '',
        key: `${questionId}_opt_${optIdx}`
    }));
}

function buildScalePoints(min, max, existingPoints = [], maxPoints = 10) {
    const existingMap = new Map((existingPoints || []).map((p) => [p.value, p.weight]));
    const count = max - min + 1;
    const points = [];
    for (let value = min; value <= max; value++) {
        let weight;
        if (existingMap.has(value)) {
            weight = existingMap.get(value);
        } else {
            const idx = value - min;
            weight = count <= 1 ? maxPoints : Math.round((idx / (count - 1)) * maxPoints);
        }
        points.push({ value, weight, key: `scale_${value}` });
    }
    return points;
}

function getQuestionMaxPoints(question) {
    if (question.type === 'scale') {
        const weights = (question.scalePoints || []).map((p) => p.weight || 0);
        return weights.length ? Math.max(...weights) : (question.points || 0);
    }
    return question.points || 1;
}

function createQuestionByType(type, index, existingIds = []) {
    const id = generateQuestionId(index, existingIds);
    const base = {
        id,
        question: '',
        type,
        points: type === 'scale' ? 10 : 1,
        explanation: '',
        showAdvanced: false
    };

    if (type === 'scale') {
        return {
            ...base,
            scaleMin: 1,
            scaleMax: 5,
            scaleMinLabel: '',
            scaleMaxLabel: '',
            scalePoints: buildScalePoints(1, 5, [], base.points)
        };
    }

    if (type === 'multiple-choice') {
        return {
            ...base,
            options: buildEmptyOptions(id),
            correctAnswers: []
        };
    }

    return {
        ...base,
        options: buildEmptyOptions(id),
        correctAnswer: 0
    };
}

function generateQuestionId(preferredIndex, existingIds = []) {
    const idSet = new Set(existingIds);
    let candidate = `q${preferredIndex}`;
    let counter = preferredIndex;
    while (idSet.has(candidate)) {
        counter += 1;
        candidate = `q${counter}`;
    }
    return candidate;
}

function normalizeOptions(question) {
    const rawOptions = question.options || [];
    return rawOptions.map((opt, optIdx) => {
        const value = typeof opt === 'string' ? opt : opt.value;
        const isCorrect =
            question.type === 'multiple-choice'
                ? (question.correctAnswers || []).includes(optIdx)
                : question.correctAnswer === optIdx;
        return {
            value: value || '',
            key: `${question.id || 'q'}_opt_${optIdx}`,
            isCorrect
        };
    });
}

function normalizeQuestion(question, idx, totalCount) {
    const type = question.type || 'single-choice';
    const normalized = {
        ...question,
        type,
        displayNumber: idx + 1,
        points: question.points ?? (type === 'scale' ? 10 : 1),
        explanation: question.explanation || '',
        showAdvanced: question.showAdvanced || false,
        isScale: type === 'scale',
        isSingleChoice: type === 'single-choice',
        isMultipleChoice: type === 'multiple-choice',
        isChoice: type === 'single-choice' || type === 'multiple-choice',
        wrapperClass: `question-card-wrapper ${type === 'scale' ? 'accent-scale' : 'accent-choice'}`,
        showAdvancedIcon: (question.showAdvanced || false) ? 'utility:chevrondown' : 'utility:chevronright',
        canMoveUp: idx > 0,
        canMoveDown: idx < totalCount - 1
    };

    if (normalized.isChoice) {
        normalized.options = normalizeOptions(normalized);
        if (normalized.type === 'single-choice' && normalized.correctAnswer === undefined) {
            normalized.correctAnswer = 0;
        }
        if (normalized.type === 'multiple-choice' && !normalized.correctAnswers) {
            normalized.correctAnswers = [];
        }
    }

    if (normalized.isScale) {
        const scaleMin = question.scaleMin ?? 1;
        const scaleMax = question.scaleMax ?? 5;
        normalized.scaleMin = scaleMin;
        normalized.scaleMax = scaleMax;
        normalized.scaleMinLabel = question.scaleMinLabel || '';
        normalized.scaleMaxLabel = question.scaleMaxLabel || '';
        normalized.scalePoints = buildScalePoints(
            scaleMin,
            scaleMax,
            question.scalePoints || [],
            normalized.points
        );
    }

    return normalized;
}

function normalizeQuestionsList(questions) {
    return questions.map((q, idx) => normalizeQuestion(q, idx, questions.length));
}

function serializeQuestion(question) {
    const base = {
        id: question.id,
        question: question.question,
        type: question.type,
        points: question.points,
        explanation: question.explanation || ''
    };

    if (question.type === 'scale') {
        return {
            ...base,
            scaleMin: question.scaleMin,
            scaleMax: question.scaleMax,
            scaleMinLabel: question.scaleMinLabel || '',
            scaleMaxLabel: question.scaleMaxLabel || '',
            scalePoints: (question.scalePoints || []).map((p) => ({
                value: p.value,
                weight: p.weight
            }))
        };
    }

    if (question.type === 'multiple-choice') {
        return {
            ...base,
            options: (question.options || []).map((opt) =>
                typeof opt === 'string' ? opt : opt.value
            ),
            correctAnswers: question.correctAnswers || []
        };
    }

    return {
        ...base,
        options: (question.options || []).map((opt) =>
            typeof opt === 'string' ? opt : opt.value
        ),
        correctAnswer: question.correctAnswer
    };
}

function validateQuestion(question, index) {
    const num = index + 1;
    if (!question.id || !question.id.trim()) {
        return `Question ${num} is missing a question ID.`;
    }
    if (!question.question || !question.question.trim()) {
        return `Question ${num} is missing question text.`;
    }

    if (question.type === 'scale') {
        const min = question.scaleMin;
        const max = question.scaleMax;
        if (min === undefined || max === undefined || min >= max) {
            return `Question ${num}: scale minimum must be less than maximum.`;
        }
        if (max - min + 1 < 2 || max - min + 1 > 10) {
            return `Question ${num}: scale must have between 2 and 10 points.`;
        }
        const maxWeight = getQuestionMaxPoints(question);
        if (maxWeight > (question.points || 0)) {
            return `Question ${num}: highest scale weight (${maxWeight}) exceeds max points (${question.points}).`;
        }
        for (const point of question.scalePoints || []) {
            if (point.weight < 0 || point.weight > (question.points || 0)) {
                return `Question ${num}: scale weight for value ${point.value} must be between 0 and ${question.points}.`;
            }
        }
        return null;
    }

    const options = (question.options || []).map((opt) =>
        typeof opt === 'string' ? opt : opt.value
    );
    const filledOptions = options.filter((opt) => opt && opt.trim());

    if (filledOptions.length < 2) {
        return `Question ${num} needs at least 2 non-empty options.`;
    }

    if (question.type === 'multiple-choice') {
        const correctAnswers = question.correctAnswers || [];
        if (correctAnswers.length === 0) {
            return `Question ${num}: select at least one correct answer.`;
        }
        if (correctAnswers.some((i) => i < 0 || i >= options.length)) {
            return `Question ${num} has an invalid correct answer selection.`;
        }
        return null;
    }

    const correctAnswer = question.correctAnswer;
    if (correctAnswer === undefined || correctAnswer < 0 || correctAnswer >= options.length) {
        return `Question ${num}: select a correct answer.`;
    }
    if (!options[correctAnswer] || !options[correctAnswer].trim()) {
        return `Question ${num}: the correct answer option cannot be empty.`;
    }

    return null;
}

function reinitializeQuestionForType(question, newType) {
    const fresh = createQuestionByType(newType, question.displayNumber, [question.id]);
    return {
        ...fresh,
        id: question.id,
        question: question.question,
        points: newType === 'scale' ? (question.points || 10) : (question.points || 1),
        explanation: question.explanation || '',
        showAdvanced: question.showAdvanced || false
    };
}

export default class QuizQuestionEditor extends LightningElement {
    @api recordId;

    @track questions = [];
    @track isLoading = false;
    @track isValidJson = true;
    @track jsonError = '';
    @track showJsonEditor = false;
    @track jsonText = '';

    wiredRecordResult;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        const { error, data } = result;
        if (data) {
            this.loadQuizQuestions(data);
        } else if (error) {
            this.showError('Error loading quiz data', error.body?.message || error.message);
        }
    }

    loadQuizQuestions(data) {
        const quizJson = data.fields.Quiz_Questions__c?.value;
        const materialType = data.fields.Material_Type__c?.value;

        if (materialType !== 'Quiz') {
            this.showError('Invalid Material Type', 'This component is only for Quiz type materials.');
            return;
        }

        if (quizJson) {
            try {
                const parsed = JSON.parse(quizJson);
                this.questions = normalizeQuestionsList(parsed.questions || []);
                this.jsonText = JSON.stringify(this.buildJsonObject(), null, 2);
                this.isValidJson = true;
            } catch (e) {
                this.isValidJson = false;
                this.jsonError = 'Invalid JSON format: ' + e.message;
                this.jsonText = quizJson;
            }
        } else {
            this.questions = [];
            this.jsonText = JSON.stringify(this.buildJsonObject(), null, 2);
        }
    }

    buildJsonObject() {
        const questionsForSave = this.questions.map((q) => serializeQuestion(q));
        const totalQuestions = questionsForSave.length;
        const totalPoints = this.questions.reduce((sum, q) => sum + getQuestionMaxPoints(q), 0);

        return {
            version: JSON_VERSION,
            totalQuestions,
            totalPoints,
            questions: questionsForSave
        };
    }

    updateJsonText() {
        this.jsonText = JSON.stringify(this.buildJsonObject(), null, 2);
    }

    refreshQuestions(questions) {
        this.questions = normalizeQuestionsList(questions);
        this.updateJsonText();
    }

    handleAddQuestion(event) {
        const type = event.currentTarget?.dataset?.type || 'single-choice';
        const existingIds = this.questions.map((q) => q.id);
        const newQuestion = createQuestionByType(type, this.questions.length + 1, existingIds);
        this.refreshQuestions([...this.questions, newQuestion]);
    }

    handleQuestionMenuSelect(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const action = event.detail.value;
        if (action === 'duplicate') {
            this.duplicateQuestionAt(index);
        } else if (action === 'delete') {
            this.deleteQuestionAt(index);
        }
    }

    duplicateQuestionAt(index) {
        const source = this.questions[index];
        const existingIds = this.questions.map((q) => q.id);
        const copy = JSON.parse(JSON.stringify(serializeQuestion(source)));
        copy.id = generateQuestionId(this.questions.length + 1, existingIds);
        if (copy.options) {
            copy.options = copy.options.map((opt) => (typeof opt === 'string' ? opt : opt.value || ''));
        }
        const updated = [...this.questions];
        updated.splice(index + 1, 0, copy);
        this.refreshQuestions(updated);
    }

    deleteQuestionAt(index) {
        const updated = this.questions.filter((_, i) => i !== index);
        this.refreshQuestions(updated);
    }

    handleMoveQuestion(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const direction = event.currentTarget.dataset.direction;
        const targetIndex = direction === 'up' ? index - 1 : index + 1;
        if (targetIndex < 0 || targetIndex >= this.questions.length) {
            return;
        }
        const updated = [...this.questions];
        const [moved] = updated.splice(index, 1);
        updated.splice(targetIndex, 0, moved);
        this.refreshQuestions(updated);
    }

    handleToggleAdvanced(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.questions = this.questions.map((q, i) =>
            i === index ? { ...q, showAdvanced: !q.showAdvanced } : q
        );
        this.refreshQuestions(this.questions);
    }

    handleQuestionChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const field = event.currentTarget.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        let updated = [...this.questions];

        if (field === 'type') {
            updated[index] = reinitializeQuestionForType(updated[index], value);
        } else if (field === 'options') {
            const optionIndex = parseInt(event.currentTarget.dataset.optionindex, 10);
            updated = updated.map((q, i) => {
                if (i !== index) return q;
                const newOptions = [...q.options];
                newOptions[optionIndex] = {
                    ...newOptions[optionIndex],
                    value
                };
                return { ...q, options: newOptions };
            });
        } else if (field === 'scaleMin' || field === 'scaleMax') {
            updated = updated.map((q, i) => {
                if (i !== index) return q;
                const parsed = parseInt(value, 10);
                const newMin = field === 'scaleMin' ? parsed : q.scaleMin;
                const newMax = field === 'scaleMax' ? parsed : q.scaleMax;
                return {
                    ...q,
                    scaleMin: newMin,
                    scaleMax: newMax,
                    scalePoints: buildScalePoints(newMin, newMax, q.scalePoints, q.points)
                };
            });
        } else if (field === 'scaleWeight') {
            const pointIndex = parseInt(event.currentTarget.dataset.pointindex, 10);
            updated = updated.map((q, i) => {
                if (i !== index) return q;
                const newPoints = [...q.scalePoints];
                newPoints[pointIndex] = {
                    ...newPoints[pointIndex],
                    weight: parseInt(value, 10) || 0
                };
                return { ...q, scalePoints: newPoints };
            });
        } else if (field === 'points') {
            const points = parseInt(value, 10) || 1;
            updated = updated.map((q, i) => {
                if (i !== index) return q;
                if (q.type === 'scale') {
                    return {
                        ...q,
                        points,
                        scalePoints: buildScalePoints(q.scaleMin, q.scaleMax, q.scalePoints, points)
                    };
                }
                return { ...q, points };
            });
        } else {
            updated[index] = { ...updated[index], [field]: value };
        }

        this.refreshQuestions(updated);
    }

    handleSetCorrectAnswer(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const optionIndex = parseInt(event.currentTarget.dataset.optionindex, 10);
        const updated = this.questions.map((q, i) =>
            i === index ? { ...q, correctAnswer: optionIndex } : q
        );
        this.refreshQuestions(updated);
    }

    handleToggleCorrectAnswer(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const optionIndex = parseInt(event.currentTarget.dataset.optionindex, 10);
        const updated = this.questions.map((q, i) => {
            if (i !== index) return q;
            const current = [...(q.correctAnswers || [])];
            const pos = current.indexOf(optionIndex);
            if (pos >= 0) {
                current.splice(pos, 1);
            } else {
                current.push(optionIndex);
                current.sort((a, b) => a - b);
            }
            return { ...q, correctAnswers: current };
        });
        this.refreshQuestions(updated);
    }

    handleAddOption(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const updated = this.questions.map((q, i) => {
            if (i !== index) return q;
            const optCount = q.options.length;
            return {
                ...q,
                options: [
                    ...q.options,
                    { value: '', key: `${q.id}_opt_${optCount}` }
                ]
            };
        });
        this.refreshQuestions(updated);
    }

    handleRemoveOption(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const optionIndex = parseInt(event.currentTarget.dataset.optionindex, 10);

        const updated = this.questions.map((q, i) => {
            if (i !== index) return q;
            const newOptions = q.options
                .filter((_, optIdx) => optIdx !== optionIndex)
                .map((opt, optIdx) => ({
                    value: typeof opt === 'string' ? opt : opt.value,
                    key: `${q.id}_opt_${optIdx}`
                }));

            let correctAnswer = q.correctAnswer;
            if (q.type === 'single-choice') {
                if (correctAnswer === optionIndex) {
                    correctAnswer = 0;
                } else if (correctAnswer > optionIndex) {
                    correctAnswer -= 1;
                }
                correctAnswer = Math.min(correctAnswer, Math.max(0, newOptions.length - 1));
            }

            let correctAnswers = (q.correctAnswers || [])
                .filter((idx) => idx !== optionIndex)
                .map((idx) => (idx > optionIndex ? idx - 1 : idx));

            return { ...q, options: newOptions, correctAnswer, correctAnswers };
        });
        this.refreshQuestions(updated);
    }

    handleJsonChange(event) {
        this.jsonText = event.target.value;
        this.validateJson();
    }

    validateJson() {
        try {
            const parsed = JSON.parse(this.jsonText);
            if (parsed.questions && Array.isArray(parsed.questions)) {
                this.questions = normalizeQuestionsList(parsed.questions);
                this.isValidJson = true;
                this.jsonError = '';
            } else {
                this.isValidJson = false;
                this.jsonError = 'JSON must contain a "questions" array';
            }
        } catch (e) {
            this.isValidJson = false;
            this.jsonError = 'Invalid JSON: ' + e.message;
        }
    }

    toggleJsonEditor() {
        this.showJsonEditor = !this.showJsonEditor;
        if (this.showJsonEditor) {
            this.updateJsonText();
        }
    }

    async handleSave() {
        if (!this.isValidJson) {
            this.showError('Invalid JSON', 'Please fix JSON errors before saving.');
            return;
        }

        if (this.questions.length === 0) {
            this.showError('No Questions', 'Please add at least one question.');
            return;
        }

        for (let i = 0; i < this.questions.length; i++) {
            const error = validateQuestion(this.questions[i], i);
            if (error) {
                this.showError('Validation Error', error);
                return;
            }
        }

        this.updateJsonText();
        this.isLoading = true;

        try {
            const fields = {};
            fields[Id.fieldApiName] = this.recordId;
            fields[QUIZ_QUESTIONS_FIELD.fieldApiName] = this.jsonText;

            await updateRecord({ fields });
            this.showSuccess('Quiz Questions Saved', 'Quiz questions have been saved successfully.');
            await refreshApex(this.wiredRecordResult);
        } catch (error) {
            this.showError('Save Failed', error.body?.message || error.message);
        } finally {
            this.isLoading = false;
        }
    }

    showSuccess(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant: 'success' })
        );
    }

    showError(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant: 'error' })
        );
    }

    get hasQuestions() {
        return this.questions && this.questions.length > 0;
    }

    get totalQuestions() {
        return this.questions.length;
    }

    get totalPoints() {
        return this.questions.reduce((sum, q) => sum + getQuestionMaxPoints(q), 0);
    }

    get jsonEditorLabel() {
        return this.showJsonEditor ? 'Hide JSON' : 'Edit JSON';
    }

    get questionTypeOptions() {
        return [
            { label: 'Single Choice', value: 'single-choice' },
            { label: 'Multiple Choice', value: 'multiple-choice' },
            { label: 'Scale', value: 'scale' }
        ];
    }

    get addQuestionMenuItems() {
        return [
            { label: 'Single Choice', value: 'single-choice' },
            { label: 'Multiple Choice', value: 'multiple-choice' },
            { label: 'Scale', value: 'scale' }
        ];
    }

    handleAddQuestionMenuSelect(event) {
        const type = event.detail.value;
        const existingIds = this.questions.map((q) => q.id);
        const newQuestion = createQuestionByType(type, this.questions.length + 1, existingIds);
        this.refreshQuestions([...this.questions, newQuestion]);
    }
}