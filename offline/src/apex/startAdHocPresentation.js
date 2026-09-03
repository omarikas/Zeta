import { plannerApiFetch } from './restHelper.js';

export default async function startAdHocPresentation(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/start-ad-hoc', {
        method: 'POST',
        body: JSON.stringify({ presentationId: params.presentationId })
    });
}
