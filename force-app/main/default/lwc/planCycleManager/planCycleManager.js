import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getYearMonthSummaries from '@salesforce/apex/PlanCycleAdminController.getYearMonthSummaries';
import getEmployeePlansForMonth from '@salesforce/apex/PlanCycleAdminController.getEmployeePlansForMonth';
import getPlanTargets from '@salesforce/apex/PlanCycleAdminController.getPlanTargets';
import savePlanTargets from '@salesforce/apex/PlanCycleAdminController.savePlanTargets';
import ensureEmployeePlan from '@salesforce/apex/PlanCycleAdminController.ensureEmployeePlan';
import copyPlansBetweenMonths from '@salesforce/apex/PlanCycleAdminController.copyPlansBetweenMonths';

const MONTH_NAMES = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
];

export default class PlanCycleManager extends LightningElement {
    selectedYear = new Date().getFullYear();
    selectedMonth;
    selectedEmployee;
    selectedTimeCardId;
    monthSummaries = [];
    employeeRows = [];
    targetRows = [];
    editableTargets = [];
    wiredSummaryResult;
    wiredEmployeeResult;
    wiredTargetResult;
    isSaving = false;
    isCopying = false;
    showCopyModal = false;
    copySourceMonth;
    copyTargetMonth;
    viewMode = 'year';

    get yearOptions() {
        const currentYear = new Date().getFullYear();
        return [currentYear - 1, currentYear, currentYear + 1].map((year) => ({
            label: String(year),
            value: String(year)
        }));
    }

    get monthOptions() {
        return MONTH_NAMES.map((label, index) => ({
            label,
            value: String(index + 1)
        }));
    }

    get selectedYearValue() {
        return String(this.selectedYear);
    }

    get monthTiles() {
        return (this.monthSummaries || []).map((month) => ({
            ...month,
            tileClass: `month-tile${month.isCurrentMonth ? ' month-tile--current' : ''}${
                this.selectedMonth === month.monthNumber ? ' month-tile--selected' : ''
            }`,
            coverageLabel: `${month.employeesWithPlans} / ${month.totalEligibleEmployees}`,
            coveragePercent:
                month.totalEligibleEmployees > 0
                    ? Math.round((month.employeesWithPlans / month.totalEligibleEmployees) * 100)
                    : 0
        }));
    }

    get hasMonthTiles() {
        return this.monthTiles.length > 0;
    }

    get selectedMonthLabel() {
        if (!this.selectedMonth) {
            return '';
        }
        return `${MONTH_NAMES[this.selectedMonth - 1]} ${this.selectedYear}`;
    }

    get employeeTableRows() {
        return (this.employeeRows || []).map((row) => ({
            ...row,
            statusLabel: row.hasPlan ? 'Has plan' : 'No plan',
            statusClass: row.hasPlan ? 'badge badge-plan' : 'badge badge-missing',
            targetLabel: row.hasPlan ? String(row.targetCount) : '—',
            territoryLabel: row.territoryName || '—'
        }));
    }

    get hasEmployeeRows() {
        return this.employeeTableRows.length > 0;
    }

    get showYearView() {
        return this.viewMode === 'year';
    }

    get showMonthView() {
        return this.viewMode === 'month';
    }

    get showEditView() {
        return this.viewMode === 'edit';
    }

    get isCopyDisabled() {
        return (
            this.isCopying ||
            !this.copySourceMonth ||
            !this.copyTargetMonth ||
            this.copySourceMonth === this.copyTargetMonth
        );
    }

    get isSaveDisabled() {
        return this.isSaving || this.editableTargets.length === 0;
    }

    @wire(getYearMonthSummaries, { year: '$selectedYear' })
    wiredSummaries(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.monthSummaries = result.data;
        } else {
            this.monthSummaries = [];
        }
    }

    @wire(getEmployeePlansForMonth, { year: '$selectedYear', month: '$selectedMonth' })
    wiredEmployees(result) {
        this.wiredEmployeeResult = result;
        if (result.data) {
            this.employeeRows = result.data;
        } else {
            this.employeeRows = [];
        }
    }

    @wire(getPlanTargets, { timeCardId: '$selectedTimeCardId' })
    wiredTargets(result) {
        this.wiredTargetResult = result;
        if (result.data) {
            this.targetRows = result.data;
            this.editableTargets = result.data.map((row) => ({
                id: row.id,
                accountName: row.accountName,
                potentiality: row.potentiality || '—',
                targetVisitFrequency: row.targetVisitFrequency,
                actualVisits: row.actualVisits ?? 0,
                frequencyStatus: row.frequencyStatus || '—'
            }));
        } else {
            this.targetRows = [];
            this.editableTargets = [];
        }
    }

    handleYearChange(event) {
        this.selectedYear = Number(event.detail.value);
        this.resetToYearView();
    }

    handleMonthTileClick(event) {
        this.selectedMonth = Number(event.currentTarget.dataset.month);
        this.viewMode = 'month';
    }

    handleBackToYear() {
        this.resetToYearView();
    }

    handleBackToMonth() {
        this.viewMode = 'month';
        this.selectedEmployee = null;
        this.selectedTimeCardId = null;
    }

    handleOpenCopyModal() {
        this.copySourceMonth = this.selectedMonth ? String(this.selectedMonth) : '1';
        this.copyTargetMonth = '';
        this.showCopyModal = true;
    }

    handleCloseCopyModal() {
        this.showCopyModal = false;
    }

    handleCopySourceChange(event) {
        this.copySourceMonth = event.detail.value;
    }

    handleCopyTargetChange(event) {
        this.copyTargetMonth = event.detail.value;
    }

    async handleCopyPlans() {
        this.isCopying = true;
        try {
            const result = await copyPlansBetweenMonths({
                year: this.selectedYear,
                sourceMonth: Number(this.copySourceMonth),
                targetMonth: Number(this.copyTargetMonth),
                employeeIds: null
            });
            this.showToast(
                'Plans copied',
                `Copied ${result.targetsCopied} account targets for ${result.employeesCopied} employees.`,
                'success'
            );
            this.showCopyModal = false;
            await this.refreshData();
        } catch (error) {
            this.showToast('Copy failed', this.reduceError(error), 'error');
        } finally {
            this.isCopying = false;
        }
    }

    async handleCreatePlan(event) {
        const employeeId = event.currentTarget.dataset.employeeId;
        this.isSaving = true;
        try {
            const timeCardId = await ensureEmployeePlan({
                employeeId,
                year: this.selectedYear,
                month: this.selectedMonth
            });
            this.showToast('Plan created', 'Monthly plan and account targets were initialized.', 'success');
            await refreshApex(this.wiredEmployeeResult);
            this.openEmployeeEditor(employeeId, timeCardId);
        } catch (error) {
            this.showToast('Create failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleEditPlan(event) {
        const employeeId = event.currentTarget.dataset.employeeId;
        const timeCardId = event.currentTarget.dataset.timeCardId;
        this.openEmployeeEditor(employeeId, timeCardId);
    }

    handleTargetFrequencyChange(event) {
        const targetId = event.currentTarget.dataset.id;
        const value = Number(event.target.value);
        this.editableTargets = this.editableTargets.map((row) =>
            row.id === targetId ? { ...row, targetVisitFrequency: value } : row
        );
    }

    async handleSaveTargets() {
        this.isSaving = true;
        try {
            await savePlanTargets({
                updates: this.editableTargets.map((row) => ({
                    id: row.id,
                    targetVisitFrequency: row.targetVisitFrequency
                }))
            });
            this.showToast('Plan updated', 'Visit targets were saved.', 'success');
            await refreshApex(this.wiredTargetResult);
            await refreshApex(this.wiredEmployeeResult);
            await refreshApex(this.wiredSummaryResult);
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    openEmployeeEditor(employeeId, timeCardId) {
        const employee = this.employeeRows.find((row) => row.employeeId === employeeId);
        this.selectedEmployee = employee ? employee.employeeName : 'Employee';
        this.selectedTimeCardId = timeCardId;
        this.viewMode = 'edit';
    }

    resetToYearView() {
        this.viewMode = 'year';
        this.selectedMonth = null;
        this.selectedEmployee = null;
        this.selectedTimeCardId = null;
    }

    async refreshData() {
        await Promise.all([
            refreshApex(this.wiredSummaryResult),
            refreshApex(this.wiredEmployeeResult),
            refreshApex(this.wiredTargetResult)
        ]);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}