import { plannerApiFetch } from './restHelper.js';

export default async function deleteVisit(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/visits/delete', {
        method: 'POST',
        body: JSON.stringify(params)
    });
}
