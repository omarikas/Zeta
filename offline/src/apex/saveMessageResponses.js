import { plannerApiFetch } from './restHelper.js';

export default async function saveMessageResponses(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/message-responses', {
        method: 'POST',
        body: JSON.stringify({
            sessionId: params.sessionId,
            responses: params.responses
        })
    });
}
