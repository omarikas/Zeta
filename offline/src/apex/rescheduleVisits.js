import { plannerApiFetch } from './restHelper.js';

export default async function rescheduleVisits(params = {}) {
    const moves = (params.visitIds || []).map((id, idx) => ({
        visitId: id,
        startDateTime: params.starts ? params.starts[idx] : null,
        endDateTime: params.ends ? params.ends[idx] : null
    }));
    return plannerApiFetch('/services/apexrest/planner/v1/visits/reschedule', {
        method: 'POST',
        body: JSON.stringify({ moves })
    });
}
