import syncOfflineActions from '@salesforce/apex/ClmOfflineSyncController.syncOfflineActions';
import {
    countPendingActions,
    enqueueAction,
    getPendingActions,
    putClientKeyMapping,
    removeAction,
    updateAction,
    updateLocalSession
} from 'c/clmOfflineStore';

const MAX_RETRIES = 5;
const listeners = new Set();
let syncInFlight = false;
let forceOffline = false;

function notify(status) {
    listeners.forEach((listener) => {
        try {
            listener(status);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn('CLM offline listener failed', error);
        }
    });
}

export function registerOfflineListener(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
}

export function isOfflineMode() {
    // Only use manual mode selection - no auto-detection
    return forceOffline;
}

export function setForceOffline(forced) {
    forceOffline = forced;
    console.log('[OfflineSync] Force offline mode:', forced);
    // Notify listeners of status change
    notify({ phase: forced ? 'forced-offline' : 'forced-online', pending: 0 });
}

export function getForceOffline() {
    return forceOffline;
}

// Manual mode change - trigger queue drain when going back online
export function setForceOfflineAndSync(forced) {
    const wasOffline = forceOffline;
    forceOffline = forced;
    console.log('[OfflineSync] Force offline mode:', forced);
    // Notify listeners of status change
    notify({ phase: forced ? 'forced-offline' : 'forced-online', pending: 0 });
    
    // When manually switching back online, trigger queue drain
    if (!forced && wasOffline) {
        console.log('[OfflineSync] Manual online mode - triggering queue drain');
        drainQueue().catch((error) => {
            console.warn('[OfflineSync] Queue drain after mode change failed:', error);
        });
    }
}

export async function queueOfflineAction(action) {
    console.log('[OfflineSync] [Step 1: Queue Action]', {
        actionType: action?.actionType,
        clientVisitKey: action?.clientVisitKey,
        clientActionKey: action?.clientActionKey,
        isOffline: isOfflineMode()
    });
    const id = await enqueueAction(action);
    const pendingCount = await countPendingActions();
    console.log(`[OfflineSync] [Step 2: Saved to IDB Outbox] Action ID: ${id}. Total pending: ${pendingCount}`);
    notify({ phase: 'queued', pending: pendingCount });

    // Only attempt to drain if we're online
    if (!isOfflineMode()) {
        console.log('[OfflineSync] Online - attempting immediate queue drain...');
        drainQueue().catch((error) => {
            console.warn('[OfflineSync] Immediate drain failed, will retry on next online event:', error);
        });
    } else {
        console.log('[OfflineSync] Offline - action queued for later sync');
    }
    return id;
}

function actionFailureKey(row) {
    return (
        row.clientActionKey ||
        row.clientSessionKey ||
        row.clientVisitKey ||
        row.clientCoachingKey ||
        `${row.actionType}_${row.id}`
    );
}

function toApexAction(row) {
    return {
        actionType: row.actionType,
        clientActionKey: row.clientActionKey || actionFailureKey(row),
        clientSessionKey: row.clientSessionKey,
        clientVisitKey: row.clientVisitKey,
        clientCoachingKey: row.clientCoachingKey,
        visitId: row.visitId,
        presentationId: row.presentationId,
        startedAtIso: row.startedAtIso,
        sequenceId: row.sequenceId,
        dwellSeconds: row.dwellSeconds,
        trackingPaused: row.trackingPaused,
        responsesJson: row.responsesJson,
        ratingsJson: row.ratingsJson,
        layoutId: row.layoutId,
        endedAtIso: row.endedAtIso,
        slidesPresentedCount: row.slidesPresentedCount,
        totalDurationSeconds: row.totalDurationSeconds,
        callReportJson: row.callReportJson,
        payloadJson: row.payloadJson
    };
}

async function persistKeyMaps(result) {
    const sessionMap = result?.sessionIdByClientKey || {};
    const visitMap = result?.visitIdByClientKey || {};
    const coachingMap = result?.coachingIdByClientKey || {};

    Object.entries(sessionMap).forEach(([clientKey, serverSessionId]) => {
        updateLocalSession(clientKey, { serverSessionId, synced: true });
        putClientKeyMapping(clientKey, { type: 'session', serverId: serverSessionId });
    });
    for (const [clientKey, serverVisitId] of Object.entries(visitMap)) {
        await putClientKeyMapping(clientKey, { type: 'visit', serverId: serverVisitId });
        await updateLocalSession(clientKey, { serverVisitId, synced: true });
    }
    for (const [clientKey, serverCoachingId] of Object.entries(coachingMap)) {
        await putClientKeyMapping(clientKey, { type: 'coaching', serverId: serverCoachingId });
    }
}

export async function drainQueue() {
    // Note: navigator.onLine is unreliable in Capacitor WebView
    // Always try to sync - let the network failure handle real offline cases
    if (syncInFlight) {
        console.log('[OfflineSync] Sync already in flight, skipping drain.');
        return { synced: 0 };
    }
    let synced = 0;
    try {
        const pending = await getPendingActions();
        console.log(`[OfflineSync] [Step 3: Reconnection / Drain] Found ${pending.length} pending action(s) in outbox.`);
        if (!pending.length) {
            // No pending actions - don't notify to avoid UI flickering
            return { synced: 0 };
        }
        // Only set syncInFlight and notify when there are actual actions to sync
        syncInFlight = true;
        notify({ phase: 'syncing' });
        const payload = pending.map(toApexAction);
        console.log('[OfflineSync] [Step 4: Syncing with Salesforce]', payload);
        const result = await syncOfflineActions({ actions: payload });
        console.log('[OfflineSync] [Step 5: Salesforce Result Received]', result);
        await persistKeyMaps(result);

        const failedKeys = new Set(result?.failedClientKeys || []);
        for (let index = 0; index < pending.length; index += 1) {
            const row = pending[index];
            const failureKey = actionFailureKey(row);
            const failed =
                failedKeys.has(failureKey) ||
                failedKeys.has(row.clientSessionKey) ||
                failedKeys.has(row.clientVisitKey) ||
                failedKeys.has(row.clientCoachingKey) ||
                failedKeys.has(row.actionType) ||
                failedKeys.has(row.clientActionKey);
            if (failed) {
                const retries = (row.retries || 0) + 1;
                console.warn(`[OfflineSync] Action failed for clientKey ${failureKey}. Retry #${retries}`);
                await updateAction(row.id, {
                    status: retries >= MAX_RETRIES ? 'dead' : 'failed',
                    retries,
                    lastError: result?.errorMessages?.[index] || 'Sync failed'
                });
            } else {
                console.log(`[OfflineSync] [Step 6: Outbox Cleanup] Successfully synced and removed action ID ${row.id}`);
                await removeAction(row.id);
                synced += 1;
            }
        }
        const remaining = await countPendingActions();
        console.log(`[OfflineSync] [Step 7: Finished] Synced: ${synced}, Remaining pending: ${remaining}`);
        notify({ phase: 'idle', synced, pending: remaining });
        return { synced, result, pending: remaining };
    } catch (error) {
        console.error('[OfflineSync] Drain queue error:', error);
        // In manual mode, we don't auto-detect offline status
        // The user must manually switch to offline mode if they have connectivity issues
        notify({ phase: 'error', error, pending: await countPendingActions() });
        throw error;
    } finally {
        syncInFlight = false;
    }
}

export function startSyncService() {
    // Only attempt to drain if we're online (manual mode)
    if (!isOfflineMode()) {
        drainQueue().catch((error) => {
            // eslint-disable-next-line no-console
            console.warn('CLM offline sync failed', error);
        });
    } else {
        console.log('[OfflineSync] Offline - skipping initial queue drain');
    }
}

export async function resolveSessionId(session) {
    if (!session) {
        return null;
    }
    if (session.serverSessionId) {
        return session.serverSessionId;
    }
    if (session.id && String(session.id).length >= 15) {
        return session.id;
    }
    return session.clientSessionKey || session.id;
}

export async function getOfflineSyncStatus() {
    const pending = await countPendingActions();
    return {
        offline: isOfflineMode(),
        pending,
        syncing: syncInFlight
    };
}