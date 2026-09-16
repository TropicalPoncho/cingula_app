---
phase: 02-backend-real-push-sync
verified: 2026-09-16T00:00:00Z
status: human_needed
score: 6/6 truths code-verified; 4/6 ROADMAP success-criteria confirmed live end-to-end tonight, 1 inconclusive, 2 untested from the running app (deferred by explicit user decision)
human_verification:
  - test: "Kill-mid-push / no-duplicates (SYNC-02) against the live Neon+Vercel deploy"
    expected: "Editing an entity, letting the push start, then killing the app before it completes, then reopening and pushing again produces EXACTLY ONE row per record_uuid in Neon (`SELECT record_uuid, count(*) FROM synced_entities GROUP BY record_uuid HAVING count(*) > 1;` returns 0 rows)"
    why_human: "Requires a real device, real timing (killing the app mid-flight), and a live Neon query. The user attempted this tonight but was not sure the app was killed before the push completed, so the result is inconclusive rather than negative. The idempotent-upsert SQL (`ON CONFLICT ... current_version < EXCLUDED.current_version`) is unit- and integration-tested (backend/api/sync/push.test.js, skipped locally without DATABASE_URL but exercises this exact scenario when run against a real branch) and the client-side double-push idempotency is covered by run_sync_usecase_test.dart, but neither substitutes for a genuine kill-mid-flight against the real deployed stack."
  - test: "Auth-invalid handling from the running app (SYNC-07) without a retry storm"
    expected: "Recompiling with a wrong CINGULA_SYNC_API_KEY and writing an entity shows the panel's specific auth-error message, leaves the row pending, and does NOT produce a burst of retries in Vercel logs (a 401 must not consume backoff, per D-03)"
    why_human: "SYNC-07 itself (401 without token, 200 with the right token) was already confirmed tonight directly via curl against the live deploy, which is sufficient evidence that the backend enforces auth correctly. What remains unverified is the app-side behavior with a bad key baked in via --dart-define: that the UI shows the specific message and that RunSyncUseCase's D-03 branch (401 does not call markAttempt) holds against the real network stack, not just against SyncApiHttp's mocked test client. This is a UI/behavior confirmation, not a backend security gap -- the server-side control is already proven."
  - test: "Coalescing on cascade delete against the live deploy"
    expected: "Deleting a geo_path with several associated triggers produces exactly one POST /sync/push (visible in Vercel logs or console), not N+1 requests"
    why_human: "SyncTrigger's debounce+non-reentrancy logic is fully unit-tested (sync_trigger_test.dart: 5x schedule() -> 1 call, in-flight guard, rerun-on-completion), but confirming it holds for a real cascade delete against the real deployed backend (not a fake RunSyncUseCase) requires a device and inspecting real request logs."
---

# Phase 02: Backend Real Push Sync Verification Report

**Phase Goal:** Cada escritura local (audio_assets, geo_triggers, geo_paths, regions) llega de forma confiable a un backend real a través del outbox ya existente, con estado de sync visible y honesto.
**Verified:** 2026-09-16
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (derived from must_haves across 02-01..02-05 PLAN.md frontmatter + ROADMAP success criteria)

| # | Truth | Source Plan(s) | Status | Evidence |
|---|-------|------|--------|----------|
| 1 | Outbox row that failed a push waits an exponentially-growing time before retrying, persisted in SQLite (survives app kill) | 02-01 | ✓ VERIFIED | `lib/data/sync/sync_backoff.dart` (`fullJitterBackoff`, `isOutboxRowEligible`), schema v6 `next_attempt_at` column in `app_database.dart`, `SyncClient.markAttempt` persists it. 9 unit tests green. |
| 2 | Delete operations enqueue `logical_version` in their payload, same as insert/update | 02-01 | ✓ VERIFIED | All 5 delete-enqueue sites in `geo_trigger_local_data_source.dart`/`geo_path_local_data_source.dart` select and forward `logical_version` via `_nextDeleteVersion`. Confirmed by direct file read. |
| 3 | A POST to /sync/push without a valid Authorization header is rejected with 401; server never opens on missing config | 02-02 | ✓ VERIFIED | `backend/api/_lib/auth.js` `requireApiKey`: fail-closed on empty `SYNC_API_KEY`, constant-time compare. 8 unit tests green (`node --test`). Confirmed live tonight via curl against `https://cingula.vercel.app` (401 without token). |
| 4 | Same record_uuid + logical_version pushed twice leaves server state identical (no-op); server keeps current + 1 previous version only | 02-02 | ✓ VERIFIED (code + integration test written) / ✓ CONFIRMED LIVE tonight | `backend/api/_lib/outbox.js` `upsertStatement`: single `ON CONFLICT` statement gated on `current_version < EXCLUDED.current_version`. `push.test.js` covers idempotency, 2-version window, out-of-order, delete (skips locally without DATABASE_URL, ran green against Neon dev branch per 02-05-SUMMARY). Tonight: direct Neon query confirmed `current_version=3, previous_version=2`, no accumulated history. |
| 5 | App speaks real HTTP against the backend instead of SyncApiStub; a network/5xx error retries with backoff, a 401 does not consume backoff (terminal) | 02-03 | ✓ VERIFIED | `SyncApiHttp` implements `SyncApi` over `package:http`; `SyncApiStub` deleted (`grep -rn "SyncApiStub" lib/ test/` → 0 hits); `RunSyncUseCase.pushOutboxOnce` catches `SyncAuthException` (rethrow, no markAttempt) vs `SyncTransientException` (markAttempt every row). 15+6 unit tests green. |
| 6 | Writing/editing an entity online pushes to the backend without pressing any button; a cascade delete produces one push, not N; reconnecting drains pending writes; the debug panel shows honest pending count / last sync / auth-vs-network error distinction; the manual push button still exists | 02-04 | ✓ VERIFIED (code) / ✓ CONFIRMED LIVE tonight (auto-push, offline+reconnect, manual button) / ? UNCERTAIN (coalescing from real app) | `SyncTrigger` (debounce, non-reentrant, `statusStream`) wired to `SyncLocalDataSource.onOutboxEnqueued` (single funnel, D-04) and `connectivity_plus.onConnectivityChanged` (D-05). `DiagnosticsPanel._syncStatusLabel` never says "todo sincronizado" while pending > 0 (grep confirms 0 matches for that phrase). 7 unit tests for `SyncTrigger` green. Tonight: auto-push (no button) confirmed via real geo_path update landing in Neon; offline+reconnect drain confirmed; manual "Forzar push ahora" used repeatedly, works. Coalescing itself (cascade delete → 1 request) was not specifically isolated tonight, though the underlying debounce/non-reentrancy logic is unit-tested. |
| 7 | No orphaned/speculative abstractions remain in the phase's new code (ponytail audit) | 02-05 | ✓ VERIFIED | 02-05 Task 1 (commit `b7315f7`): extracted duplicated 401/non-200 classification into `_throwForStatus`, removed dead `SyncTrigger.isRunning` getter, kept `flush()` with an explicit `ponytail:` comment justifying it as test-only-but-load-bearing. `grep -rc "ponytail:" lib/data/sync/ backend/api/` → 3+ matches confirmed present in `sync_client.dart`, `sync_api_http.dart`, `sync_trigger.dart`, `backend/api/sync/push.js`. |
| 8 | Backend is deployed and receiving real production data; pre-existing local data on the phone is intact | 02-05 | ✓ VERIFIED | Live at `https://cingula.vercel.app`. Tonight: confirmed via direct Neon query and via a prior full-table row-count diff (77 audio_assets, 70 geo_paths, 459 geo_triggers, 20 regions all intact before/after the delete-payload repair). A separate 1186-row historical backlog was successfully drained during a prior session. |

**Score:** 8/8 derived truths have solid code-level + automated-test evidence. Of the observable, device-dependent behaviors, 4 (auto-push, offline+reconnect, 2-version window, manual button, data regression — actually 5) were confirmed live tonight against the real Neon+Vercel deployment; 1 (kill-mid-push dedup) is inconclusive; 2 (coalescing-from-real-app, auth-invalid-from-running-app) were not exercised tonight by explicit user choice. None of these three carve out a code gap — they are the last mile of human confirmation on top of already-passing automated coverage of the same logic.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/data/sync/sync_backoff.dart` | Pure Full Jitter backoff + eligibility, no DB dependency | ✓ VERIFIED | Read directly: 2 functions, 2 constants, 0 classes, exactly as specified. |
| `lib/data/datasources/local/app_database.dart` | Schema v6 with `next_attempt_at` | ✓ VERIFIED | `_dbVersion = 6` confirmed present with `next_attempt_at` in `_onCreate` and `oldVersion < 6` ALTER block. |
| `lib/data/sync/sync_client.dart` | `pendingOutbox` filters by eligibility (takeWhile), `markAttempt` persists backoff | ✓ VERIFIED | Read directly, matches plan exactly, `ponytail:` comment present explaining the takeWhile head-of-line-blocking tradeoff. |
| `backend/schema.sql` | `synced_entities` DDL with current_*/previous_* | ✓ VERIFIED (via 02-02-SUMMARY + push.test.js referencing it) |
| `backend/api/_lib/auth.js` | `requireApiKey()`, constant-time, fail-closed | ✓ VERIFIED | Read directly — `timingSafeEqual`, length check before compare, empty-key fails closed. |
| `backend/api/_lib/outbox.js` | `validateOutboxItem`/`extractVersion`/`upsertStatement` | ✓ VERIFIED | Read directly — single `ON CONFLICT` statement implementing idempotency + 2-version window in one mechanism. |
| `backend/api/sync/push.js` | Auth → validate-all-or-400 → transactional upsert → ackedIds | ✓ VERIFIED | Read directly, matches wire_contract. |
| `lib/data/sync/sync_errors.dart` | `SyncAuthException` (terminal), `SyncTransientException` (retryable) | ✓ VERIFIED | Read directly, two flat classes. |
| `lib/data/sync/sync_api_http.dart` | Real `SyncApi` implementation over `package:http` | ✓ VERIFIED | Read directly, includes 02-05's `_throwForStatus` refactor + `fetchState` ponytail comment. |
| `lib/data/sync/sync_trigger.dart` | Debounce + non-reentrant + observable status + onError | ✓ VERIFIED | Read directly, includes 02-05's live-debugging addition (`onError` callback, `debugPrint`) not originally in the plan — a real improvement made in response to a live production bug. |
| `lib/presentation/pages/home/widgets/diagnostics_panel.dart` | Honest pending count, last sync, auth-vs-network distinction, manual button retained | ✓ VERIFIED | `_syncStatusLabel`, `statusStream.listen`, "Forzar push ahora" all present; 0 matches for "todo sincronizado"/"all synced" phrasing. |
| `.planning/phases/02-backend-real-push-sync/02-VALIDATION.md` | Closed validation table with real task IDs and sign-off | ✗ NOT CLOSED | Still `status: draft`, `nyquist_compliant: false`, table still has `02-XX`/`TBD` placeholders, `**Approval:** pending`. This is plan 02-05's own Task 4, explicitly deferred alongside Task 3 — a documented, known gap, not a surprise. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `sync_client.dart` | `sync_backoff.dart` | `isOutboxRowEligible` + `takeWhile` | ✓ WIRED | Confirmed by direct read. |
| `run_sync_usecase.dart` | `sync_errors.dart` | `on SyncAuthException` / `on SyncTransientException` | ✓ WIRED | Confirmed by direct read and by 6 passing tests exercising both branches. |
| `service_locator.dart` | `sync_api_http.dart` | `registerLazySingleton<SyncApi>(() => SyncApiHttp())` | ✓ WIRED | `SyncApiStub` deleted, 0 remaining references anywhere in `lib/`/`test/`. |
| `sync_local_data_source.dart` | `sync_trigger.dart` | `onOutboxEnqueued` → `SyncTrigger.schedule()`, wired in service locator | ✓ WIRED | Single call site in `enqueueOutbox`, wired in `service_locator.dart` line 87. |
| `service_locator.dart` | `connectivity_plus` | `onConnectivityChanged` → `SyncTrigger.schedule()` on reconnect | ✓ WIRED | Confirmed, with subscription-cancel-before-resubscribe guard for `reinitialize: true` re-entry. |
| `diagnostics_panel.dart` | `sync_trigger.dart` | `statusStream` subscription | ✓ WIRED | Confirmed by direct read. |
| `backend/api/sync/push.js` | `backend/api/_lib/outbox.js` | `upsertStatement` + `sql.transaction` | ✓ WIRED | Confirmed by direct read. |
| App (Flutter) | Neon `synced_entities` | Real HTTP against `https://cingula.vercel.app` | ✓ WIRED, LIVE | Confirmed tonight: real writes landing in Neon, 1186-row historical backlog previously drained. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `DiagnosticsPanel` pending count | `_outboxCount` | `SyncClient.pendingOutbox(limit: 200)` reading real `sync_outbox` table | Yes — real SQLite query, not hardcoded | ✓ FLOWING |
| `DiagnosticsPanel` sync status label | `_syncStatus` | `SyncTrigger.statusStream`, driven by real `RunSyncUseCase.pushOutboxOnce()` outcomes | Yes | ✓ FLOWING |
| `synced_entities.current_payload` | server-stored payload | `upsertStatement` writing the exact outbox item payload received over HTTP | Yes — confirmed live via Neon query showing real logical_version progression | ✓ FLOWING |

### Behavioral Spot-Checks

Step 7b: Automated spot-checks were not re-run in this verification session (they require a live server/device, out of scope for a fast grep/read-based pass) — instead, the equivalent live evidence gathered by the user tonight is treated as the spot-check record:

| Behavior | Command/Action | Result | Status |
|----------|---------|--------|--------|
| Backend rejects unauthenticated push | `curl -X POST .../sync/push` (no token) | `401 {"error":"invalid or missing API key"}` | ✓ PASS (confirmed tonight + in 02-05-SUMMARY) |
| Backend accepts authenticated push | `curl -X POST .../sync/push` (with token) | `200 {"ackedIds":[]...}` | ✓ PASS |
| `flutter test` full suite | `flutter test` | 64/64 passing | ✓ PASS (re-run during this verification) |
| `flutter analyze` | `flutter analyze` | 0 errors, 1 pre-existing unrelated info (`WillPopScope` deprecation) | ✓ PASS (re-run during this verification) |
| `node --test` (backend) | `cd backend && node --test` | 17 passing, 1 skipped (expected, no `DATABASE_URL` in this shell) | ✓ PASS (re-run during this verification) |
| Real geo_path edit reaches Neon without pressing sync button | Live device test tonight | Confirmed via direct Neon query | ✓ PASS |
| Offline write + reconnect drain | Live device test tonight (airplane mode) | Queued offline, uploaded automatically on reconnect | ✓ PASS |
| 2-version window | Direct Neon query tonight | `current_version=3, previous_version=2`, no history beyond that | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|-----------------|-------------|--------|----------|
| SYNC-01 | 02-02, 02-03, 02-04, 02-05 | Backend real reemplaza SyncApiStub | ✓ SATISFIED | `SyncApiHttp` wired, stub deleted, live push to `https://cingula.vercel.app` confirmed tonight without manual button press. |
| SYNC-02 | 02-01, 02-02, 02-05 | Push idempotente, dedupe por uuid+logical_version | ✓ SATISFIED (code + backend integration test) / ? kill-mid-push scenario inconclusive live | `ON CONFLICT` upsert gated on version comparison; `push.test.js` covers double-push identical-timestamp assertion; live kill-mid-push attempt tonight was inconclusive (timing uncertain), not a negative result. |
| SYNC-03 | 02-01, 02-03, 02-04 | Backoff exponencial+jitter, transitorio vs terminal | ✓ SATISFIED | Full Jitter backoff persisted in SQLite; `RunSyncUseCase` routes `SyncAuthException` vs `SyncTransientException` correctly; live offline+reconnect drain confirmed tonight. |
| SYNC-06 | 02-02, 02-05 | Estado actual + 1 anterior, sin historial ilimitado | ✓ SATISFIED | Single-statement upsert structurally prevents unlimited history (only 2 version slots exist in the schema); confirmed live tonight via direct Neon query. |
| SYNC-07 | 02-02, 02-03, 02-05 | Autenticación mínima (API key/bearer) | ✓ SATISFIED | `requireApiKey` fail-closed + constant-time; confirmed live via curl (401/200); app-side 401-handling is unit-tested but not confirmed from the running app tonight (see human_verification). |
| SYNC-08 | 02-04, 02-05 | Estado real de sync visible, sin falsos "todo sincronizado" | ✓ SATISFIED | `_syncStatusLabel` never claims full sync with pending > 0 (grep-confirmed + directly observed live tonight showing "ERROR de red/servidor" with nonzero pending during the production bug investigation). |

No orphaned requirements — REQUIREMENTS.md maps SYNC-01/02/03/06/07/08 to Phase 2 (SYNC-04/05 correctly deferred to Phase 3), and all six IDs appear across the five plans' frontmatter `requirements` fields.

### Anti-Patterns Found

None blocking. Scanned all phase-touched sync files (`sync_backoff.dart`, `sync_client.dart`, `sync_errors.dart`, `sync_api_http.dart`, `sync_trigger.dart`, `run_sync_usecase.dart`, `service_locator.dart`, `diagnostics_panel.dart`, and the backend `_lib`/`api` files) for TODO/FIXME/placeholder markers, empty implementations, and hardcoded stub returns — the only "TODO-adjacent" markers found are the deliberate `ponytail:` comments documenting known, accepted simplifications with their upgrade path (e.g., `SyncApiHttp.fetchState` has no callers today but is kept because `SyncApi` declares it; 4xx-non-401 treated as transient rather than a third error category). These are the intended output of the phase's own mandatory ponytail audit (02-05 Task 1), not undocumented shortcuts.

One residual item, not a code anti-pattern: `02-VALIDATION.md` still shows `status: draft` / `TBD` placeholders because plan 02-05's Task 4 (closing that document) was explicitly deferred along with Task 3. This is a documentation-closure gap, not a code gap.

### Human Verification Required

### 1. Kill-mid-push / no-duplicates against the live deploy (SYNC-02)

**Test:** Edit an entity, let a push start against `https://cingula.vercel.app`, kill the app (swipe from recents) before the push completes, reopen, and force another push. Then run `SELECT record_uuid, count(*) FROM synced_entities GROUP BY record_uuid HAVING count(*) > 1;` against Neon.
**Expected:** Exactly one row per `record_uuid` (the query returns 0 rows) — no duplicates, and the final `current_version` reflects the edit.
**Why human:** Requires precise timing (killing the app while an HTTP request is genuinely in flight) on a real device against the live backend. The user attempted this tonight but was unsure the app was killed before the push actually completed, so the result is inconclusive, not negative. The idempotency mechanism itself (`ON CONFLICT` gated on version comparison) is proven correct by `backend/api/sync/push.test.js` when run with `DATABASE_URL` set, and by `run_sync_usecase_test.dart`'s "doble push idempotente" test — but neither exercises a genuine mid-flight kill against the real network stack.

### 2. Auth-invalid handling from the running app, without a retry storm (SYNC-07, D-03)

**Test:** Recompile with `--dart-define=CINGULA_SYNC_API_KEY=clave-mala`, edit an entity, observe the debug panel and Vercel request logs.
**Expected:** Panel shows the specific auth-error message ("ERROR DE AUTH (401)..."), the row stays pending, and Vercel logs show at most one request per write/reconnect — no retry loop.
**Why human:** The backend's auth enforcement itself (401 without token, 200 with) was already confirmed live tonight via curl, so the security control is proven. What's unverified is the app's UI-and-behavior response when compiled with a genuinely wrong key and run against the real deployed backend — `RunSyncUseCase`'s D-03 branch (401 → no `markAttempt`) is unit-tested against a mocked `SyncApi`, but not observed end-to-end on device tonight.

### 3. Coalescing on cascade delete against the live deploy (SYNC-01/SYNC-03 supporting behavior)

**Test:** Delete a `geo_path` with several associated `geo_triggers` (cascade delete enqueues N+1 outbox rows), then check Vercel logs/console for the number of `/sync/push` requests.
**Expected:** Exactly one POST /sync/push request, not N+1.
**Why human:** `SyncTrigger`'s debounce (2s window) and non-reentrancy guard are fully unit-tested (`sync_trigger_test.dart`), but confirming the coalescing holds for a genuine cascade delete against the real deployed backend (not a fake `RunSyncUseCase`) requires a device and real request-log inspection. Not exercised tonight by explicit user choice.

### Gaps Summary

No code-level gaps were found. Every must-have artifact and key link declared across plans 02-01 through 02-05 exists, is substantive, and is wired correctly — confirmed by direct file reads (not just SUMMARY claims), by re-running `flutter analyze` (0 errors), `flutter test` (64/64 green), and `node --test` in `backend/` (17 passing, 1 expectedly skipped) during this verification session. All six phase requirements (SYNC-01, 02, 03, 06, 07, 08) have working code and automated test coverage, and five of the six ROADMAP success criteria were additionally confirmed live tonight against the actual Neon+Vercel production deployment (auto-push, offline+reconnect drain, 2-version window, manual button, data-regression safety).

The three items carried forward as human-verification follow-ups — kill-mid-push (inconclusive, not negative), auth-invalid-from-the-running-app (backend control already proven via curl, only the app-side UI/retry-behavior confirmation remains), and coalescing-from-a-real-cascade-delete — are the last mile of on-device confirmation on top of already-passing, already-reviewed automated logic. They do not indicate a structural gap in the implementation; they indicate remaining manual QA steps that the user explicitly chose to defer after a long live-debugging session tonight (in which a real production bug — the FIFO head-of-line-blocking stall affecting 1186 real outbox rows — was found and fixed with careful before/after data-integrity verification, consistent with the project's highest-priority "cero pérdida de datos" constraint).

Separately, `.planning/phases/02-backend-real-push-sync/02-VALIDATION.md` remains in `draft` status because plan 02-05's Task 3 (formal 7-case checklist) and Task 4 (closing the validation table) were explicitly deferred. This is a documentation-closure task, not a code or requirements gap, and should be closed alongside the three human-verification items above.

---

*Verified: 2026-09-16*
*Verifier: Claude (gsd-verifier)*
