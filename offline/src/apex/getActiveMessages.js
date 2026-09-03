import { plannerApiFetch } from './restHelper.js';

// Read-only offline stand-in for HomeOfficeMessageController.getActiveMessages
// (Aura-only, not exposed over REST). Mirrors the active-message query via the
// Salesforce REST Query API — no writes, no Apex deploy. Territory/audience
// filtering from the controller is intentionally not replicated (cache all
// active messages); in real Lightning the same import resolves to the Apex.
const API_VERSION = 'v62.0';
const LOOKBACK_DAYS = 90;
const DEFAULT_LIMIT = 8;

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function formatPublishedLabel(iso) {
    if (!iso) {
        return '';
    }
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) {
        return '';
    }
    return d.toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    });
}

function audienceLabelFor(scope) {
    const s = (scope || '').trim();
    return s && s !== 'All Business Units' ? s : 'All Business Units';
}

export default async function getActiveMessages(params) {
    const requested = params && params.limitSize ? Number(params.limitSize) : DEFAULT_LIMIT;
    const rowLimit = Math.min(Math.max(requested || DEFAULT_LIMIT, 1), 25);

    // SOQL datetime literals must be YYYY-MM-DDThh:mm:ssZ (no milliseconds).
    const cutoff = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000)
        .toISOString()
        .replace(/\.\d{3}Z$/, 'Z');

    const rows = await soql(
        "SELECT Id, Name, Message_Body__c, Audience_Scope__c, Priority__c, " +
        "Published_On__c, Author__r.Name FROM Home_Office_Message__c " +
        `WHERE Is_Active__c = true AND Published_On__c >= ${cutoff} ` +
        "ORDER BY Priority__c DESC, Published_On__c DESC " +
        `LIMIT ${rowLimit}`
    );

    return rows.map((r) => ({
        recordId: r.Id,
        subject: r.Name,
        body: r.Message_Body__c,
        authorName: r.Author__r ? r.Author__r.Name : '',
        publishedOn: r.Published_On__c,
        publishedLabel: formatPublishedLabel(r.Published_On__c),
        priority: r.Priority__c,
        audienceLabel: audienceLabelFor(r.Audience_Scope__c),
        isHighPriority: r.Priority__c === 'High'
    }));
}
