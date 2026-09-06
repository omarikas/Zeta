import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for VisitCallReportController.getCallReportPayload (Aura-only).
// Builds the visit header from a read-only SOQL query so the Details section
// renders live online; offline the shell falls back to its IndexedDB cache.
// Related collections (attendees/products/samples) come from their own @wire
// adapters and are left empty here — this covers the call-report core.
const API_VERSION = 'v62.0';

async function soqlOne(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    const records = result && Array.isArray(result.records) ? result.records : [];
    return records.length ? records[0] : null;
}

function mapVisit(v) {
    const status = v.Status__c || 'Draft';
    return {
        id: v.Id,
        name: v.Name,
        status,
        visitType: v.Visit_Type__c,
        startDateTime: v.Start_Date__c,
        endDateTime: v.End_Date__c,
        visitObjective: v.Visit_Objective__c,
        visitNotes: v.Visit_Notes__c,
        clmPresentation: v.CLM_Presentation__c,
        nextVisitDate: v.Next_Visit_Date__c,
        cancellationReason: v.Cancellation_Reason__c,
        // Client can't check the "Amend_Completed_Visits" perm; mirror the default.
        isLocked: status === 'Completed' || status === 'Cancelled',
        isDoubleVisit: v.Is_Double_Visit__c === true,
        coachingEventId: v.Coaching_Event__c || null,
        accountId: v.Account__c,
        accountName: v.Account__r ? v.Account__r.Name : null,
        accountCity: v.Account__r ? v.Account__r.BillingCity : null
    };
}

async function soqlMany(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

async function loadAttendees(visitId) {
    const rows = await soqlMany(
        'SELECT Id, Account__c, Account__r.Name, Account__r.Specialty_1__c, ' +
        'Account__r.RecordType.DeveloperName, Account__r.RecordType.Name ' +
        `FROM Visit_Attendee__c WHERE Visit__c = '${visitId}' ORDER BY CreatedDate ASC`
    );
    return rows.map((r, index) => {
        const acct = r.Account__r || {};
        const rt = acct.RecordType || null;
        return {
            id: r.Id,
            accountId: r.Account__c,
            accountName: acct.Name || null,
            specialty: acct.Specialty_1__c || null,
            recordTypeDeveloperName: rt ? rt.DeveloperName : null,
            accountTypeLabel: rt ? rt.Name : null,
            role: 'Attendee',
            isPrimary: index === 0,
            displayOrder: index + 1
        };
    });
}

async function loadCallReportPayload(params) {
    const visitId = params && params.visitId;
    if (!visitId) {
        return null;
    }
    const visit = await soqlOne(
        'SELECT Id, Name, Status__c, Visit_Type__c, Start_Date__c, End_Date__c, ' +
        'Visit_Objective__c, Visit_Notes__c, CLM_Presentation__c, Next_Visit_Date__c, ' +
        'Cancellation_Reason__c, Is_Double_Visit__c, Coaching_Event__c, Account__c, ' +
        'Account__r.Name, Account__r.BillingCity ' +
        `FROM Visit__c WHERE Id = '${visitId}' LIMIT 1`
    );
    if (!visit) {
        return null;
    }
    const attendees = await loadAttendees(visitId).catch(() => []);
    return {
        visit: mapVisit(visit),
        attendees,
        products: [],
        samples: [],
        clmSessions: []
    };
}

export default makeDualApex(loadCallReportPayload);
