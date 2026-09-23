---
status: partial
phase: 02-backend-real-push-sync
source: [02-VERIFICATION.md]
started: 2026-09-16T00:00:00.000Z
updated: 2026-09-16T00:00:00.000Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Kill-mid-push / no-duplicates against the live deploy (SYNC-02)
expected: Edit an entity, let a push start against https://cingula.vercel.app, kill the app (swipe from recents) before the push completes, reopen, and force another push. `SELECT record_uuid, count(*) FROM synced_entities GROUP BY record_uuid HAVING count(*) > 1;` against Neon returns 0 rows — no duplicates, final current_version reflects the edit.
result: [pending] — attempted 2026-09-16, timing uncertain (app may not have been killed before the push completed), inconclusive not negative.

### 2. Auth-invalid handling from the running app, without a retry storm (SYNC-07, D-03)
expected: Recompiling with a wrong CINGULA_SYNC_API_KEY and editing an entity shows the panel's specific auth-error message, leaves the row pending, and Vercel logs show at most one request per write/reconnect — no retry loop.
result: [pending] — backend-side 401/200 already confirmed live via curl; app-side UI/behavior not yet observed on device.

### 3. Coalescing on cascade delete against the live deploy
expected: Deleting a geo_path with several associated geo_triggers produces exactly one POST /sync/push request, not N+1.
result: [pending] — debounce/non-reentrancy logic is unit-tested, not yet observed against a real cascade delete on device.

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
