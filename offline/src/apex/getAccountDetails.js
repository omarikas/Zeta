import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for AccountAffiliationController.getAccountDetails — the
// center node of the affiliation network.
export default makeDualApex(async (params) => {
    const accountId = params && params.accountId;
    if (!accountId) {
        return null;
    }
    const q = `SELECT Id, Name, RecordType.Name FROM Account WHERE Id = '${accountId}' LIMIT 1`;
    const result = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(q)}`
    );
    const rows = result && Array.isArray(result.records) ? result.records : [];
    if (!rows.length) {
        return null;
    }
    const a = rows[0];
    return { id: a.Id, name: a.Name, accountType: a.RecordType ? a.RecordType.Name : null };
});
