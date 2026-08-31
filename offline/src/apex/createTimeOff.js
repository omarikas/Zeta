import { plannerApiFetch } from './restHelper.js';

export default async function createTimeOff(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/time-off', {
        method: 'POST',
        body: JSON.stringify(params)
    });
}
