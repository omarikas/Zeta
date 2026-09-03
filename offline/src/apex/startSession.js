import { plannerApiFetch } from './restHelper.js';

export default async function startSession(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/start', {
        method: 'POST',
        body: JSON.stringify({
            visitId: params.visitId,
            presentationId: params.presentationId
        })
    });
}
