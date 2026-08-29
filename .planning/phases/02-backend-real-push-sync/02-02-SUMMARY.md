---
phase: 02-backend-real-push-sync
plan: 02
subsystem: api
tags: [nodejs, vercel-functions, neon, postgres, sync, auth]

# Dependency graph
requires: []
provides:
  - "backend/ sub-project: standalone Node ESM project (npm test / vercel dev)"
  - "requireApiKey() bearer-token auth (backend/api/_lib/auth.js), fail-closed, constant-time compare"
  - "synced_entities Postgres schema (backend/schema.sql): current + 1 previous version per record"
  - "upsertStatement()/validateOutboxItem()/extractVersion() (backend/api/_lib/outbox.js)"
  - "POST /sync/push and GET /sync/state Vercel Function handlers implementing the wire_contract in 02-02-PLAN.md"
affects: [02-03, 02-05]

tech-stack:
  added: ["@neondatabase/serverless ^1.1.0", "node:test (built-in, no test framework dep)"]
  patterns:
    - "Vercel legacy Node handler style: export default async function handler(request, response)"
    - "Idempotent upsert via ON CONFLICT + CASE-per-column gated on 'current_version < EXCLUDED.current_version', single statement gives both idempotency and a 2-version retention window"
    - "Lazy DB connection (getSql() memoized, throws only when actually called) so importing db.js never requires DATABASE_URL — keeps pure-logic tests DB-free"

key-files:
  created:
    - backend/package.json
    - backend/vercel.json
    - backend/.gitignore
    - backend/.env.example
    - backend/README.md
    - backend/schema.sql
    - backend/api/_lib/auth.js
    - backend/api/_lib/auth.test.js
    - backend/api/_lib/db.js
    - backend/api/_lib/outbox.js
    - backend/api/_lib/outbox.test.js
    - backend/api/sync/push.js
    - backend/api/sync/push.test.js
    - backend/api/sync/state.js
  modified: []

key-decisions:
  - "Backend written in JavaScript ESM (.js), not TypeScript — Node v22.14 confirmed in this environment, .ts would need --experimental-strip-types/tsx + tsconfig for 2 endpoints and ~40-line modules; explicit deviation from RESEARCH/VALIDATION docs, documented inline in the plan and in this summary."
  - "Single synced_entities table instead of 4 tables mirroring SQLite schema — payload is opaque to the server this phase (no per-column queries until Phase 3 pull), so one generic table avoids 4x DDL for zero benefit."
  - "Authorization: Bearer over X-API-Key — equal implementation cost, more conventional REST."

requirements-completed: [SYNC-01, SYNC-02, SYNC-06, SYNC-07]

duration: 12min
completed: 2026-08-29
---

# Phase 02 Plan 02: Backend Real (Neon + Vercel Functions) Summary

**Standalone `backend/` Node ESM sub-project with bearer-token-authed `/sync/push` and `/sync/state` Vercel Functions over Neon Postgres, implementing idempotent + 2-version-windowed upsert in a single `ON CONFLICT` SQL statement.**

## Performance

- **Duration:** ~12 min (first commit 11:21:32, last commit 11:23:17, plus setup/verification either side)
- **Started:** 2026-08-29T14:21:00Z (approx, UTC)
- **Completed:** 2026-08-29T14:23:17Z (approx, UTC)
- **Tasks:** 3/3
- **Files modified:** 14 created, 0 modified

## Accomplishments
- `backend/` sub-project scaffolded (package.json, vercel.json rewrite rule, .env.example, README, .gitignore) — deployable to Vercel with zero build step
- `requireApiKey()` bearer-token auth: fail-closed on missing config, constant-time comparison, case-insensitive `Bearer` prefix, 8 passing tests (SYNC-07)
- `synced_entities` Postgres schema + `upsertStatement()` implementing idempotency (SYNC-02) and current+1-previous version retention (SYNC-06) in one `ON CONFLICT ... DO UPDATE` statement gated by version comparison
- `POST /sync/push` (auth → validate-all-or-400 → transactional batch upsert → `ackedIds`) and `GET /sync/state` handlers matching the plan's `wire_contract` field-for-field
- Integration test (`push.test.js`) covering idempotency, 2-version window, out-of-order arrival, and delete against real Postgres — skips cleanly without `DATABASE_URL` so `npm test` stays green everywhere; will run for real in plan 02-05 against a Neon dev branch

## Task Commits

1. **Task 1: Scaffold backend/ + auth por bearer token** - `9a1f2c0` (feat)
2. **Task 2: Schema Postgres + upsert versionado idempotente** - `6c1948f` (feat)
3. **Task 3: Handlers /sync/push y /sync/state + test de integración** - `ab97389` (feat)

**Plan metadata:** (this commit)

_All three tasks were type="auto"; Tasks 1-2 were `tdd="true"` — tests written and run before/alongside implementation per the plan's `<behavior>` blocks._

## Files Created/Modified
- `backend/package.json` - ESM project, `node --test`, single dependency `@neondatabase/serverless`
- `backend/vercel.json` - rewrites `/sync/:path*` → `/api/sync/:path*` (client hits `/sync/push`, Vercel file-routes to `/api/sync/push.js`)
- `backend/.env.example`, `backend/README.md`, `backend/.gitignore` - setup docs and node_modules/.env exclusion
- `backend/schema.sql` - `synced_entities` table: current_* + previous_* columns, PK (table_name, record_uuid)
- `backend/api/_lib/auth.js` + `auth.test.js` - `requireApiKey()`, 8 tests
- `backend/api/_lib/db.js` - lazy `getSql()`, never throws on import
- `backend/api/_lib/outbox.js` + `outbox.test.js` - `SYNCABLE_TABLES`, `extractVersion`, `validateOutboxItem`, `upsertStatement`, 9 pure tests
- `backend/api/sync/push.js` + `push.test.js` - POST handler + Postgres integration test
- `backend/api/sync/state.js` - GET handler

## Decisions Made
- JavaScript ESM over TypeScript for the backend (see key-decisions above) — explicit, documented deviation from RESEARCH/VALIDATION, justified by the plan itself as avoiding scaffolding with no return for 2 endpoints
- Single generic `synced_entities` table over 4 tables mirroring SQLite — payload is opaque server-side this phase
- No new dependencies beyond `@neondatabase/serverless`; no test framework added (`node:test` built into Node 22)

## Deviations from Plan

None functionally — plan executed exactly as written, including its explicit in-plan deviation (JS not TS, documented in Task 1's `<action>` and carried into this summary).

One cosmetic discrepancy worth noting: Task 2's acceptance criteria expects `grep -c "Number.isInteger" backend/api/_lib/outbox.js` to return `3` or more, but the plan's own reference code (copied verbatim) contains exactly 2 occurrences (`extractVersion` and the `id` check in `validateOutboxItem`). All 9 `<behavior>`-specified test cases pass and the validation logic is complete; this is a miscounted grep in the plan's own acceptance criteria, not a functional gap, and was not "fixed" by adding a redundant check.

**Total deviations:** 0 functional, 1 documented plan-authoring inconsistency (no code impact)
**Impact on plan:** None — all `<done>` criteria and behavior tests satisfied.

## Issues Encountered

The assigned worktree's branch (`worktree-agent-a8687f06f9c9860fd`) was checked out from a stale ancestor commit (`4b83a84`, pre-dating all of Phase 1 and Phase 2 planning) instead of the current `main` tip (`28bf81a`). `.planning/` and `CLAUDE.md` did not exist in the worktree at start. Resolved by fast-forward merging local `main` into the worktree branch (`git merge main`, fast-forward, no conflicts) before reading any plan files — this only added commits, discarded nothing, and is safe because the worktree branch had no divergent commits of its own beyond what main already contained.

## User Setup Required

**External services require manual configuration** (per this plan's `user_setup` frontmatter — no separate USER-SETUP.md was generated for this plan, documenting inline here instead):
- **Neon**: create a project + a `dev` branch, set `DATABASE_URL` (pooled connection string) — needed to actually run `backend/api/sync/push.test.js`'s integration test and to deploy
- **Vercel**: `cd backend && vercel link`, then `vercel env add SYNC_API_KEY` with a value generated via `openssl rand -hex 32`; the same value must be passed to the Flutter app as `--dart-define=CINGULA_SYNC_API_KEY=<value>` (plan 02-03's concern, not this plan's)

Neither is required for this plan's own `npm test` to pass (integration test skips cleanly without `DATABASE_URL`); both are needed before plan 02-05 runs the integration test for real and before any deployment.

## Next Phase Readiness
- `backend/` is ready for `vercel link` + deploy once Neon/Vercel env vars are set by the user
- Plan 02-03 (Flutter-side `SyncApi` implementation) can now target the exact `wire_contract` this plan implements
- Plan 02-05 (integration/closing) can run `push.test.js` for real against a Neon dev branch
- No blockers introduced by this plan

---
*Phase: 02-backend-real-push-sync*
*Completed: 2026-08-29*

## Self-Check: PASSED

All 14 created files verified present on disk; all 3 task commits (`9a1f2c0`, `6c1948f`, `ab97389`) verified present in `git log`.
