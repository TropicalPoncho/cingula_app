---
phase: 02-backend-real-push-sync
plan: 04
subsystem: sync
tags: [dart, flutter, debounce, connectivity, ui]
status: complete-device-qa-deferred

# Dependency graph
requires:
  - phase: 02-backend-real-push-sync
    plan: 01
    provides: SyncClient with backoff-aware pendingOutbox/markAttempt
  - phase: 02-backend-real-push-sync
    plan: 03
    provides: SyncApiHttp, RunSyncUseCase distinguishing SyncAuthException/SyncTransientException
provides:
  - "SyncTrigger: debounced (2s), non-reentrant, event-driven push scheduler with observable statusStream"
  - "SyncLocalDataSource.onOutboxEnqueued callback wired to SyncTrigger.schedule() -- single funnel for all 4 local data sources (D-04)"
  - "connectivity_plus onConnectivityChanged wired to SyncTrigger.schedule() on reconnect (D-05)"
  - "DiagnosticsPanel shows honest sync status: never claims full sync while pending > 0, distinguishes auth vs transient errors"
affects: [02-05]

tech-stack:
  added: ["connectivity_plus ^7.3.1"]
  patterns:
    - "Purely event-driven sync trigger (write, reconnect, manual button) -- zero periodic timers, by explicit milestone anti-polling constraint"
    - "SyncTrigger.schedule() is fire-and-forget: never propagates exceptions to the caller, so a background sync failure can never break the local write that triggered it"

key-files:
  created:
    - lib/data/sync/sync_trigger.dart
    - test/data/sync/sync_trigger_test.dart
  modified:
    - pubspec.yaml
    - lib/data/datasources/local/sync_local_data_source.dart
    - lib/core/di/service_locator.dart
    - android/app/src/main/AndroidManifest.xml
    - lib/presentation/pages/home/widgets/diagnostics_panel.dart

key-decisions:
  - "Task 4 (blocking human-verify checkpoint) requires on-device QA the executor cannot perform -- Tasks 1-3 committed and verified via automated tests; execution paused there per the plan's own gate=\"blocking\" instruction, no fabricated device-test result"
  - "User explicitly deferred all 5 Task 4 on-device verification cases (2026-08-29): no time to test on a real device right now, plans to run it later (\"tonight\"). This is a scope decision, not a failed or skipped test -- same pattern as Phase 1's DATA-01 on-device deferral in 01-04-SUMMARY.md. Recorded as deferred, not signed off, and tracked in STATE.md Blockers/Concerns so it isn't silently dropped."

requirements-completed: []
# SYNC-01, SYNC-03, SYNC-08 are code-complete (Tasks 1-3, automated tests green) but their
# on-device human confirmation (this plan's actual closing gate for these IDs) is deferred,
# not done -- see "Known Gaps" below. Not marked complete until the user runs Task 4's 5 cases.

duration: ~20min (Tasks 1-3, agent work)
completed: 2026-08-29
---

# Phase 02 Plan 04: Auto-Push Trigger + Honest Sync Status Summary

**`SyncTrigger` coalesces write bursts into one debounced push, guards against overlapping runs, and is wired to both `enqueueOutbox` (every local write) and `connectivity_plus` reconnect events, with zero periodic timers; the debug panel now shows real pending count, last sync, and distinguishes an auth failure from a network failure instead of ever claiming "all synced" while pending > 0. All 5 on-device verification cases are explicitly deferred by the user (2026-08-29), not tested, not failed.**

## Performance

- **Tasks completed:** 3/3 code tasks (Task 4 is a verification-only checkpoint, no code) — all 5 device-QA cases explicitly deferred by user decision, not run
- **Files modified:** 7 (2 created, 5 modified)

## Accomplishments (Tasks 1-3)

- `SyncTrigger` (`lib/data/sync/sync_trigger.dart`): `schedule()` debounces bursts (2s default) into a single `pushOutboxOnce()` call; `flush()` runs immediately for tests/manual button; a `schedule()`/timer fire while a push is in-flight queues exactly one rerun instead of overlapping pushes on the same outbox; `statusStream`/`lastStatus` classify `SyncAuthException` -> `authError` and `SyncTransientException` -> `transientError` without ever propagating either exception to the caller. 7 tests covering coalescing, non-reentrancy, both error classifications, success, stream emission, and `dispose()` safety.
- `SyncLocalDataSource.enqueueOutbox` gained a single `onOutboxEnqueued` callback fired after every outbox insert — the one funnel all 4 local data sources (`AudioLocalDataSource`, `GeoTriggerLocalDataSource`, `GeoPathLocalDataSource`, `RegionLocalDataSource`) already write through, so no other file needed to change (D-04).
- Service locator registers `SyncTrigger` and wires two trigger sources: `onOutboxEnqueued -> schedule()` and `connectivity_plus.onConnectivityChanged -> schedule()` when a network interface reappears (D-05), with the existing subscription cancelled first so `setupServiceLocator(reinitialize: true)` (used in background isolate re-entry) doesn't accumulate listeners.
- `connectivity_plus ^7.3.1` added; `ACCESS_NETWORK_STATE` permission added to `AndroidManifest.xml`.
- `DiagnosticsPanel` subscribes to `SyncTrigger.statusStream`, adds a `_syncStatusLabel` getter that always states remaining-pending count in the `ok` case (never a bare "all synced"), shows backend URL and API key length (never the key value), and distinguishes the auth-error message (points at `CINGULA_SYNC_API_KEY`) from the transient-error message. Manual button renamed `'Push outbox (stub)'` -> `'Forzar push ahora'` since it no longer targets a stub (D-06 preserved).

## Task Commits

1. **Task 1: SyncTrigger — debounce, un solo push en vuelo, estado observable** - `c1dcf0c` (feat, TDD: test+impl same commit since plan pre-wrote both)
2. **Task 2: Cablear el disparo automático — enqueueOutbox + reconexión + DI** - `c04063f` (feat)
3. **Task 3: Panel de debug con estado de sync honesto** - `4229b77` (feat)
4. **Task 4: Verificación en dispositivo** - no code commit (verification-only task); all 5 cases DEFERRED by explicit user decision (2026-08-29), see "Known Gaps" below

## Files Created/Modified
- `lib/data/sync/sync_trigger.dart` - `SyncTrigger`, `SyncTriggerStatus` enum
- `test/data/sync/sync_trigger_test.dart` - 7 tests, no sqflite/DB dependency
- `pubspec.yaml` / `pubspec.lock` - `connectivity_plus: ^7.3.1`
- `lib/data/datasources/local/sync_local_data_source.dart` - `onOutboxEnqueued` callback field + single call site
- `lib/core/di/service_locator.dart` - `SyncTrigger` registration, `onOutboxEnqueued` wiring, `connectivity_plus` subscription with cancel-before-resubscribe
- `android/app/src/main/AndroidManifest.xml` - `ACCESS_NETWORK_STATE` permission
- `lib/presentation/pages/home/widgets/diagnostics_panel.dart` - `_syncStatusLabel`, statusStream subscription, backend/API-key display, renamed manual button
- `linux/flutter/generated_plugin_registrant.*`, `windows/flutter/generated_plugin_registrant.*`, `macos/Flutter/GeneratedPluginRegistrant.swift` - regenerated by `flutter pub get` after adding `connectivity_plus`

## Decisions Made
- No new dependencies beyond `connectivity_plus` (already scoped in the plan and CLAUDE.md stack decision)
- Zero periodic timers anywhere in the trigger/wiring path — verified via grep (`Timer.periodic`/`Workmanager().registerPeriodic`: 0 matches)

## Deviations from Plan

### Non-functional: plan acceptance-criteria grep count off-by-one

- **Found during:** Task 3 verification
- **Issue:** Plan's acceptance criteria expects `grep -c "RunSyncUseCase" diagnostics_panel.dart` to return 2+ (import + usage). The actual import line is `import '../../../../domain/usecases/run_sync_usecase.dart';` (lowercase filename) which doesn't textually contain the class name `RunSyncUseCase`; only the one usage site (`getIt<RunSyncUseCase>()`) matches. Real occurrence count is 1.
- **Impact:** None — functionally the manual "Forzar push ahora" button is correctly wired to `RunSyncUseCase` (D-06 satisfied). This is the same class of plan-authoring grep-count mismatch already documented in 02-01-SUMMARY.md and 02-02-SUMMARY.md for this phase; not a code defect, no fix applied.

No other code deviations. Tasks 1-3 executed as written, including the plan's inline reference implementation for `SyncTrigger` (used verbatim). Task 4's `<acceptance_criteria>` expected either "aprobado" or a described failure for each of the 5 cases; the actual outcome (all 5 explicitly deferred, none run) is neither — documented honestly below rather than forced into either bucket, matching how 01-04-SUMMARY.md handled its own deferred device check. No code was touched in response to the deferral.

## Known Gaps

- **Task 4's on-device verification (SYNC-01, SYNC-03, SYNC-08's human-confirmation gate) is not done.** The user explicitly deferred all 5 cases on 2026-08-29 — no time to test on a real device right now, intends to run it later ("tonight"). This is **not** a bug report and **not** a failed test — it is a scope decision, exactly the same pattern as Phase 1's DATA-01 deferral (`01-04-SUMMARY.md`). The 5 deferred cases, none tested:
  1. Push automático (SYNC-01) — write reaches backend without touching any button
  2. Coalescing — cascade delete produces one POST /sync/push, not N+1
  3. Offline write + reconnect drain (SYNC-03, D-05) — airplane mode queues, reconnect drains, panel never claims "synced" while pending > 0
  4. Terminal auth error (SYNC-07, D-03) — bad key shows the specific auth message, no retry storm
  5. Manual button (D-06) — "Forzar push ahora" present and functional
  All 5 remain covered by the automated test suite for their non-device-dependent logic (`sync_trigger_test.dart`'s coalescing/reentrancy/status-classification tests, `sync_api_http_test.dart`'s 401/5xx/network-error classification, `run_sync_usecase_test.dart`'s markAttempt/no-markAttempt-on-auth behavior) — 64/64 green. What's missing is the human, on-device confirmation that the full wiring (real HTTP, real airplane mode, real cascade delete, real reconnect) behaves as the automated tests predict. Tracked in `STATE.md` → Blockers/Concerns, not silently closed. Steps to close: `02-04-PLAN.md` Task 4's `<how-to-verify>`, the exact same 5 cases listed above.

## Ponytail Audit (Tasks 1-3)

Ran per CLAUDE.md's mandatory per-phase ponytail checklist item.
- `SyncTrigger` has no persistent job queue, no per-entity-type debounce config, and no retry policy of its own — retries/backoff stay in `SyncClient`/`RunSyncUseCase` from 02-01/02-03, exactly per the plan's explicit "NO agregar" instruction.
- Zero `Timer.periodic`/`Workmanager().registerPeriodic` anywhere touched — confirmed by grep, matching the milestone's core anti-polling constraint.
- The `onOutboxEnqueued` callback is a single nullable function field on the existing funnel class, not a new event-bus/pub-sub abstraction — smallest thing that lets 4 call-site families opt in through 1 wire.
- `DiagnosticsPanel` changes are additive text/label changes to an existing debug-only widget — no new state-management layer, no history/graph, matching the plan's explicit scope limit.
- Nothing found to simplify further in Tasks 1-3.

## Issues Encountered

The assigned worktree's branch (`worktree-agent-ab45ee6f3ab1245db`) was checked out from a stale ancestor commit (`4b83a84`, pre-dating all of Phase 1/2) instead of current `main` (`f57fb73`, includes 02-01/02-02/02-03). `.planning/`, `CLAUDE.md`, `backend/`, and all prerequisite plan work did not exist in the worktree at start. Resolved identically to the pattern documented in 02-02/02-03's own summaries: `git merge --ff-only main` — a clean fast-forward (0 divergent commits on the worktree branch), discarding nothing, done before reading any plan files.

## User Setup Required

None further for Tasks 1-3 (reuses `CINGULA_API_BASE_URL`/`CINGULA_SYNC_API_KEY` `--dart-define` flags from 02-02/02-03). Task 4's on-device verification remains available to run later whenever the user chooses to pick it back up — requires the backend reachable (either deployed, or `cd backend && vercel dev` locally). The exact `flutter run` command and 5 numbered cases are in `02-04-PLAN.md` Task 4's `<how-to-verify>`.

## Next Phase Readiness

- Code for this plan is complete, tested, and committed (Tasks 1-3: `c1dcf0c`, `c04063f`, `4229b77`). Plan 02-05 depends on this plan's *code* (per ROADMAP.md), not on the pending human verification, so it is not blocked.
- SYNC-01, SYNC-03, SYNC-08 are code-complete with automated coverage but not yet requirement-complete — their on-device human confirmation (Task 4) is deferred, not done, and is flagged honestly rather than silently passed or blocking.
- If/when the user wants to close the gap, no new planning is needed — `02-04-PLAN.md` Task 4's `<how-to-verify>` (5 numbered cases) are still the exact instructions to run.

---
*Phase: 02-backend-real-push-sync*
*Tasks 1-3 completed and committed: 2026-08-29*
*Task 4 (all 5 device-QA cases) deferred by explicit user decision: 2026-08-29*

## Self-Check: PASSED

`lib/data/sync/sync_trigger.dart`, `test/data/sync/sync_trigger_test.dart` found on disk. Commits `c1dcf0c`, `c04063f`, `4229b77` found in `git log`. `flutter analyze` — 0 errors (2 pre-existing, out-of-scope info/warning). `flutter test` — 64/64 passing.
