export const VISIT_STATUS_DRAFT = 'Draft';
export const VISIT_STATUS_SUBMITTED = 'Submitted';
export const VISIT_STATUS_SCHEDULED = 'Scheduled';
export const VISIT_STATUS_COMPLETED = 'Completed';
export const VISIT_STATUS_CANCELLED = 'Cancelled';

export const VISIT_TYPE_UNPLANNED = 'Unplanned';
export const VISIT_TYPE_PLANNED_AUTO = 'Planned (Automatically)';
export const VISIT_TYPE_PLANNED_MANAGER = 'Planned (Manager)';

const ALL_STATUS_OPTIONS = [
    { label: 'Draft', value: VISIT_STATUS_DRAFT },
    { label: 'Submitted', value: VISIT_STATUS_SUBMITTED },
    { label: 'Scheduled', value: VISIT_STATUS_SCHEDULED },
    { label: 'Completed', value: VISIT_STATUS_COMPLETED },
    { label: 'Cancelled', value: VISIT_STATUS_CANCELLED }
];

function startOfDay(date) {
    const copy = new Date(date);
    copy.setHours(0, 0, 0, 0);
    return copy;
}

/**
 * BRD working week: Saturday through Wednesday.
 * Non-working days: Thursday (4) and Friday (5).
 */
export function isNonWorkingDay(date) {
    if (!date) {
        return false;
    }
    const day = date instanceof Date ? date.getDay() : new Date(date).getDay();
    return day === 4 || day === 5;
}

/** @deprecated use isNonWorkingDay */
export function isWeekendDay(date) {
    return isNonWorkingDay(date);
}

export function isPlannedVisitType(visitType) {
    return visitType === VISIT_TYPE_PLANNED_AUTO || visitType === VISIT_TYPE_PLANNED_MANAGER;
}

export function isUnplannedVisitType(visitType) {
    return visitType === VISIT_TYPE_UNPLANNED;
}

export function isFutureVisitStart(startDateTime) {
    if (!startDateTime) {
        return false;
    }
    const visitDay = startOfDay(new Date(startDateTime));
    const today = startOfDay(new Date());
    return visitDay > today;
}

export function isLockedVisitStatus(status) {
    return status === VISIT_STATUS_COMPLETED || status === VISIT_STATUS_CANCELLED;
}

export function isPendingApprovalStatus(status) {
    return status === VISIT_STATUS_SUBMITTED;
}

export function getAllowedStatuses(visitType, currentStatus, isManager = false) {
    const planned = isPlannedVisitType(visitType);
    const unplanned = isUnplannedVisitType(visitType);

    if (unplanned) {
        if (!currentStatus || currentStatus === VISIT_STATUS_SCHEDULED) {
            return [VISIT_STATUS_SCHEDULED, VISIT_STATUS_COMPLETED, VISIT_STATUS_CANCELLED];
        }
        return [currentStatus];
    }

    if (!planned) {
        return ALL_STATUS_OPTIONS.map((option) => option.value);
    }

    switch (currentStatus) {
        case VISIT_STATUS_DRAFT:
            return [VISIT_STATUS_DRAFT, VISIT_STATUS_SUBMITTED, VISIT_STATUS_CANCELLED];
        case VISIT_STATUS_SUBMITTED:
            return isManager
                ? [VISIT_STATUS_SUBMITTED, VISIT_STATUS_SCHEDULED, VISIT_STATUS_DRAFT]
                : [VISIT_STATUS_SUBMITTED];
        case VISIT_STATUS_SCHEDULED:
            return [
                VISIT_STATUS_SCHEDULED,
                VISIT_STATUS_COMPLETED,
                VISIT_STATUS_CANCELLED,
                VISIT_STATUS_SUBMITTED
            ];
        case VISIT_STATUS_COMPLETED:
        case VISIT_STATUS_CANCELLED:
            return [currentStatus];
        default:
            return [VISIT_STATUS_DRAFT, VISIT_STATUS_SUBMITTED, VISIT_STATUS_SCHEDULED];
    }
}

export function getVisitStatusOptions(startDateTime, visitType, currentStatus, isManager = false) {
    const future = isFutureVisitStart(startDateTime);
    const allowed = new Set(getAllowedStatuses(visitType, currentStatus, isManager));
    return ALL_STATUS_OPTIONS.filter((option) => {
        if (!allowed.has(option.value)) {
            return false;
        }
        if (future && option.value === VISIT_STATUS_COMPLETED) {
            return false;
        }
        if (option.value === VISIT_STATUS_SUBMITTED && currentStatus !== VISIT_STATUS_SUBMITTED) {
            return false;
        }
        return true;
    });
}

export function canSubmitForApproval(visitType, currentStatus) {
    return isPlannedVisitType(visitType) && currentStatus === VISIT_STATUS_DRAFT;
}

export function validateVisitStatusChange(status, startDateTime, cancellationReason) {
    if (status === VISIT_STATUS_CANCELLED && !(cancellationReason || '').trim()) {
        return 'Enter a cancellation reason.';
    }
    if (status === VISIT_STATUS_COMPLETED && isFutureVisitStart(startDateTime)) {
        return 'A visit cannot be completed before its scheduled date.';
    }
    if (startDateTime && isNonWorkingDay(new Date(startDateTime))) {
        return 'Visits can only be scheduled on working days (Saturday through Wednesday).';
    }
    return null;
}
