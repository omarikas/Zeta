import { plannerApiFetch } from './restHelper.js';

export default async function cancelSession(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/cancel', {
        method: 'POST',
        body: JSON.stringify({ sessionId: params.sessionId })
    });
}
