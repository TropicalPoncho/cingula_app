---
phase: 02-backend-real-push-sync
plan: 03
subsystem: sync
tags: [http, sync, error-handling, dart]

# Dependency graph
requires:
  - phase: 02-backend-real-push-sync
    plan: 01
    provides: SyncClient with backoff-aware pendingOutbox/markAttempt (post-schema-v6)
  - phase: 02-backend-real-push-sync
    plan: 02
    provides: /sync/push and /sync/state wire contract implemented by backend/
provides:
  - "SyncApiHttp: real SyncApi implementation over package:http, talking the exact wire_contract from 02-02"
  - "SyncAuthException (terminal, 401) / SyncTransientException (retryable, network/5xx/408/400) error taxonomy"
  - "RunSyncUseCase.pushOutboxOnce distinguishes terminal from transient failures: 401 never consumes backoff (D-03), everything else marks every row's attempt"
  - "Service locator resolves SyncApi to SyncApiHttp; SyncApiStub deleted"
affects: [02-04, 02-05]

tech-stack:
  added: ["http ^1.6.0"]
  patterns:
    - "Two flat exception classes (SyncAuthException, SyncTransientException), no hierarchy/codes/sealed class -- plan's explicit ponytail instruction"
    - "Non-200/non-401 HTTP responses (400/408/500/503/etc.) are all classified transient; a 400 won't actually succeed on retry but a third error category for a payload-bug-only case wasn't worth it (research Open Question 1)"

key-files:
  created:
    - lib/data/sync/sync_errors.dart
    - lib/data/sync/sync_api_http.dart
    - test/data/sync/sync_api_http_test.dart
    - test/domain/usecases/run_sync_usecase_test.dart
  modified:
    - pubspec.yaml
    - lib/core/config/api_config.dart
    - lib/domain/usecases/run_sync_usecase.dart
    - lib/core/di/service_locator.dart
  deleted:
    - lib/data/sync/sync_api_stub.dart

key-decisions:
  - "All non-200/non-401 statuses (400, 408, 500, 503, ...) classified as SyncTransientException -- adding a third terminal category for 400 would only matter for a client-side payload bug, which retrying harmlessly surfaces again rather than silently dropping (plan's explicit decision, not a deviation)"

requirements-completed: [SYNC-01, SYNC-03, SYNC-07]

# Metrics
duration: 8min
completed: 2026-08-29
---

# Phase 02 Plan 03: HTTP Sync Client + Terminal/Transient Error Handling Summary

**`SyncApiHttp` replaces `SyncApiStub` end-to-end (DI included), speaking the exact `/sync/push` + `/sync/state` wire contract from plan 02-02 with a two-class error taxonomy so `RunSyncUseCase` can tell a bad API key (401, no backoff, D-03) from a network/server failure (backoff on every row).**

## Performance

- **Duration:** ~8 min (task commits 11:35:15 → 11:38:20 -03:00, plus test-writing and dart-define compile verification)
- **Tasks:** 2/2 completed, both TDD (RED test-first, GREEN implementation matching plan's prescribed code)
- **Files modified:** 4 created, 4 modified, 1 deleted

## Accomplishments
- `SyncApiHttp` (`lib/data/sync/sync_api_http.dart`) implements `SyncApi.pushOutbox`/`fetchState` over `package:http`, sending `Authorization: Bearer <ApiConfig.apiKey>` + JSON body exactly matching the `wire_contract`; `pullChanges` throws `UnimplementedError` (Phase 3 scope, SYNC-04/05)
- `SyncAuthException` (401, terminal) and `SyncTransientException` (network error / 5xx / 408 / 400, retryable) in `lib/data/sync/sync_errors.dart` — two flat classes, no hierarchy
- `ApiConfig.apiKey` reads `CINGULA_SYNC_API_KEY` via `String.fromEnvironment`, mutable at runtime for the debug panel, same pattern as existing `baseUrl`
- `RunSyncUseCase.pushOutboxOnce` now catches both exception types: `SyncAuthException` rethrows untouched (D-03 — a 401 is a config problem, not a network one, so it must not burn backoff); `SyncTransientException` calls `markAttempt` for every row in the batch before rethrowing
- `service_locator.dart` registers `SyncApiHttp()` instead of `SyncApiStub()`; the stub file is deleted (`grep -rn "SyncApiStub" lib/ test/` returns nothing)
- 15 `MockClient`-based tests for `SyncApiHttp` (request shape, 200/401/500/503/408/400, network `ClientException`, `pullChanges`) + 6 hand-written-fake tests for `RunSyncUseCase` (empty outbox, full ack, partial ack, idempotent double-push, transient error path, auth error path) — no DB, no mocking library

## Task Commits

1. **Task 1: Dependencia http, API key en ApiConfig, tipos de error, y SyncApiHttp** - `4ae3a39` (feat)
2. **Task 2: RunSyncUseCase distingue terminal de transitorio + DI apunta al backend real** - `ea89e7c` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `lib/data/sync/sync_errors.dart` - `SyncAuthException`, `SyncTransientException`
- `lib/data/sync/sync_api_http.dart` - `SyncApiHttp implements SyncApi`, classifies every response as success/terminal/transient
- `test/data/sync/sync_api_http_test.dart` - 15 tests via `package:http/testing.dart` `MockClient`
- `pubspec.yaml` - added `http: ^1.6.0` (no `dio`, no `mockito`/`mocktail`)
- `lib/core/config/api_config.dart` - `static String apiKey` reading `CINGULA_SYNC_API_KEY`
- `lib/domain/usecases/run_sync_usecase.dart` - try/catch around `_api.pushOutbox` distinguishing the two exception types
- `lib/core/di/service_locator.dart` - `SyncApi` now resolves to `SyncApiHttp()`
- `test/domain/usecases/run_sync_usecase_test.dart` - `_FakeSyncApi implements SyncApi`, `_FakeSyncClient implements SyncClient`, 6 tests
- `lib/data/sync/sync_api_stub.dart` - deleted (superseded, no remaining references)

## Decisions Made
- 400 classified transient rather than adding a third terminal error category — matches the plan's explicit call-out of research's Open Question 1; a payload bug on 400 will keep surfacing on retry rather than silently vanishing, and a config-driven distinction wasn't worth building for a case that only appears with a client bug.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Lint] Removed unnecessary `as http.Request` casts in test file**
- **Found during:** Task 1, `flutter analyze` after writing `sync_api_http_test.dart`
- **Issue:** `MockClient`'s callback parameter is already typed `http.Request`; casting it again is a no-op flagged as `unnecessary_cast`.
- **Fix:** Removed the redundant cast at all 3 call sites (`captured = request as http.Request;` → `captured = request;`).
- **Files modified:** `test/data/sync/sync_api_http_test.dart`
- **Commit:** `ea89e7c` (bundled into Task 2's commit since Task 1's commit had already landed)

**2. [Rule 1 - Lint] Removed unnecessary null-assertion in test file**
- **Found during:** Task 2, `flutter analyze` after writing `run_sync_usecase_test.dart`
- **Issue:** `if (_throwException != null) throw _throwException!;` — the `!` triggers `unnecessary_non_null_assertion` since Dart's flow analysis already narrows the type inside the `if`.
- **Fix:** Reassigned to a local `final exception = _throwException;` before the null check, which narrows cleanly without an assertion.
- **Files modified:** `test/domain/usecases/run_sync_usecase_test.dart`
- **Commit:** `ea89e7c`

**Issues NOT fixed (out of scope):**
- `flutter analyze` reports one pre-existing `deprecated_member_use` info for `WillPopScope` in `lib/presentation/pages/data_browser_page.dart:354` — untouched by this plan, out of scope per the deviation-rules scope boundary.
- One residual `unused_element_parameter` warning on `_FakeSyncApi`'s `serverCursor` constructor parameter (always uses its default across the current test cases) — cosmetic, left as-is since the parameter is legitimate test-fake flexibility, not dead code.

## Ponytail Audit

Ran per CLAUDE.md's mandatory per-phase ponytail checklist item.
- `sync_errors.dart` stayed at exactly the plan's 2 flat exception classes — no hierarchy, no error codes, no `sealed class`.
- `sync_api_http.dart` has no retry/backoff logic of its own (that already lives in `SyncClient`/`RunSyncUseCase` from plan 02-01) and no response-classification abstraction beyond the plan's explicit `ponytail:` comment already embedded in the reference code (non-200/non-401 = transient, deliberately not a third category).
- `RunSyncUseCase`'s try/catch is the minimum shape needed to route two exception types to two different side effects — no error-handler registry, no strategy pattern.
- No new dependencies beyond `http` (verified: 0 `dio`/`mockito`/`mocktail` matches in `pubspec.yaml`).
- Nothing found to simplify further.

## Issues Encountered

The assigned worktree's branch (`worktree-agent-a2d441850635caabb`) was checked out from a stale ancestor commit (`4b83a84`, pre-dating all of Phase 1/2 planning and both prerequisite plans 02-01/02-02) instead of current `main` (`e3853d7`). `.planning/`, `CLAUDE.md`, `backend/`, and the local outbox-backoff changes from 02-01 did not exist in the worktree at start. Resolved identically to plan 02-02's own note on this: `git fetch origin && git merge --ff-only main` — a clean fast-forward (4b83a84 is an ancestor of e3853d7), discarding nothing, before reading any plan files.

## User Setup Required

None. This plan only adds Flutter-side HTTP client code; it reuses the `CINGULA_API_BASE_URL` / `CINGULA_SYNC_API_KEY` `--dart-define` flags already established as the configuration mechanism in 02-02. The actual Neon/Vercel env var setup (`SYNC_API_KEY` on the backend, matching value passed to the app) remains the user's responsibility, already flagged in 02-02's summary and not blocking for this plan's own verification (which used `--dart-define=CINGULA_SYNC_API_KEY=x` against a `flutter build web` compile check, not a live server).

## Next Phase Readiness
- The app now speaks real HTTP to the backend from 02-02, manually triggered — automatic sync scheduling is plan 02-04's scope, unaffected by anything here
- `SyncAuthException`/`SyncTransientException` are exported and ready for any UI-level "sync failed" messaging plan 02-04/02-05 might add
- No blockers for downstream plans in this phase

---
*Phase: 02-backend-real-push-sync*
*Completed: 2026-08-29*

## Self-Check: PASSED

All 5 created/output files verified present on disk (`lib/data/sync/sync_errors.dart`, `lib/data/sync/sync_api_http.dart`, `test/data/sync/sync_api_http_test.dart`, `test/domain/usecases/run_sync_usecase_test.dart`, this SUMMARY.md). `lib/data/sync/sync_api_stub.dart` confirmed deleted. Both task commits (`4ae3a39`, `ea89e7c`) verified present in `git log`.
