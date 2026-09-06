import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for VisitCallReportController.searchAttendeeCandidates.
// The Apex scopes candidates by the user's territory; this approximates it via
// the visit account's active affiliations (for the default list) and an org-wide
// name search (when the user types) — the accounts a rep would pick as attendees.
const API_VERSION = 'v62.0';
const PAGE_SIZE = 20;

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function esc(v) {
    return String(v).replace(/'/g, "\\'");
}

function quoteList(ids) {
    return ids.map((id) => `'${id}'`).join(',');
}

function mapCandidate(a, source) {
    const rt = a.RecordType || null;
    return {
        accountId: a.Id,
        accountName: a.Name,
        specialty: a.Specialty_1__c || null,
        recordTypeDeveloperName: rt ? rt.DeveloperName : null,
        accountTypeLabel: rt ? rt.Name : null,
        source
    };
}

async function loadAttendeeCandidates(params) {
    const visitId = params && params.visitId;
    const rawTerm = params && params.searchTerm ? String(params.searchTerm).trim() : '';
    const offset = params && params.offset > 0 ? Math.floor(params.offset) : 0;

    // Affiliated accounts for the visit's account (default suggestions).
    let affiliationIds = [];
    if (visitId) {
        const visitRows = await soql(
            `SELECT Account__c FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`
        );
        const accountId = visitRows.length ? visitRows[0].Account__c : null;
        if (accountId) {
            const affs = await soql(
                'SELECT Primary_Account__c, Related_Account__c FROM Account_Affiliation__c ' +
                `WHERE (Primary_Account__c = '${accountId}' OR Related_Account__c = '${accountId}') ` +
                'AND Is_Active__c = TRUE AND Outside_Territory__c = FALSE LIMIT 200'
            );
            const set = new Set();
            affs.forEach((aff) => {
                const related = aff.Primary_Account__c === accountId
                    ? aff.Related_Account__c
                    : aff.Primary_Account__c;
                if (related) set.add(related);
            });
            affiliationIds = Array.from(set);
        }
    }

    const accountSelect = 'Id, Name, Specialty_1__c, RecordType.DeveloperName, RecordType.Name';
    let accounts;
    if (rawTerm) {
        // Typed search: org-wide by name.
        accounts = await soql(
            `SELECT ${accountSelect} FROM Account WHERE Name LIKE '%${esc(rawTerm)}%' ` +
            `ORDER BY Name ASC LIMIT ${PAGE_SIZE} OFFSET ${offset}`
        );
        return accounts.map((a) => mapCandidate(a, 'Search'));
    }
    if (affiliationIds.length) {
        accounts = await soql(
            `SELECT ${accountSelect} FROM Account WHERE Id IN (${quoteList(affiliationIds)}) ` +
            `ORDER BY Name ASC LIMIT ${PAGE_SIZE} OFFSET ${offset}`
        );
        return accounts.map((a) => mapCandidate(a, 'Affiliation'));
    }
    // No term, no affiliations — a small recent list so the picker isn't empty.
    accounts = await soql(
        `SELECT ${accountSelect} FROM Account ORDER BY LastModifiedDate DESC ` +
        `LIMIT ${PAGE_SIZE} OFFSET ${offset}`
    );
    return accounts.map((a) => mapCandidate(a, 'Search'));
}

export default makeDualApex(loadAttendeeCandidates);
