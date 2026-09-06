import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for VisitContextInsightsController.getVisitContextInsights.
// Reproduces the account context + prior-visit history (the parts the shell's
// Context section shows). Neighbouring pharmacies rely on an external OpenMap
// lookup + geo radius, so they're left empty offline.
const API_VERSION = 'v62.0';
const DEFAULT_RADIUS_KM = 3;
const PAGE_SIZE = 10;
const MAX_PRIOR_VISITS = 10;

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function esc(v) {
    return String(v).replace(/'/g, "\\'");
}

function soqlDateTime(value) {
    if (!value) return null;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return null;
    // SOQL datetime literal: YYYY-MM-DDThh:mm:ssZ (no milliseconds).
    return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function snippet(notes) {
    if (!notes) return null;
    const text = String(notes).trim();
    return text.length > 140 ? `${text.slice(0, 137)}…` : text;
}

function mapPriorVisit(v) {
    return {
        visitId: v.Id,
        visitName: v.Name,
        startDateTime: v.Start_Date__c,
        repName: v.Assigned_To__r ? v.Assigned_To__r.Name : null,
        objective: v.Visit_Objective__c || null,
        notesSnippet: snippet(v.Visit_Notes__c),
        productsDiscussed: v.Products_Discussed__c || null
    };
}

async function loadPriorVisits(accountId, currentVisitId, beforeStart, assignedToId) {
    if (!accountId) return [];
    let where =
        `Account__c = '${esc(accountId)}' AND Status__c = 'Completed' ` +
        `AND Id != '${esc(currentVisitId)}' `;
    if (beforeStart) {
        where += `AND Start_Date__c < ${beforeStart} `;
    }
    if (assignedToId) {
        where += `AND Assigned_To__c = '${esc(assignedToId)}' `;
    }
    const rows = await soql(
        'SELECT Id, Name, Start_Date__c, Visit_Objective__c, Visit_Notes__c, ' +
        'Products_Discussed__c, Assigned_To__r.Name FROM Visit__c ' +
        `WHERE ${where}ORDER BY Start_Date__c DESC NULLS LAST LIMIT ${MAX_PRIOR_VISITS}`
    );
    return rows.map(mapPriorVisit);
}

async function loadVisitContextInsights(params) {
    const result = {
        hasGeo: false,
        searchRadiusKm: DEFAULT_RADIUS_KM,
        pharmacyPageSize: PAGE_SIZE,
        centerLatitude: null,
        centerLongitude: null,
        centerAccountName: null,
        totalPharmacyCount: 0,
        neighbouringPharmacies: [],
        territoryPriorVisits: [],
        zetaPriorVisits: []
    };

    const visitId = params && params.visitId;
    if (!visitId) {
        return result;
    }

    const visits = await soql(
        'SELECT Id, Account__c, Start_Date__c, Assigned_To__c, Account__r.Name, ' +
        'Account__r.BillingLatitude, Account__r.BillingLongitude ' +
        `FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`
    );
    if (!visits.length) {
        return result;
    }
    const visit = visits[0];
    const account = visit.Account__r || {};

    if (account.BillingLatitude != null && account.BillingLongitude != null) {
        result.hasGeo = true;
        result.centerLatitude = account.BillingLatitude;
        result.centerLongitude = account.BillingLongitude;
        result.centerAccountName = account.Name;
    }

    const before = soqlDateTime(visit.Start_Date__c);
    result.zetaPriorVisits = await loadPriorVisits(visit.Account__c, visit.Id, before, null);
    result.territoryPriorVisits = await loadPriorVisits(
        visit.Account__c,
        visit.Id,
        before,
        visit.Assigned_To__c
    );
    return result;
}

export default makeDualApex(loadVisitContextInsights);
