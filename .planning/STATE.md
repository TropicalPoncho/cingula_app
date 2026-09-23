---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 02.1-11-PLAN.md
last_updated: "2026-09-23T18:37:43.041Z"
last_activity: 2026-09-23
progress:
  total_phases: 8
  completed_phases: 3
  total_plans: 21
  completed_plans: 21
  percent: 89
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-08)

**Core value:** Que la app siga siendo confiable en el bolsillo del usuario mientras se construye la infraestructura de sync — ningún cambio de este milestone puede arriesgar los datos que ya existen en el celular.
**Current focus:** Phase 02.1 — modelo-de-datos-objetivo

## Current Position

Phase: 02.2
Plan: Not started
Status: Ready to execute
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
Last activity: 2026-09-23

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
| Phase 02.1 P01 | 20min | 3 tasks | 12 files |
| Phase 02.1 P06 | 20min | 3 tasks | 17 files |
| Phase 02.1 P02 | 25min | 3 tasks | 9 files |
| Phase 02.1 P03 | 25min | 3 tasks | 3 files |
| Phase 02.1 P04 | n/a | 3 tasks | 2 files |
| Phase 02.1 P05 | 15min | 3 tasks | 6 files |
| Phase 02.1 P08 | 40min | 3 tasks | 29 files |
| Phase 02.1 P09 | 25min | 2 tasks | 13 files |
| Phase 02.1 P10 | 35min | 3 tasks | 10 files |
| Phase 02.1 P11 | 35min | 2 tasks | 4 files |

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
- [Phase 02.1]: Node uuid v5 via node:crypto; shared vectors asserted in Dart and Node
- [Phase 02.1]: Plan 06: Region removed from code; regions table and region_id kept in schema marked legacy-upgrade
- [Phase 02.1]: Plan 02: entity_prev PK enforces current+1 previous version; spec.js is single source for backend schema
- [Phase 02.1]: Plan 03: foreign_key_check por tabla nueva; migrateToV7 devuelve reporte
- [Phase 02.1]: Plan 04: pre-flight GO sobre base real (78/72/462/20); 15 audios huerfanos se migran tal cual
- [Phase 02.1]: Plan 05: payload del reenvio = SELECT * (tablas v7 == TABLE_SPEC); tablas viejas renombradas legacy_*, nunca borradas
- [Phase 02.1]: [Phase 02.1 Plan 08]: GeoPathRepositoryImpl.createPath crea una obra draft con el nombre del path cuando falta obraUuid (D-22), inyectando ObraRepository en el repositorio
- [Phase 02.1]: [Phase 02.1 Plan 08]: sync_outbox/sync_state quedan fuera de v7_schema.dart (su forma no cambia); AppDatabase._onCreate las sigue creando directamente
- [Phase 02.1]: [Phase 02.1 Plan 08]: debugOnBeforeVerifyV7 (@visibleForTesting) reexpone el hook de migrateToV7 sin agregar un tercer parametro a init(), para no romper la firma exacta que el plan fija por contrato
- [Phase 02.1]: [Phase 02.1 Plan 09]: se elimino _activeTrigger de MonitorUserLocationUseCase (D-28 vuelve dead code la rama de trigger suelto)
- [Phase 02.1]: [Phase 02.1 Plan 09]: aviso de respaldo exitoso (D-19/D-26) implementado en home_page_impl.dart via AppDatabase.lastBackupPath, mismo patron one-shot que lastRecoveryEvent
- [Phase 02.1]: [Phase 02.1 Plan 10]: GeoTriggerLocalDataSource.onObraTouched (closure opcional) cablea insert/deleteByPathUuid/deleteOrphaned a ObraRepository.refreshCover, evitando dependencia circular directa entre data sources
- [Phase 02.1]: [Phase 02.1 Plan 10]: GeoPathLocalDataSource.deleteByUuid no dispara refreshCover (borra triggers por SQL directo, fuera del files_modified de este plan) -- diferido, no arreglado
- [Phase 02.1]: [Phase 02.1 Plan 11]: ponytail audit borro la cadena onStateChanged/samplingMode (MonitorUserLocationUseCase -> PlaybackNotifier), ya senalada como candidata en 02.1-06-SUMMARY.md
- [Phase 02.1]: [Phase 02.1 Plan 11]: MODEL-06 se deja explicitamente en Pending en 02.1-VALIDATION.md; el gap de ~117 filas sin title/name en Neon no se fuerza a verde

### Roadmap Evolution

- Phase 02.1 inserted after Phase 2: Modelo de Datos Objetivo y Migración (URGENT) — 2026-09-19. Origen: durante discuss-phase 3 (pull) el usuario aclaró que el pull es el mecanismo de distribución a celulares de otros usuarios (no solo su propio celular), lo que expuso que el modelo actual (ids enteros locales como referencia entre tablas, blob JSONB genérico en el servidor, progreso de usuario mezclado con contenido) no alcanza para la versión final. Decisión: rediseñar el modelo antes del pull, en vez de parchear. Fase 3 pasa a depender de 2.1; `03-CONTEXT.md` queda como borrador.
- Phase 02.2 inserted after Phase 2.1: Subida de Audios a Storage (URGENT) — 2026-09-19. Decidido en discuss-phase 2.1 (D-21): los .wav siguen solo en el celular; se respaldan en una fase propia antes del pull. Fase 3 pasa a depender de 2.2.

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4: real-device/real-terrain geofencing latency numbers are estimates from docs, not measured in Comarca Andina — flag for on-the-ground validation during Phase 4 planning.
- Phase 01: DATA-01 on-device human verification of DB-corruption cold-start recovery is deferred (not done) -- user declined to corrupt their real device's DB (only copy of field data) and chose not to use an emulator alternative either. Automated db_recovery_test.dart coverage stands and is green; the full AppDatabase.init() catch-path has not been confirmed end-to-end on real hardware. Steps to close: 01-04-PLAN.md task 2, section C, steps 9-14, recommended on an emulator.
- Phase 02: 02-04 Task 4 on-device human verification (5 cases: auto-push, coalescing, offline+reconnect, terminal auth error, manual button) is deferred (not done). Automated coverage stands and is green (flutter analyze 0 errors, flutter test 64/64); code committed (c1dcf0c, c04063f, 4229b77). Steps to close: 02-04-PLAN.md Task 4's `<how-to-verify>`, 5 numbered cases. Note: several of these were informally exercised during the 2026-09-01 live debugging session (auto-push fired repeatedly, honest status observed under real error conditions) but not through the formal checklist.
- Phase 02: 02-05 Task 3 (7-case structured end-to-end verification against the real Neon+Vercel deploy) and Task 4 (close 02-VALIDATION.md) are deferred -- user chose to stop for the night after ~4.5 hours including significant live production debugging (see 02-05-SUMMARY.md). Not a failure: the backend is live, tested, and actively receiving real data (1186-row historical backlog successfully synced during this session). Caso 1 (SYNC-01), Caso 4 (SYNC-07), Caso 5 (SYNC-08), and Caso 7 (data regression) all have strong informal evidence from tonight's session; Caso 2 (kill-mid-push dedup), Caso 3 (offline+backoff), and Caso 6 (2-version window) remain fully untested. Steps to close: 02-05-PLAN.md Task 3's `<how-to-verify>`, 7 numbered cases, then Task 4.
- Phase 02: minor UI bug found in passing (unrelated to sync) -- `RenderFlex overflowed by 55 pixels` in `lib/presentation/widgets/trigger_map.dart:275`, seen in the device console during tonight's session. Not fixed, not blocking, cosmetic only.
- Phase 02: the "Reparar deletes viejos" debug-panel button (added in commit 5e0c4da) did not appear on the user's device after a VS Code hot-restart during tonight's session; root cause not confirmed (suspected stale/cached build, matching the session's recurring theme -- try `flutter clean` first when revisiting). The underlying repair was applied successfully via direct on-device file repair instead, so this is a UI-visibility follow-up, not a blocker for the fix itself.
- 02.1-07: ambiguous-id abort (geo_triggers:42,43; geo_paths:11,12) fixed via id_overrides.json, confirmed on a re-run against the same Neon dev branch. But the re-run surfaced a new, unrelated blocker one layer down: ~117 rows (63 audios, 27 obras, 27 paths) have no recoverable title/name in `synced_entities` (lost to old partial-payload pushes + current+1-previous retention) -- decide policy before 02.1-12; MODEL-06 still incomplete. See 02.1-07-SUMMARY.md and 02.1-NEON-REHEARSAL.md.

## Session Continuity

Last session: 2026-09-22T02:57:22.445Z
Stopped at: Completed 02.1-11-PLAN.md
Resume file: None
