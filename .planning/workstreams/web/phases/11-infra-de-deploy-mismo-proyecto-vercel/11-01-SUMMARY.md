---
phase: 11-infra-de-deploy-mismo-proyecto-vercel
plan: 01
subsystem: infra
tags: [bash, curl, vercel, ci, smoke-test]

requires: []
provides:
  - "backend/scripts/smoke-preview.sh: GET-only routing smoke test for /sync/state, distinguishes function JSON from Vercel HTML (rewrite/Root Directory/SPA fallback/Deployment Protection)"
  - "Confirmed .github/workflows/ does not exist — no CI depends on backend/api location"
  - "web/ fully cleared of Flutter web scaffold, ready for the Phase 12 SPA"
affects: [11-03, 11-04, 11-05, 12]

tech-stack:
  added: []
  patterns:
    - "smoke-preview.sh: mktemp+trap for response body, curl -w for status+content-type in one call, safe optional header array via ${hdr[@]+\"${hdr[@]}\"} under set -u"

key-files:
  created:
    - backend/scripts/smoke-preview.sh
  modified: []

key-decisions:
  - "web/ leftovers deleted entirely (index.html, manifest.json, favicon.png, icons/) per 11-CONTEXT.md — no favicon or asset carried forward, Phase 12 defines SPA identity from scratch"
  - "Smoke script never sends -X or --data (grep-enforced): stays GET-only so it's safe to run against production"

requirements-completed: [INFRA-01, INFRA-03]

duration: 5min
completed: 2026-09-26
---

# Phase 11 Plan 01: Smoke Test de Ruteo + Limpieza de web/ Summary

**Bash smoke-preview.sh (GET-only, curl+mktemp+trap) distinguishing `/sync/state` function JSON from Vercel HTML, plus full removal of Flutter web scaffold from `web/`**

## Performance

- **Duration:** ~5 min (git commits 23:59:36 → 00:00:47 local time)
- **Completed:** 2026-09-26
- **Tasks:** 2/2
- **Files modified:** 8 (1 created, 7 deleted)

## Accomplishments
- `backend/scripts/smoke-preview.sh`: repeatable GET-only routing check for `GET /sync/state` — unauthenticated check requires no secrets (expects 401 JSON `invalid or missing API key` from `auth.js`), optional `SMOKE_API_KEY` check expects 200 JSON with `serverCursor`, optional `VERCEL_BYPASS` adds `x-vercel-protection-bypass` header for Deployment Protection.
- Confirmed `.github/workflows/` does not exist (`.github/` only has `copilot-instructions.md`) — no CI workflow depends on `backend/api`'s current location, so plan 03's routing-mechanism change (if it moves `backend/api/`) has no CI working-directory to break.
- `web/` cleared entirely of Flutter's default web scaffold (`index.html`, `manifest.json`, `favicon.png`, `icons/Icon-{192,512,maskable-192,maskable-512}.png`) — `git ls-files web` now returns nothing.

## Task Commits

Each task was committed atomically:

1. **Task 1: Smoke test de ruteo `backend/scripts/smoke-preview.sh` + chequeo de CI** - `cc6e7bd` (feat)
2. **Task 2: Borrar los restos de Flutter web de `web/` (INFRA-03)** - `332784e` (chore)

**Plan metadata:** (this commit) `docs(11-01): complete plan`

## Files Created/Modified
- `backend/scripts/smoke-preview.sh` - GET-only routing smoke test for `/sync/state`; distinguishes JSON (function reached) from HTML (Vercel misroute/SPA fallback/Deployment Protection)
- `web/index.html`, `web/manifest.json`, `web/favicon.png`, `web/icons/*.png` (7 files) - deleted, Flutter web scaffold no longer needed

## Decisions Made
- Followed 11-CONTEXT.md decision: total removal of `web/` leftovers, no favicon/asset kept — Phase 12 defines the SPA's visual identity from zero.
- Script enforces GET-only via structure (no `-X`, no `--data`) rather than a runtime guard, matching the plan's acceptance criteria (`grep -c -e "-X " -e "--data"` must return 0).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Installed missing `backend/node_modules` (npm install)**
- **Found during:** overall plan verification (step 3: `cd backend && npm test`)
- **Issue:** `backend/node_modules/` was not present in this worktree (not committed, correctly gitignored), so `_lib/db.js`'s `@neondatabase/serverless` import failed for 3 test files (`pull.test.js`, `push.test.js`, `state.test.js`), producing `ERR_MODULE_NOT_FOUND`.
- **Fix:** Ran `npm install` inside `backend/` to restore `node_modules` from the existing `package.json`/lockfile. No source or dependency version changes — nothing to commit (node_modules is gitignored).
- **Files modified:** none tracked (node_modules is gitignored)
- **Verification:** `cd backend && npm test` — 48 pass, 0 fail, 5 skipped (skips are pre-existing, unrelated to this plan)
- **Committed in:** N/A (no trackable file changes)

---

**Total deviations:** 1 auto-fixed (1 blocking, environment setup only)
**Impact on plan:** No code or behavior change; unblocked the plan's own verification step. No scope creep.

## Issues Encountered
None beyond the deviation above.

## User Setup Required

None - no external service configuration required. The smoke script's real-network test against a live Preview/production URL happens in plan 03 (per plan text); this plan only verifies syntax and local error paths (no-arg exit code 2, unreachable-host exit code 1).

## Next Phase Readiness
- Plan 03 (spike `vercel dev` / routing mechanism decision) can now use `backend/scripts/smoke-preview.sh` to validate whichever routing mechanism it picks, and knows no `.github/workflows/` exists to break.
- `web/` is empty and ready for Phase 12's SPA build output.
- Plans 04/05 (Preview vs. production cursor comparison, real mobile push) can reuse the same script with `SMOKE_API_KEY` set.

---
*Phase: 11-infra-de-deploy-mismo-proyecto-vercel*
*Completed: 2026-09-26*

## Self-Check: PASSED

- FOUND: backend/scripts/smoke-preview.sh
- FOUND: commit cc6e7bd (Task 1)
- FOUND: commit 332784e (Task 2)
- `git ls-files web` returns 0 files (leftovers fully removed)
