import { plannerApiFetch } from './restHelper.js';

export default async function logSlideEvent(params = {}) {
    return plannerApiFetch('/services/apexrest/clm/v1/sessions/slide-event', {
        method: 'POST',
        body: JSON.stringify({
            sessionId: params.sessionId,
            sequenceId: params.sequenceId,
            dwellSeconds: params.dwellSeconds,
            trackingPaused: params.trackingPaused
        })
    });
}
