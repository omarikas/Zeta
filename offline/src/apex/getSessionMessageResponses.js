import { plannerApiFetch } from './restHelper.js';

export default async function getSessionMessageResponses(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/message-responses/fetch', {
        method: 'POST',
        body: JSON.stringify({ sessionId: params.sessionId })
    });
}
