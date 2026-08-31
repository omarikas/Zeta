const TYPE_CONFIG = {
    campaign: {
        iconName: 'utility:target',
        cssClass: 'proj-type-icon--campaign',
        accent: '#0b5cab'
    },
    evaluation: {
        iconName: 'utility:education',
        cssClass: 'proj-type-icon--evaluation',
        accent: '#7c3aed'
    },
    default: {
        iconName: 'utility:strategy',
        cssClass: 'proj-type-icon--default',
        accent: '#0176d3'
    }
};

function normalizeTypeName(recordTypeName) {
    return (recordTypeName || '').toLowerCase();
}

export function getProjectTypeConfig(recordTypeName) {
    const normalized = normalizeTypeName(recordTypeName);
    if (normalized.includes('campaign')) {
        return { ...TYPE_CONFIG.campaign, label: recordTypeName || 'Campaign Project' };
    }
    if (normalized.includes('evaluation') || normalized.includes('frequent')) {
        return { ...TYPE_CONFIG.evaluation, label: recordTypeName || 'Evaluation Project' };
    }
    return { ...TYPE_CONFIG.default, label: recordTypeName || 'Project' };
}

export function getStatusClass(status) {
    switch (status) {
        case 'In Progress':
            return 'proj-status proj-status--progress';
        case 'Completed':
            return 'proj-status proj-status--completed';
        case 'On Hold':
            return 'proj-status proj-status--hold';
        default:
            return 'proj-status proj-status--planning';
    }
}

export function formatCurrency(value) {
    const amount = value || 0;
    return amount.toLocaleString(undefined, {
        maximumFractionDigits: 0
    });
}

export function formatDisplayDate(value) {
    if (!value) {
        return '—';
    }
    const parts = String(value).split('-');
    if (parts.length !== 3) {
        return value;
    }
    const date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    return date.toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    });
}