import { plannerApiFetch } from './restHelper.js';

export default async function completeSession(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/complete', {
        method: 'POST',
        body: JSON.stringify({ sessionId: params.sessionId })
    });
}
