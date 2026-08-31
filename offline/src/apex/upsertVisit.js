import { plannerApiFetch } from './restHelper.js';

export default async function upsertVisit(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/visits/upsert', {
        method: 'POST',
        body: JSON.stringify(params)
    });
}
