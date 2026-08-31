---
name: lwc-to-pwa
description: >-
  Port an existing Salesforce LWC so the same force-app component runs in
  Lightning and in the offline/ Vite PWA. Use when the user says "same drill",
  "build the pwa to fetch the lwc", "port this LWC", or names a home/planner
  tab to run standalone (fieldRepHomeMetrics, fieldRepHomeTodayPlan, and later
  tabs).
---

# LWC → PWA (same component, two runtimes)

Do **not** copy the LWC into `offline/`. Compile `force-app/main/default/lwc/<name>` in both Lightning and the PWA.

Done already: `fieldRepHomeMetrics`, `fieldRepHomeTodayPlan`, `fieldRepHomeNextBestCustomer`. Copy that pattern.

## Hard rules

- One source: `force-app/main/default/lwc/<bundle>/`
- No `lightning-*`, `NavigationMixin`, `ShowToastEvent`, `LightningConfirm`, `@salesforce/user/Id`, `lightning/platformResourceLoader`
- Cache-first IndexedDB via `c/clmOfflineStore`, then network
- If `globalThis.PLANNER_REST_BASE` is set → REST `fetch`. Else → `@AuraEnabled` Apex
- Never call Apex REST from Lightning UI (`fetch('/services/apexrest/...')` → **401**)
- Skip the network call when `navigator.onLine === false`
- Error banner only when there is **no** cache
- Header sync chip: Cached / Updating… / Offline
- `put*` into IndexedDB must JSON-clone (LWC `@track` proxies are not cloneable)
- Deploy Apex/LWC with `--test-level RunSpecifiedTests --tests PlannerMobileRestServiceTest`

## Checklist

```
- [ ] REST GET (+ AuraEnabled twin) on PlannerMobileRestService
- [ ] Test asserts REST body + AuraEnabled map
- [ ] Strip Salesforce-only imports from the original LWC
- [ ] Cache-first init + connectivity listeners
- [ ] Native HTML + chip + error banner
- [ ] Vite alias / Apex stub if needed
- [ ] Mount in offline/src/main.js
- [ ] Deploy + npm run pwa:build
```

## 1. Apex contract

Add both surfaces on `PlannerMobileRestService`:

1. `GET /planner/v1/home/<resource>` in `doGet`
2. `@AuraEnabled` method that returns the **same** `buildX()` map

Required payload keys:

- `userId` — cache key (PWA has no `@salesforce/user/Id`)
- The records the LWC actually renders

Reuse existing controllers (`FieldRepHomeController`, `FieldPlannerController`). Do not invent a second data shape.

Writes (postpone/delete): PWA posts to existing REST (`/visits/reschedule`, `/visits/delete`). Lightning keeps AuraEnabled Apex.

Test: REST 200 + `contains` keys, then call the AuraEnabled method and `containsKey`.

## 2. LWC data layer

```javascript
const PATH = '/services/apexrest/planner/v1/home/<resource>';
const CACHE_USER_FALLBACK = 'me';

async fetchPayload() {
    const restBase = globalThis.PLANNER_REST_BASE || '';
    if (restBase) return this.fetchRest(restBase);
    return getAuraMethod({ contextUserId: this.contextUserId || null });
}

async init() {
    this.bindConnectivityListeners();
    const cached = await this.readCache();
    if (cached) {
        this.applyCached(cached);
        this.hasCachedData = true;
        this.syncStatus = 'cached';
    }
    if (navigator.onLine === false) {
        this.syncStatus = 'offline';
        if (!this.hasCachedData) this.errorMessage = 'You are offline. Connect to load …';
        return;
    }
    this.syncStatus = 'updating';
    try {
        const payload = await this.fetchPayload();
        this.applyPayload(payload);
        this.cacheUserKey = payload?.userId || CACHE_USER_FALLBACK;
        await this.writeCache();
        this.syncStatus = 'idle';
    } catch (error) {
        if (error?.name === 'AbortError') return;
        this.syncStatus = 'offline';
        if (!this.hasCachedData) this.errorMessage = /* connectivity vs real error */;
    }
}
```

Cache keys: `getUser*Key(userId)` from `c/clmOfflineStore`, plus fallback `'me'`.

`putHomeMetrics` / `putTodayPlan` already run `JSON.parse(JSON.stringify(value))`. New stores must do the same.

Treat REST **5xx** as offline when cache exists. Vite proxy returns 500/503 when Salesforce DNS fails.

On `online` → re-`init()`. On `offline` → abort in-flight fetch, chip = Offline.

## 3. LWC UI

Replace:

| Remove | Use |
|---|---|
| `lightning-spinner` | no full-card spinner; paint cache immediately |
| `lightning-button` | `<button class="plan-btn">` |
| `lightning-combobox` | `<select>` + `<option selected={opt.isSelected}>` (do not bind `value` on `<select>` — LWC1057) |
| `lightning-icon` | emoji / text |
| `ShowToastEvent` | inline `noticeMessage` banner |
| `LightningConfirm` | `window.confirm` |
| `NavigationMixin` record/tab | `window.open('/lightning/r/…')` or `PLANNER_SF_INSTANCE` in PWA |
| `@salesforce/resourceUrl` + `loadScript` | `<script>`/`<link>`: PWA = CDN, Lightning = `/resource/<name>` |

Chip + error go in the card header/body. Copy CSS from `fieldRepHomeMetrics` (`.sync-chip-*`, `.error-banner`).

## 4. PWA shell (`offline/`)

Runtime globals set in `src/main.js`:

- `PLANNER_REST_BASE = location.origin` (Vite proxies `/services` → org)
- `PLANNER_ACCESS_TOKEN` from `VITE_SF_ACCESS_TOKEN` or `localStorage` `zeta.pwa.sfAccessToken`
- `PLANNER_SF_INSTANCE` from `VITE_SF_INSTANCE_URL`

Mount the **original** constructor:

```javascript
import Foo from 'c/fooBar';
root.appendChild(createElement('c-foo-bar', { is: Foo }));
```

Vite (`offline/vite.config.js`):

- Resolve `c/<name>` → `force-app/main/default/lwc/<name>/<name>.js`
- Compile `.js` that has a sibling `.html` with `@lwc/compiler` `transformSync`
- Virtual IDs for compiled HTML/CSS **must not end in `.html` / `.css`** (append `.virtual.js`) or Vite steals them
- `enableStaticContentOptimization: false`
- `@salesforce/apex/PlannerMobileRestService.*` → `offline/src/apex/*.js`; other Apex → `noopApex.js`
- HTTPS via `@vitejs/plugin-basic-ssl`
- Proxy `/services` → `VITE_SF_INSTANCE_URL` (default `https://zetapharma.my.salesforce.com`)
- Proxy `error` → JSON **503** `{ message: 'Offline' }`, not a raw 500

SW (`offline/public/sw.js`): cache app shell only. Do **not** cache `/services/`. When `navigator.onLine === false`, do not forward API calls to the Vite proxy.

## 5. Verify

```bash
npm run pwa:build
# https://localhost:5173/  (accept self-signed cert)
sf project deploy start \
  --source-dir force-app/main/default/classes/PlannerMobileRestService.cls \
  --source-dir force-app/main/default/classes/PlannerMobileRestServiceTest.cls \
  --source-dir force-app/main/default/lwc/<bundle> \
  --test-level RunSpecifiedTests --tests PlannerMobileRestServiceTest
```

CLI session token (`sf org display`) works as Bearer for local PWA. Do not commit it.

First visit online must write cache. Then DevTools Offline: chip = Offline, UI stays, **no** dashboard 500 in the console.

## Reference implementations

- Metrics: `force-app/main/default/lwc/fieldRepHomeMetrics/`
- Today plan: `force-app/main/default/lwc/fieldRepHomeTodayPlan/`
- REST + AuraEnabled: `PlannerMobileRestService.buildHomeDashboard` / `buildTodayPlan`
- IDB: `c/clmOfflineStore` (`toPlainData`, `putHomeMetrics`, `putTodayPlan`)
- PWA: `offline/src/main.js`, `offline/vite.config.js`
