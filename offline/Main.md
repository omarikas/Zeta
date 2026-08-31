# Offline-First LWC-to-PWA App — Architecture Spec

## 1. Goal

Take 5 existing Salesforce LWC tabs and run them as a standalone mobile PWA that:
- Fetches data from Salesforce when online
- Works fully offline using locally cached data (read + write)
- Queues offline writes and syncs them back to Salesforce (via Apex) when connectivity returns
- Reuses the LWC component architecture (templates, JS class, reactivity) rather than rewriting UI from scratch

This doc covers: what to strip from each LWC, the compile/build pipeline, the PWA shell, the IndexedDB schema, the sync engine (event-driven poller + outbox), the Apex batch endpoint contract, conflict handling, and idempotency.

---

## 2. What to strip from each LWC (Salesforce-specific pieces)

### 2.1 Data layer — replace entirely
- `@wire` adapters: `lightning/uiRecordApi` (`getRecord`, `getRecords`), `lightning/uiListApi` (`getListUi`), `lightning/uiObjectInfoApi` (`getObjectInfo`)
- Imported Apex methods: `import getX from '@salesforce/apex/ClassName.methodName'`
- `createRecord` / `updateRecord` / `deleteRecord` from `lightning/uiRecordApi`
- `refreshApex()`

**Replace with:** a local data-access module backed by IndexedDB (see §5). Same method signatures/shapes where practical (e.g. `getRecord(id)` returns the same shape your `@wire` used to), so component logic changes minimally.

### 2.2 Base component library (`lightning-*`)
Every `lightning-*` tag needs a replacement — these don't exist outside core:
- Inputs: `lightning-input`, `lightning-textarea`, `lightning-combobox`, `lightning-input-field`, `lightning-record-edit-form`
- Display: `lightning-record-view-form`, `lightning-output-field`, `lightning-formatted-*`
- Data: `lightning-datatable`, `lightning-tree`, `lightning-tree-grid`
- Layout: `lightning-card`, `lightning-layout`, `lightning-layout-item`, `lightning-tabset`, `lightning-accordion`
- Actions/feedback: `lightning-button`, `lightning-button-icon`, `lightning-spinner`, `lightning-badge`, `lightning-icon`

**Replace with:** a small internal component library (plain custom elements + CSS) covering just what these 5 tabs actually use. Don't build a full design system upfront — audit usage per tab first, build only what's needed.

### 2.3 Salesforce-scoped imports — replace with local equivalents
- `@salesforce/label/*` → a local i18n/constants module
- `@salesforce/schema/*` → local constants for object/field API names
- `@salesforce/resourceUrl/*` → normal static asset imports/paths
- `@salesforce/user/*` → local auth/session module
- `@salesforce/i18n/*` → local locale handling

### 2.4 Navigation & platform services
- `NavigationMixin` → your own router (even a minimal hash-based one)
- `lightning/platformShowToastEvent` → your own toast/snackbar component
- `lightning/refresh` → not needed (you control refresh yourself)
- `lightning/messageService` → replace cross-component pub/sub with plain `CustomEvent` bubbling or a small local event bus

### 2.5 Security/runtime & metadata
- Locker Service / LWS assumptions — not present outside core, no action needed, just don't rely on Salesforce-specific sandbox behavior
- `*.js-meta.xml` — meaningless outside Salesforce; if used for design attributes/config, replace with a plain JS/JSON config object per component

### 2.6 What survives untouched
- `.js` class structure, `@track`/`@api` decorators
- `.html` template syntax (`if:true`, `for:each`, event bindings)
- Lifecycle hooks (`connectedCallback`, `renderedCallback`, `disconnectedCallback`)
- `this.dispatchEvent(new CustomEvent(...))`
- Custom CSS

---

## 3. Build pipeline

1. Compile components with the LWC compiler + `@lwc/engine-dom` (outside the Salesforce build/deploy pipeline) — output is standard Custom Elements.
2. Bundle with your existing bundler (Vite recommended, matches current dev setup) into a static site: HTML + JS + CSS.
3. Serve over HTTPS (required for service worker registration; localhost exempted for dev).
4. Add a `manifest.json`:
   - `name`, `short_name`, icons (multiple sizes)
   - `start_url`
   - `display: "standalone"`
   - theme/background colors
5. Register a service worker for the app shell (see §4).

---

## 4. Service worker — app shell caching

Two distinct caching concerns — keep them separate:

- **App shell cache** (service worker Cache API): HTML/JS/CSS itself, cached on install/activate, so the app *loads* at all when offline. Use a cache-first strategy for these static assets, with versioned cache names so updates invalidate old shells cleanly.
- **Data cache** (IndexedDB, not the SW cache): fetched Salesforce records and the offline write queue. Structured, queryable, mutable — belongs in IndexedDB, not the Cache API.

Note: iOS Safari has historically lagged on service worker background sync and storage persistence guarantees vs. Android — verify current support for whatever your sync engine needs before committing to timing assumptions.

---

## 5. IndexedDB schema

One database, multiple object stores:

### 5.1 `records` store (cached Salesforce data, per object type)
One store per Salesforce object you cache (e.g. `records_Account`, `records_Visit__c`), or a single `records` store keyed by `objectType:recordId` — pick based on query patterns per tab.

Each record entry:
```json
{
  "id": "recordId or tempId",
  "objectType": "Account",
  "fields": { "...": "..." },
  "lastSyncedAt": "ISO timestamp or null",
  "serverVersion": "SystemModstamp or LastModifiedDate from last fetch",
  "syncStatus": "synced | pending | conflict | failed"
}
```

### 5.2 `outbox` store (pending write queue)
Each queued operation:
```json
{
  "opId": "client-generated UUID",
  "objectType": "Visit__c",
  "operation": "create | update | delete",
  "recordId": "tempId or real id",
  "fields": { "...": "..." },
  "createdAt": "ISO timestamp",
  "status": "pending | syncing | failed",
  "retryCount": 0,
  "lastError": null
}
```

- **Ordering per record**: if the same record is edited twice offline before syncing, either (a) preserve both ops in order and replay sequentially, or (b) collapse to a single latest-state op before it's ever pushed. Collapsing is simpler and avoids replay-ordering bugs — recommended unless you need a full audit trail of offline edits.
- **Temp IDs**: client-generated (e.g. UUID) for offline-created records, prefixed distinctly (e.g. `tmp_...`) so the sync layer can recognize which records need ID remapping after create.

### 5.3 `syncMeta` store
Tracks last full sync timestamp per object type, used to decide what to re-fetch on reconnect.

---

## 6. Sync engine

### 6.1 Trigger strategy — event-driven, not pure polling
- Primary trigger: `window.addEventListener('online', flushOutbox)`
- Backup trigger: interval poller (e.g. every 30–60s) as a fallback, since the `online` event can be unreliable on some mobile browsers/WebViews
- Singleton: one shared sync engine instance for the whole app, not per-tab — all 5 tabs enqueue into the same `outbox` store and share one flush process

### 6.2 Flush process
1. Check `navigator.onLine` (and ideally a real connectivity probe — a lightweight authenticated ping — since `navigator.onLine` only reflects network interface state, not actual reachability of Salesforce).
2. Read all `pending` ops from `outbox`, grouped by object type.
3. Batch into a single Apex call per object type (or one generic batch call handling mixed types — see §7).
4. On response, process per-item results (§7.3):
   - Success → update `records` store with real ID (if temp ID was used) and server-confirmed fields, mark `synced`, remove from `outbox`.
   - Failure → mark op `failed` in `outbox` with error detail, surface to UI for user resolution; don't block other ops in the batch.
5. Re-fetch anything flagged as changed server-side since last sync (see §8, conflict handling).

### 6.3 Batching — required, not optional
Do not push one Apex call per queued record. Governor limits (SOQL/DML/callout limits per transaction) will be hit quickly for anyone who's been offline for a while. Always send arrays; Apex side must be bulkified.

---

## 7. Apex batch endpoint contract

### 7.1 Signature (sketch)
```apex
public class OfflineSyncController {
    @AuraEnabled
    public static List<SyncResult> syncOperations(List<SyncOperation> operations) {
        // bulkified: group by objectType + operation type, execute as DML lists
    }
}

public class SyncOperation {
    @AuraEnabled public String opId;       // client UUID, for idempotency
    @AuraEnabled public String objectType;
    @AuraEnabled public String operation;  // create | update | delete
    @AuraEnabled public String recordId;   // tempId or real id
    @AuraEnabled public Map<String, Object> fields;
    @AuraEnabled public String clientLastSyncedVersion; // for conflict check on update
}

public class SyncResult {
    @AuraEnabled public String opId;
    @AuraEnabled public Boolean success;
    @AuraEnabled public String realRecordId;   // populated on create
    @AuraEnabled public String errorCode;      // e.g. VALIDATION, CONFLICT, DUPLICATE
    @AuraEnabled public String errorMessage;
    @AuraEnabled public Map<String, Object> serverFields; // current server state, for conflict resolution
}
```

### 7.2 Idempotency
- Store `opId` (client UUID) server-side, either in a custom field on the target object or a dedicated `Sync_Log__c` object, before/during DML.
- On retry (network dropped mid-response), check for an already-processed `opId` and return the prior result instead of re-executing — prevents duplicate creates.

### 7.3 Per-item results, not all-or-nothing
Use `Database.insert(records, false)` / `Database.update(records, false)` (partial success mode) so one bad record doesn't fail the whole batch. Map each `Database.SaveResult` back to its originating `opId` and return individual success/failure.

---

## 8. Conflict handling

Two conflict scenarios:

### 8.1 Same record edited twice offline (client-side only)
Handled at the outbox level — collapse to latest state before syncing (§5.2), so only one op per record ever reaches Apex.

### 8.2 Server changed the record while client was offline
- Every cached record stores `serverVersion` (e.g. `SystemModstamp`) from its last fetch.
- On sync, send `clientLastSyncedVersion` with each update op.
- Apex compares against current `SystemModstamp` before applying the update:
  - Match → apply update normally.
  - Mismatch → return `errorCode: CONFLICT` with current `serverFields`, don't apply the client's write.
- Client-side conflict resolution options (pick one as default, expose the other as an escape hatch):
  - **Server-wins**: discard local change, overwrite local cache with server state, notify user.
  - **User-prompted merge**: mark record `conflict` in local store, surface a UI affordance to let the user pick/merge, requeue after resolution.
- Duplicate-booking-style conflicts (e.g. two reps drag the same account onto the same slot while both offline) need a server-side validation rule or duplicate check in Apex, since nothing client-side can catch this reliably — surface as a normal `VALIDATION`/`CONFLICT` error from the batch response.

---

## 9. Network status & UI indicators

- `navigator.onLine` + `online`/`offline` events for connectivity state.
- Per-record `syncStatus` (`synced | pending | conflict | failed`) drives a visual indicator in each tab's UI (e.g. color/icon), reused across all 5 tabs, not built custom per tab.
- Optimistic UI: writes render immediately from local state; sync status updates in place once the outbox flush resolves, without blocking or re-rendering the whole view.

---

## 10. Per-tab notes

Since all 5 tabs are structurally different (confirmed: no shared layout pattern), each tab gets its own custom UI built from the shared primitive library (§2.2) and shared data/sync layer (§5–§7). Only the following are shared across all 5:
- IndexedDB access module
- Outbox/sync engine (singleton)
- Network status listener
- Toast/notification component
- Base primitive components (button, input, card, badge, spinner, etc.)

Document each tab's specific object(s), fields, and interaction model separately as you port it — this spec covers the shared plumbing only.

---

## 11. Open decisions to make before/during implementation

- [ ] Bundler choice (Vite recommended given existing Vite dev server usage)
- [ ] One IndexedDB store per object vs. single generic `records` store
- [ ] Collapse-to-latest vs. full op history in the outbox
- [ ] Default conflict resolution strategy (server-wins vs. user-prompted) — can differ per object type
- [ ] Real connectivity probe vs. relying solely on `navigator.onLine`
- [ ] Where the Sync_Log__c / idempotency tracking lives on the Salesforce side
- [ ] iOS PWA install flow — no `beforeinstallprompt` support, needs manual "Add to Home Screen" instructions in-app