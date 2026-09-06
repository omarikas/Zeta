import { plannerApiFetch } from '../apex/restHelper.js';
import { makeDualApex } from '../apex/_wireAdapter.js';

const API_VERSION = 'v62.0';

// @wire(getRecord, { recordId, fields }) adapter. Resolves the requested fields
// via a read-only SOQL query and shapes the result like uiRecordApi's getRecord
// so getFieldValue works (record.fields[api].value).
async function loadRecord(config) {
    if (!config || !config.recordId || !Array.isArray(config.fields) || !config.fields.length) {
        return undefined;
    }
    const refs = config.fields
        .map((f) => (typeof f === 'string' ? f : f && f.fieldApiName))
        .filter(Boolean);
    if (!refs.length) {
        return undefined;
    }
    const objectApiName = refs[0].split('.')[0];
    const fieldNames = refs.map((r) => r.split('.').slice(1).join('.')).filter(Boolean);
    const select = ['Id', ...fieldNames].join(', ');
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(
        `SELECT ${select} FROM ${objectApiName} WHERE Id = '${config.recordId}' LIMIT 1`
    )}`;
    const result = await plannerApiFetch(path);
    const rows = result && Array.isArray(result.records) ? result.records : [];
    if (!rows.length) {
        return undefined;
    }
    const row = rows[0];
    const fields = {};
    fieldNames.forEach((fn) => {
        fields[fn] = { value: row[fn] !== undefined ? row[fn] : null };
    });
    return { id: row.Id, apiName: objectApiName, fields };
}

export const getRecord = makeDualApex(loadRecord);

// Extract a field value from a getRecord result, tolerant of our empty shape and
// of both string field names and @salesforce/schema field references.
export function getFieldValue(record, field) {
    if (!record || !record.fields) {
        return undefined;
    }
    const apiName = field && field.fieldApiName
        ? String(field.fieldApiName).split('.').pop()
        : field;
    const entry = record.fields[apiName];
    return entry ? entry.value : undefined;
}

export async function createRecord(recordInput) {
    const { apiName, fields } = recordInput;
    const result = await plannerApiFetch('/services/apexrest/planner/v1/time-off', {
        method: 'POST',
        body: JSON.stringify({ apiName, fields })
    });
    return result || { id: `tmp_${Date.now()}`, success: true };
}

export async function updateRecord(recordInput) {
    const { apiName, fields, recordId } = recordInput;
    const result = await plannerApiFetch(`/services/apexrest/planner/v1/time-off/${recordId}`, {
        method: 'PATCH',
        body: JSON.stringify({ apiName, fields })
    });
    return result || { id: recordId, success: true };
}

export async function deleteRecord(recordId) {
    await plannerApiFetch(`/services/apexrest/planner/v1/time-off/${recordId}`, {
        method: 'DELETE'
    });
    return { success: true };
}
