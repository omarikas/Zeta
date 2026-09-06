import { getVisitPayload, putVisitPayload } from 'c/clmOfflineStore';
import { queueOfflineAction } from 'c/clmOfflineSync';

// Offline stand-in for VisitCallReportController.saveCallReport (Aura-only, no
// REST write endpoint). Every save is optimistic + queued to the offline outbox
// so it syncs when a sync endpoint is available; returns the merged payload the
// shell re-renders from. Matches the component's own offline-mode behaviour so
// online/offline saves are consistent.
export default async function saveCallReport(params) {
    const request = JSON.parse((params && params.requestJson) || '{}');
    const visitId = request.visitId;

    const prev = (visitId && (await getVisitPayload(visitId))) || {};
    const payload = {
        visit: {
            ...(prev.visit || {}),
            id: visitId,
            status: request.status,
            visitObjective: request.visitObjective,
            visitNotes: request.visitNotes,
            clmPresentation: request.clmPresentation || null,
            nextVisitDate: request.nextVisitDate || null,
            cancellationReason: request.cancellationReason || null
        },
        attendees: request.attendees || [],
        products: request.products || [],
        samples: request.samples || [],
        clmSessions: prev.clmSessions || []
    };

    if (visitId) {
        await putVisitPayload(visitId, payload);
        await queueOfflineAction({
            actionType: 'SAVE_CALL_REPORT',
            visitId,
            clientActionKey: `save_call_${visitId}_${Date.now()}`,
            callReportJson: params.requestJson
        });
    }
    return payload;
}
