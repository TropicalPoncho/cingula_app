---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: verifying
stopped_at: "02-05-PLAN.md Tasks 1-2 complete + live production bug found and fixed on real device (outbox FIFO head-of-line-blocking from pre-02-01 delete payloads). Task 3 (7-case e2e) and 02-04 Task 4 (5-case on-device) both deferred by user decision to stop for the night."
last_updated: "2026-09-01T21:00:00.000Z"
last_activity: 2026-09-01
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 9
  completed_plans: 8
  percent: 89
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-08)

**Core value:** Que la app siga siendo confiable en el bolsillo del usuario mientras se construye la infraestructura de sync — ningún cambio de este milestone puede arriesgar los datos que ya existen en el celular.
**Current focus:** Phase 02 — backend-real-push-sync

## Current Position

Phase: 02 (backend-real-push-sync) — EXECUTING
Plan: 4 of 5 complete (02-01, 02-02, 02-03, 02-04) — 1 plan in progress (02-05)
Status: 02-05 Tasks 1-2 complete and merged. Backend live at https://cingula.vercel.app.
  During setup, a real production bug surfaced on the user's own device: SyncTrigger was
  swallowing push exceptions (only a status enum survived, no message, nowhere) and 8 stale
  `op: delete` outbox rows (enqueued before 02-01 added logical_version to delete payloads)
  were rejecting their entire batch at the backend, which combined with the FIFO
  head-of-line-blocking in SyncClient.pendingOutbox silently stalled ALL 1186 pending outbox
  rows -- including the user's real historical field recordings, never before backed up
  since no real backend existed until today. Fixed live: added onError logging to
  SyncTrigger (commit 5e0c4da), added SyncLocalDataSource.repairDeleteOutboxPayloads() +
  debug-panel button, and applied the repair directly on-device (app closed, read-only
  diff-verified before any write, SHA-256 round-trip verified after) since the button wasn't
  reachable during this session. Outbox drained 1186 -> 0; new writes confirmed landing in
  Neon. Full writeup: 02-05-SUMMARY.md.
  Task 3 (7-case structured e2e checklist) and 02-04's Task 4 (5-case on-device checklist)
  both remain formally undone -- deferred by explicit user decision to stop for the night,
  not failures. See Blockers/Concerns.
Last activity: 2026-09-01

Progress: [█████████░] 89%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: - min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | 15 | 2 tasks | 6 files |
| Phase 01 P02 | 25 | 3 tasks | 7 files |
| Phase 01 P03 | 20min | 2 tasks | 1 files |
| Phase 01 P04 | 25min | 2 tasks | 4 files |
| Phase 02 P01 | 4min | 3 tasks | 8 files |
| Phase 02 P02 | 12min | 3 tasks | 14 files |
| Phase 02 P03 | 8min | 2 tasks | 9 files |
| Phase 02 P04 | 20min | 3 tasks | 7 files |
| Phase 02 P05 (partial) | ~4.5h | 2/4 tasks | 10 files (incl. live prod fix) |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: UI-01 (toggle debug/usuario) folded into Phase 1 alongside DATA-01/02 — both touch the same debug panel, small and low-risk, no need for a standalone phase.
- Roadmap: Phase 4 (geofencing) sequenced after Phase 3 following research's build-order (isolates real-device/platform risk from backend work) even though it is architecturally independent of sync and could run in parallel.
- PROJECT.md: Ponytail audit is a hard part of every execution phase's checklist, not just a milestone close-out — reflected as a Ponytail audit note on every phase in ROADMAP.md.
- [Phase 01]: db_recovery.dart kept pure-Dart (dart:io only) so rename-not-delete recovery logic is unit-testable without sqflite/path_provider plugin bindings
- [Phase 01]: Destructive debug actions (recreate DB, import DB) deleted outright rather than confirmation-guarded, per project memory feedback_no_destructive_automation
- [Phase 01]: Plan 01-02 ejecutado sin desviaciones: AppModeConfig, HiddenTapGesture, y UserModeView creados exactamente segun el contrato de interfaces del plan.
- [Phase 01]: [Phase 01]: Plan 01-03's Task 1 referenced a _RecordingBanner/RecorderService wiring in home_page_impl.dart that only existed in an uncommitted stash (WIP sync/geofencing work set aside before Phase 1) -- implemented the debug/user split without conditioning that nonexistent code; UI-01/DATA-01 acceptance holds since UserModeView never renders a recording banner.
- [Phase 01]: Removed dead DatabaseRecoveryEvent.occurredAt field (populated but never read) during phase-01 ponytail audit
- [Phase 01]: Phase 01 closed with one deferred item: user explicitly declined on-device DB-corruption-recovery QA (real device holds only copy of field data); automated db_recovery_test.dart coverage stands, human confirmation deferred not failed
- [Phase 02-backend-real-push-sync]: [Phase 02 Plan 01]: next_attempt_at (resolved instant) chosen over research's last_attempt_at so backoff jitter is decided once at failure time, not re-rolled on every outbox read
- [Phase 02]: Backend (02-02) escrito en JS ESM en vez de TypeScript: Node v22.14 confirmado, .ts hubiera necesitado tsx/tsconfig para 2 endpoints
- [Phase 02]: Backend (02-02): tabla unica synced_entities (current+previous version) en vez de 4 tablas espejo del schema SQLite -- payload es opaco al servidor hasta el pull de Fase 3
- [Phase 02]: [Phase 02 Plan 03]: 400 classified as SyncTransientException (not a third terminal category) -- a client payload bug on 400 keeps surfacing on retry rather than being silently dropped
- [Phase 02]: [Phase 02 Plan 04]: SyncTrigger is purely event-driven (write, reconnect, manual button) with zero periodic timers, matching the milestone's anti-polling constraint
- [Phase 02]: [Phase 02 Plan 04]: Task 4's 5-case on-device verification explicitly deferred by user (2026-08-29, no time now, will run later) -- code complete and automated-tested, not a failure, tracked in Blockers/Concerns same as Phase 1's DATA-01 deferral
- [Phase 02]: [Phase 02 Plan 05]: Ponytail audit (Task 1) found and fixed real duplication (SyncApiHttp's 401/non-200 classification block, identical in pushOutbox and fetchState, extracted to a private _throwForStatus helper) and one truly dead symbol (SyncTrigger.isRunning, zero callers anywhere including tests, removed). SyncTrigger.flush() was flagged by the same check (test-only callers) but kept deliberately: D-06 has the manual button call RunSyncUseCase directly (not flush()), so flush()'s only caller is the test suite -- but it is the sole deterministic way to test coalescing/reentrancy without depending on real timers, so removing it would have been a net loss for regression coverage, not a simplification. Documented with a ponytail: comment instead of deleted.
- [Phase 02]: [Phase 02 Plan 05, Task 2]: Vercel connected via GitHub import in the dashboard (Root Directory=backend) instead of the plan's `vercel link`/`vercel --prod` CLI flow -- user's choice, functionally equivalent (same env vars, same deploy target), not a deviation worth re-litigating.
- [Phase 02]: [Phase 02 Plan 05, unplanned]: SyncTrigger's swallowed exceptions + SyncClient's FIFO takeWhile head-of-line-blocking combined to silently stall the entire 1186-row outbox behind 8 stale pre-02-01 delete rows -- found and fixed live on the user's device (repairDeleteOutboxPayloads, logical_version=1, safe because no real backend ever existed before this session). See 02-05-SUMMARY.md for the full root-cause chain and the verification steps taken before writing to the user's device (read-only diff, then SHA-256 round-trip after write).
- [Phase 02]: dart_defines.json (gitignored) + .vscode/launch.json now wire --dart-define-from-file for local VS Code runs, mirroring backend/.env's pattern for the Flutter side. 3 stale launch configs pointing at an already-cleaned-up worktree removed.

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4: real-device/real-terrain geofencing latency numbers are estimates from docs, not measured in Comarca Andina — flag for on-the-ground validation during Phase 4 planning.
- Phase 01: DATA-01 on-device human verification of DB-corruption cold-start recovery is deferred (not done) -- user declined to corrupt their real device's DB (only copy of field data) and chose not to use an emulator alternative either. Automated db_recovery_test.dart coverage stands and is green; the full AppDatabase.init() catch-path has not been confirmed end-to-end on real hardware. Steps to close: 01-04-PLAN.md task 2, section C, steps 9-14, recommended on an emulator.
- Phase 02: 02-04 Task 4 on-device human verification (5 cases: auto-push, coalescing, offline+reconnect, terminal auth error, manual button) is deferred (not done). Automated coverage stands and is green (flutter analyze 0 errors, flutter test 64/64); code committed (c1dcf0c, c04063f, 4229b77). Steps to close: 02-04-PLAN.md Task 4's `<how-to-verify>`, 5 numbered cases. Note: several of these were informally exercised during the 2026-09-01 live debugging session (auto-push fired repeatedly, honest status observed under real error conditions) but not through the formal checklist.
- Phase 02: 02-05 Task 3 (7-case structured end-to-end verification against the real Neon+Vercel deploy) and Task 4 (close 02-VALIDATION.md) are deferred -- user chose to stop for the night after ~4.5 hours including significant live production debugging (see 02-05-SUMMARY.md). Not a failure: the backend is live, tested, and actively receiving real data (1186-row historical backlog successfully synced during this session). Caso 1 (SYNC-01), Caso 4 (SYNC-07), Caso 5 (SYNC-08), and Caso 7 (data regression) all have strong informal evidence from tonight's session; Caso 2 (kill-mid-push dedup), Caso 3 (offline+backoff), and Caso 6 (2-version window) remain fully untested. Steps to close: 02-05-PLAN.md Task 3's `<how-to-verify>`, 7 numbered cases, then Task 4.
- Phase 02: minor UI bug found in passing (unrelated to sync) -- `RenderFlex overflowed by 55 pixels` in `lib/presentation/widgets/trigger_map.dart:275`, seen in the device console during tonight's session. Not fixed, not blocking, cosmetic only.
- Phase 02: the "Reparar deletes viejos" debug-panel button (added in commit 5e0c4da) did not appear on the user's device after a VS Code hot-restart during tonight's session; root cause not confirmed (suspected stale/cached build, matching the session's recurring theme -- try `flutter clean` first when revisiting). The underlying repair was applied successfully via direct on-device file repair instead, so this is a UI-visibility follow-up, not a blocker for the fix itself.

## Session Continuity

Last session: 2026-09-01T21:00:00.000Z
Stopped at: "02-05 Tasks 1-2 done + live bug fix (outbox unblocked, 1186->0). Task 3 (02-05) and Task 4 (02-04) both deferred by user choice to stop for the night."
Resume file: .planning/phases/02-backend-real-push-sync/02-05-SUMMARY.md
