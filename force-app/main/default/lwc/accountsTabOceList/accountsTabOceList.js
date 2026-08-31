import { LightningElement, api } from 'lwc';

import { resolveAccountPinKind } from 'c/plannerMapPins';

const RISK_DOT_CLASS = {
    High: 'risk-dot-high',
    Med: 'risk-dot-med',
    Low: 'risk-dot-low'
};

const RISK_BADGE_CLASS = {
    High: 'oce-risk-badge oce-risk-high',
    Med: 'oce-risk-badge oce-risk-med',
    Low: 'oce-risk-badge oce-risk-low'
};

const PACE_CLASS = {
    Critical: 'oce-pace oce-pace-critical',
    Behind: 'oce-pace oce-pace-behind',
    'On Track': 'oce-pace oce-pace-ok',
    Ahead: 'oce-pace oce-pace-ok'
};

const CLASS_BADGE = {
    A: 'oce-class-badge oce-class-a',
    B: 'oce-class-badge oce-class-b',
    C: 'oce-class-badge oce-class-c'
};

export default class AccountsTabOceList extends LightningElement {
    @api rows = [];
    @api isLoading = false;
    @api sortBy;
    @api sortDirection;

    get displayRows() {
        return (this.rows || []).map((row) => {
            const pinKind = resolveAccountPinKind(
                row.recordTypeDeveloperName,
                row.recordTypeName
            );
            const pinLabel =
                row.accountSubtype || (pinKind === 'hco' ? 'HCO' : 'HCP');
            const classification = row.classification || '—';
            const risk = row.agentforceRisk || '—';
            const pace = row.paceStatusLabel || '—';
            const specialty = row.specialty || null;
            const city = row.city || null;
            const metaParts = [pinLabel, city].filter(Boolean);
            if (!city && row.addressLine) {
                metaParts.push(row.addressLine);
            }
            const businessUnits = Array.isArray(row.businessUnits) ? row.businessUnits : [];

            return {
                ...row,
                pinKind,
                typeIconName: pinKind === 'hco' ? 'standard:account' : 'standard:contact',
                pinLabel,
                typeIconClass:
                    pinKind === 'hco' ? 'account-type-icon-hco' : 'account-type-icon-hcp',
                riskDotClass: RISK_DOT_CLASS[row.agentforceRisk] || RISK_DOT_CLASS.Low,
                classificationDisplay: classification,
                classBadgeClass: CLASS_BADGE[row.classification] || 'oce-class-badge',
                metaLine: metaParts.join(' · '),
                businessUnits,
                hasBusinessUnits: businessUnits.length > 0,
                planCycleDisplay: row.planCycleLabel || (row.inPlanCycle ? 'In' : 'Out'),
                planBadgeClass: row.inPlanCycle ? 'oce-plan oce-plan-in' : 'oce-plan oce-plan-out',
                callPlanLabel:
                    row.inPlanCycle && row.targetVisits != null
                        ? `${row.actualVisits || 0}/${row.targetVisits}`
                        : '—',
                plannedPlanLabel:
                    row.inPlanCycle && row.targetVisits != null
                        ? `Planned ${row.plannedVisits || 0}/${row.targetVisits}`
                        : 'No target',
                gapDisplay:
                    row.inPlanCycle && row.visitGap != null ? String(row.visitGap) : '—',
                paceDisplay: pace,
                paceClass: PACE_CLASS[pace] || 'oce-pace',
                scoreDisplay:
                    row.agentforceScoreDisplay ||
                    (row.agentforceScore != null
                        ? Number(row.agentforceScore).toFixed(1)
                        : '—'),
                riskDisplay: risk,
                riskBadgeClass: RISK_BADGE_CLASS[row.agentforceRisk] || 'oce-risk-badge',
                specialtyDisplay: specialty || '—'
            };
        });
    }

    get sortDirectionIcon() {
        return this.sortDirection === 'asc' ? '↑' : '↓';
    }

    get sortDirectionLabel() {
        return this.sortDirection === 'asc' ? 'ascending' : 'descending';
    }

    handleRowAction(event) {
        const accountId = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action || 'view';
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action },
                bubbles: true,
                composed: true
            })
        );
    }

    handleAccountClick(event) {
        event.preventDefault();
        const accountId = event.currentTarget.dataset.id;
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action: 'view' },
                bubbles: true,
                composed: true
            })
        );
    }

    handleSortToggle() {
        this.dispatchEvent(new CustomEvent('sorttoggle'));
    }
}