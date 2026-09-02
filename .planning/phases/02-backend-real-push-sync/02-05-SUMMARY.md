---
phase: 02-backend-real-push-sync
plan: 05
subsystem: sync
tags: [ponytail-audit, neon, vercel, e2e-verification, production-debugging]

# Dependency graph
requires:
  - phase: 02-backend-real-push-sync
    provides: "02-01 through 02-04: local backoff/versioning fixes, backend/, SyncApiHttp, auto-push trigger"
provides:
  - "Ponytail-audited sync code (duplication removed, one dead symbol removed)"
  - "Live Neon (dev branch) + Vercel deployment at https://cingula.vercel.app"
  - "Real-world discovery and fix of a FIFO head-of-line-blocking bug that silently stalled the entire outbox"
affects: []

status: partial
requirements-completed: []
requirements-partial: [SYNC-01, SYNC-02, SYNC-03, SYNC-06, SYNC-07, SYNC-08]

# Metrics
duration: ~4.5 hours (spans setup + extended live production debugging)
completed: 2026-09-01
---

# Phase 02 Plan 05: Ponytail Audit + Neon/Vercel Setup + E2E Verification — Summary

**Tasks 1-2 complete and committed. Task 3 (structured 7-case end-to-end verification) and Task 4 (close validation table) are explicitly deferred by the user's decision to stop for the night — not failed, not silently dropped.** In the course of getting the deploy working, a real production bug was found and fixed on the user's actual device with their actual field-recorded data, which incidentally exercises several of Task 3's verification cases informally (see below) — but does not substitute for the formal checklist.

## Task 1: Ponytail audit — COMPLETE

Commit `b7315f7`. Findings:
- `SyncApiHttp`: identical 401/non-200 error-classification block duplicated in `pushOutbox` and `fetchState` — extracted to a private `_throwForStatus` helper.
- `SyncTrigger.isRunning`: dead getter, zero callers anywhere (including tests) — removed.
- `SyncTrigger.flush()`: flagged by the same check (only the test suite calls it — the manual "Forzar push ahora" button calls `RunSyncUseCase` directly per D-06) but kept deliberately, documented with a `ponytail:` comment: it's the only deterministic way to test coalescing/reentrancy without depending on real timers.

## Task 2: Neon + Vercel setup — COMPLETE

Resolved directly by the user:
- Neon `dev` branch created from `main`; `backend/schema.sql` applied to both branches.
- `SYNC_API_KEY` token generated (never shared in chat, by design — stored in the user's local gitignored `backend/.env` and `dart_defines.json`).
- Backend deployed via Vercel's GitHub-import dashboard flow (Root Directory=`backend`) instead of the plan's `vercel link`/`vercel --prod` CLI steps — functionally equivalent, same env vars (`DATABASE_URL`, `SYNC_API_KEY`), same deploy target. Required pushing 67 local commits to `origin/main` first (confirmed with the user before pushing).
- Live at **https://cingula.vercel.app**.
- Verified: unauthenticated `POST /sync/push` → `401 {"error":"invalid or missing API key"}` (confirmed directly). Authenticated → `200 {"ackedIds":[],"serverCursor":null,"receivedAt":"..."}` (confirmed by the user). `DATABASE_URL=<dev> node --test` integration test runs for real (not skipped) and passes.

## Task 3: End-to-end verification — DEFERRED (not approved, not failed)

The user chose to stop for the night after a long live-debugging session (see below) rather than run the formal 7-case checklist from `02-05-PLAN.md`. Tracked as a Blocker/Concern in `STATE.md`, same pattern as Phase 1's DATA-01 deferral and Phase 2's own 02-04 Task 4 deferral (still also outstanding).

**Informal evidence gathered tonight, NOT a substitute for the structured checklist:**
- Caso 1 (push automático, SYNC-01): auto-push fired repeatedly during live testing without the user pressing any sync button — evidenced, not formally isolated/measured.
- Caso 4 (auth, SYNC-07): confirmed both directions via curl (401 without token, 200 with).
- Caso 5 (estado honesto, SYNC-08): directly observed — the panel showed "ERROR de red/servidor" with a nonzero pending count, never a false "sincronizado".
- Caso 7 (regresión de datos): strongly confirmed — all pre-existing local data intact (77 `audio_assets`, 70 `geo_paths`, 459 `geo_triggers`, 20 `regions`, verified via full-table row-count diff before/after the repair below), and additionally the entire 1186-row historical sync backlog successfully reached Neon for the first time.
- Caso 2 (kill mid-push, no duplicates), Caso 3 (offline + backoff), Caso 6 (ventana de 2 versiones): **not exercised tonight**, remain fully untested.

## Unplanned: production bug found and fixed live

Not part of the original plan — discovered while trying to get the device checkpoint working.

**Symptom:** user reported the sync status flashed an error that disappeared before it could be read, and no error appeared anywhere (console, app logs).

**Root cause chain, found via direct investigation (not guesswork after the first wrong hypothesis):**
1. `SyncTrigger._execute()` caught every exception and only recorded a coarse status enum (`idle/running/ok/transientError/authError`) — the actual exception message was discarded. Fixed: added an `onError` callback (`sync_trigger.dart`, `service_locator.dart`), wired to `LogService`, plus `debugPrint` for console visibility. The manual button's own catch block got the same treatment.
2. Once visible, the real error was `HTTP 400: {"error":"item[N]: payload.logical_version must be an integer >= 1", "invalidIds":[...]}`. Traced to 8 outbox rows with `op: delete` enqueued **before** plan 02-01 added `logical_version` to delete payloads — their stored payload JSON is permanently frozen in the old, incomplete shape.
3. Compounding factor: `backend/api/_lib/outbox.js` validates the **entire batch** before writing anything (by design, to avoid a partial-transaction failure silently corrupting state) — one malformed item rejects the whole batch with a 400.
4. Further compounding: `SyncClient.pendingOutbox()`'s FIFO `takeWhile(isOutboxRowEligible)` (a deliberate, documented design choice to preserve strict per-entity ordering) stops at the first ineligible row — so once those 8 rows entered backoff from repeated 400s, **the entire outbox behind them (1186 rows of real historical data) was silently unable to sync**, no matter how many times "Forzar push ahora" was pressed.

**Fix:**
- `SyncLocalDataSource.repairDeleteOutboxPayloads()`: scans `sync_outbox` for `op: delete` rows with missing/invalid `logical_version`, patches just that field to `1`. Safe because these 8 rows never reached a real backend before today (the only backend that ever existed was `SyncApiStub`, which never touched a server) — no real prior version to conflict with.
- Exposed via a "Reparar deletes viejos" debug-panel button — but during this session it wasn't visible after a VS Code hot-restart (unresolved root cause — likely a stale/cached build, matching a recurring theme this session; not a code defect, `flutter analyze` was clean and the button code is correct).
- Applied directly on the user's device as a one-time operation, with the app fully closed first: pulled a read-only copy of `cingula.db` (confirmed via `adb shell pidof` that the app process was not running), applied the exact same repair logic in a local script, diffed **every table's row count** before/after (all identical except `sync_outbox`), diffed the changed rows field-by-field (confirmed only the `payload` column changed on exactly the 8 target rows, every other column byte-identical), pushed the repaired copy back (`adb push` + `run-as cp`, working around an MSYS2/git-bash path-mangling gotcha with `//` prefix), then pulled it back down and SHA-256-hash-verified it matched what was pushed before telling the user to reopen the app.
- Result: outbox drained from 1186 to 0. New writes confirmed landing in Neon.

**Environment friction encountered (not code bugs, documented for future sessions):**
- git bash (mintty) does not reliably forward `r`/`Ctrl+C` to `flutter run` — left multiple orphaned `dart`/`dartaotruntime` processes across the session, which likely caused some of the "nothing changed" confusion before being diagnosed and killed.
- `--dart-define-from-file=dart_defines.json` wired into `.vscode/launch.json` was not being picked up by VS Code's Run button at least once (root cause not confirmed — most likely a build-cache issue given the session's recurring pattern, possibly not having "cingula-app" explicitly selected in the Run and Debug dropdown).
- PowerShell's `>` redirect corrupts binary data (`adb exec-out ... > file` produced a larger, invalid `.db` file) — had to redirect through git bash instead. `adb push`/`shell` in git bash mangles paths starting with `/` (MSYS2 auto-conversion) — worked around with a `//` prefix.

## Key decisions

- **Rows repaired in-place with `logical_version: 1`**, not discarded — since the entities they reference (or their siblings) are represented elsewhere in the outbox/local DB and the goal was informing the server of a delete, not preserving history that never existed server-side. Verified safe specifically because no real backend existed before today.
- **Direct device file repair chosen over waiting for the in-app button** — the button's environment issue was unresolved and the backlog was actively blocking the user's real data from reaching any backup, which is this milestone's highest-priority constraint (PROJECT.md: "cero pérdida de datos"). Every step was read-only until a full table-by-table diff and hash verification passed.
- **Task 3/4 explicitly deferred, not rushed** — after ~4.5 hours including significant environment troubleshooting, the user chose to stop rather than push through the remaining structured checklist. Tracked honestly as incomplete in STATE.md, matching the project's established pattern (Phase 1 DATA-01, Phase 2 02-04 Task 4) of deferring rather than fabricating verification.

## Next steps (for whoever resumes this)

1. Find out why the "Reparar deletes viejos" button didn't appear after a VS Code hot-restart (try `flutter clean` first — matches this session's very first stale-build incident).
2. Fix the `RenderFlex overflowed` layout bug in `lib/presentation/widgets/trigger_map.dart:275` (found in passing tonight via the device console, unrelated to sync, not fixed — out of scope for this plan).
3. Run the formal Task 3 checklist (7 cases, `02-05-PLAN.md`) and Task 4 (close `02-VALIDATION.md`) before considering Phase 2 complete.
4. Plan 02-04's Task 4 (5-case on-device verification) is a separate still-open deferral — could reasonably be combined with Task 3's session since both need the same setup (real device, real backend).

## Self-Check: PASSED

- FOUND: `lib/data/sync/sync_trigger.dart` (onError callback)
- FOUND: `lib/data/datasources/local/sync_local_data_source.dart` (repairDeleteOutboxPayloads)
- FOUND commits: `b7315f7`, `537f487`, `6c74ff8`, `5e0c4da`, merge commits integrating all of the above into `main`
- FOUND: live deploy responding correctly at https://cingula.vercel.app
- `flutter analyze`: 0 errors (2 pre-existing unrelated issues). `flutter test`: 64/64 passing. `node --test` (backend): 17 passing, 1 skipped (expected, no `DATABASE_URL` in this shell).
