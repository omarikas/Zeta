import { plannerApiFetch } from '../apex/restHelper.js';

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
