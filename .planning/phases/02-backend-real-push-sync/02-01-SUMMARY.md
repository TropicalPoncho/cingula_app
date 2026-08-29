---
phase: 02-backend-real-push-sync
plan: 01
subsystem: database
tags: [sqflite, sync-outbox, backoff, dart]

# Dependency graph
requires:
  - phase: 01-blindaje-de-datos-y-separaci-n-debug-usuario
    provides: sqflite schema (v5) with sync_outbox/sync_state tables, uuid/updated_at/deleted_at/logical_version on every syncable entity
provides:
  - "Local schema v6 with sync_outbox.next_attempt_at, migrating safely from v5 without touching existing rows"
  - "Pure-Dart Full Jitter backoff (fullJitterBackoff) + eligibility check (isOutboxRowEligible), unit tested"
  - "SyncClient.pendingOutbox filters out rows still in backoff while preserving FIFO order (takeWhile)"
  - "SyncClient.markAttempt persists next_attempt_at using Full Jitter over attempt_count"
  - "All 5 outbox delete-enqueue sites (geo_trigger_local_data_source, geo_path_local_data_source) now include logical_version in the payload"
affects: [02-02, 02-03, 02-04, 02-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Full Jitter backoff (AWS Architecture Blog): delay = random(0, min(cap, base * 2^attempt)), resolved once at failure time and persisted as next_attempt_at (not recomputed on read)"
    - "Outbox eligibility filtered client-side via takeWhile over FIFO-ordered rows, not a SQL WHERE clause, to keep global send order stable"

key-files:
  created:
    - lib/data/sync/sync_backoff.dart
    - test/data/sync/sync_backoff_test.dart
  modified:
    - lib/data/datasources/local/app_database.dart
    - lib/data/datasources/local/sync_local_data_source.dart
    - lib/data/sync/sync_client.dart
    - lib/data/datasources/local/geo_trigger_local_data_source.dart
    - lib/data/datasources/local/geo_path_local_data_source.dart
    - lib/domain/usecases/run_sync_usecase.dart

key-decisions:
  - "Used next_attempt_at (resolved instant) instead of research's proposed last_attempt_at (recomputed on read) so jitter is decided once at failure time, keeping outbox reads deterministic without re-rolling Random on every pendingOutbox() call"
  - "_nextDeleteVersion helper duplicated verbatim (3 lines) in both geo_trigger_local_data_source.dart and geo_path_local_data_source.dart rather than extracted to a shared file -- per plan's explicit ponytail call: duplication cheaper than a new shared module for 3 lines"

patterns-established:
  - "sync_backoff.dart: pure functions + const Duration values only, no classes, no configurable strategy -- ladder rung 6/7 (one line / minimum code), reuse this file directly rather than reimplementing backoff math elsewhere in the sync pipeline"

requirements-completed: [SYNC-02, SYNC-03]

# Metrics
duration: 4min
completed: 2026-08-29
---

# Phase 02 Plan 01: Local Outbox Backoff + Delete Versioning Summary

**Schema v6 adds persisted `next_attempt_at` to sync_outbox, a pure-Dart Full Jitter backoff helper with 9 unit tests, and `logical_version` now flows through all 5 delete-enqueue sites so the server can order versioned deletes.**

## Performance

- **Duration:** ~4 min (commit-to-commit: 11:21:21 → 11:25:24 -03:00)
- **Tasks:** 3 completed (Task 2 followed full TDD: RED → GREEN)
- **Files modified:** 6 existing + 2 new = 8

## Accomplishments
- Local SQLite schema bumped to v6: `sync_outbox.next_attempt_at` added via both fresh-install DDL and an `oldVersion < 6` `ALTER TABLE`, following the codebase's existing try/catch migration pattern exactly
- `fullJitterBackoff()`/`isOutboxRowEligible()` extracted as pure, dependency-free functions (`lib/data/sync/sync_backoff.dart`), covered by 9 passing unit tests including a seeded-`Random` determinism check
- `SyncClient.pendingOutbox` now skips outbox rows still in backoff via `takeWhile`, and `markAttempt` persists the resolved next-retry instant instead of only incrementing a counter
- All 5 sites across the codebase that enqueue a `delete` outbox op (2 in `geo_trigger_local_data_source.dart`, 3 in `geo_path_local_data_source.dart`) now select and forward `logical_version`, bumped via a small `_nextDeleteVersion` helper matching `withUpdateMetadata`'s existing bump rule

## Task Commits

1. **Task 1: Migración schema v6 — columna next_attempt_at en sync_outbox** - `cd72bf5` (feat)
2. **Task 2: Helper puro de backoff (Full Jitter) + elegibilidad** - `fb73542` (test, RED) → `3c286f3` (feat, GREEN; no refactor needed)
3. **Task 3: SyncClient filtra por elegibilidad y persiste el próximo intento; payloads de delete llevan logical_version** - `2474fe0` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `lib/data/sync/sync_backoff.dart` - Full Jitter backoff curve + outbox eligibility check, pure Dart
- `test/data/sync/sync_backoff_test.dart` - 9 tests covering the behavior spec (ranges, cap, negative attempt, determinism, eligibility edges)
- `lib/data/datasources/local/app_database.dart` - `_dbVersion = 6`, `next_attempt_at` column in `_onCreate`/v5 DDL/`oldVersion < 6` ALTER
- `lib/data/datasources/local/sync_local_data_source.dart` - `enqueueOutbox` seeds `next_attempt_at: null`; `incrementOutboxAttempt` takes optional `nextAttemptAt`
- `lib/data/sync/sync_client.dart` - `pendingOutbox` filters via `isOutboxRowEligible`/`takeWhile`; `markAttempt` computes and persists `nextAttemptAt`
- `lib/data/datasources/local/geo_trigger_local_data_source.dart` - `deleteOrphaned`/`deleteByAudioAssetId` payloads carry `uuid` + `logical_version`
- `lib/data/datasources/local/geo_path_local_data_source.dart` - `deleteByAudioAssetId`/`deleteById` (path + trigger rows) payloads carry `uuid` + `logical_version`
- `lib/domain/usecases/run_sync_usecase.dart` - `markAttempt` call now passes `attemptCount` from the row already in hand

## Decisions Made
- `next_attempt_at` over `last_attempt_at` (see key-decisions above) — avoids re-rolling jitter on every read, keeping eligibility a single deterministic integer comparison
- Duplicated the 3-line `_nextDeleteVersion` helper in both local data source files rather than adding a shared module, per the plan's explicit instruction

## Deviations from Plan

None — plan executed exactly as written, including its explicit deviation-from-research note (next_attempt_at vs last_attempt_at) which was already called out in the plan text itself, not something discovered during execution.

**Verification note (not a code deviation):** the plan's acceptance-criteria `grep -c "logical_version" ...` commands assume one match per line; because payload lines in this implementation contain both the `'logical_version'` key and a `row['logical_version']` value read on the same line, `grep -c` (line-count) returns 4/12 instead of the specified 5/7 threshold. `grep -o | wc -l` (occurrence-count) confirms 6 and 15 occurrences respectively — comfortably above threshold and functionally correct (2 SELECT + 2 payload sites in geo_trigger, 3+3 in geo_path). `flutter analyze` (0 errors) and `flutter test` (37/37 passing, full suite) both confirm correctness independent of this grep quirk.

## Ponytail Audit

Ran per CLAUDE.md's mandatory per-phase ponytail checklist item.
- `sync_backoff.dart` stayed at 2 functions + 2 constants, no classes, no pluggable strategy — matches plan's explicit "NO agregar" instruction.
- `_nextDeleteVersion` duplicated (not extracted to a shared file) is a deliberate rung-2/3 tradeoff already made by the plan itself: 3 lines duplicated twice is cheaper than a new shared module for two files in different "libraries."
- No new abstractions, interfaces, or config surfaces introduced. Nothing to simplify further.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required. This plan is 100% local (SQLite schema + pure Dart), no HTTP wiring yet (that's plan 02-03 per the plan's own scope note).

## Next Phase Readiness
- `sync_client.dart` and the outbox delete sites are ready for the HTTP-backed `SyncApi` implementation landing in later waves of this phase (02-02 backend scaffold is running in parallel; 02-03+ wires transient-vs-terminal error handling on top of `markAttempt`)
- Schema v6 is safe for existing installs: migration is additive-only (`ALTER TABLE ADD COLUMN`), verified via the same try/catch pattern already proven in v3/v4 migrations — no data loss risk introduced
- No blockers for downstream plans in this phase

---
*Phase: 02-backend-real-push-sync*
*Completed: 2026-08-29*

## Self-Check: PASSED

All created files found on disk (`lib/data/sync/sync_backoff.dart`, `test/data/sync/sync_backoff_test.dart`, `.planning/phases/02-backend-real-push-sync/02-01-SUMMARY.md`). All 4 task commits found in `git log` (`cd72bf5`, `fb73542`, `3c286f3`, `2474fe0`).
