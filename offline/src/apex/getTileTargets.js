import { plannerApiFetch } from './restHelper.js';

// Read-only offline stand-in for ReportsHubController.getTileTargets, consumed by
// reportsHub via @wire. Mirrors the controller's Report/Dashboard lookups over the
// Salesforce REST Query API — no writes, no Apex deploy. In real Lightning the same
// import resolves to the cacheable Apex wire adapter. Report/Dashboard are standard
// queryable SObjects; the custom Tab target is static (accessible, apiName only).
const API_VERSION = 'v62.0';

async function soqlFirstId(query) {
    try {
        const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
        const result = await plannerApiFetch(path);
        const records = result && Array.isArray(result.records) ? result.records : [];
        return records.length ? records[0].Id : null;
    } catch (e) {
        // Report/Dashboard may be inaccessible for the profile — degrade to disabled tile.
        console.warn('[reportsHub] tile target lookup failed:', e && e.message);
        return null;
    }
}

async function resolveReport(developerName, folderName) {
    const id = await soqlFirstId(
        `SELECT Id FROM Report WHERE DeveloperName = '${developerName}' ` +
        `AND FolderName = '${folderName}' LIMIT 1`
    );
    return { recordId: id, objectApiName: 'Report', apiName: null, accessible: id != null };
}

async function resolveDashboard(developerName, folderName) {
    const id = await soqlFirstId(
        `SELECT Id FROM Dashboard WHERE DeveloperName = '${developerName}' ` +
        `AND FolderName = '${folderName}' LIMIT 1`
    );
    return { recordId: id, objectApiName: 'Dashboard', apiName: null, accessible: id != null };
}

function resolveCustomTab(tabApiName) {
    return { recordId: null, objectApiName: 'Tab', apiName: tabApiName, accessible: true };
}

async function loadTileTargets() {
    const [workingDays, medicalRep360] = await Promise.all([
        resolveReport('Working_Days_Analysis', 'Working Days Analysis'),
        resolveDashboard('Medical_Rep_360_Dashboard', 'Management')
    ]);
    return {
        'working-days-analysis': workingDays,
        'medical-rep-360': medicalRep360,
        'pharmacy-sales': resolveCustomTab('Pharmacy_Sales_Dashboard')
    };
}

// LWC wire adapter contract: engine does new Adapter(dataCallback) -> update(config) -> connect().
export default class GetTileTargetsWireAdapter {
    constructor(dataCallback) {
        this.dataCallback = dataCallback;
        this._connected = false;
    }

    connect() {
        this._connected = true;
        this._emit();
    }

    update() {
        // No wire params for getTileTargets; nothing to react to.
    }

    disconnect() {
        this._connected = false;
    }

    async _emit() {
        try {
            const data = await loadTileTargets();
            if (this._connected) {
                this.dataCallback({ data, error: undefined });
            }
        } catch (error) {
            if (this._connected) {
                this.dataCallback({ data: undefined, error });
            }
        }
    }
}
