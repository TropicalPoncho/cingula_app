---
phase: 10
slug: pull-cerrado-auth-dual-key
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-24
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node built-in test runner (`node --test`), colocated `*.test.js` files — matches existing `backend/api/sync/push.test.js` |
| **Config file** | none — `backend/package.json` `"test": "node --test"` already covers new colocated test files |
| **Quick run command** | `node --test backend/api/sync/pull.test.js` |
| **Full suite command** | `cd backend && npm test` |
| **Estimated runtime** | ~10-30s (integration tests hit a real Neon dev branch) |

---

## Sampling Rate

- **After every task commit:** Run the quick command for the file just touched (`node --test backend/api/sync/pull.test.js` or `.../state.test.js` or `.../auth.test.js`)
- **After every plan wave:** Run `cd backend && npm test` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | AUTH-01 | unit | `cd backend && node --test api/_lib/auth.test.js` | ✅ | ✅ green |
| 10-01-02 | 01 | 1 | AUTH-01 (403), PULL-04, PULL-03 (lock en push) | unit + integration | `cd backend && node --test api/sync/push.test.js api/sync/state.test.js` | ✅ | ✅ green |
| 10-02-01 | 02 | 2 | PULL-01, PULL-02, AUTH-01 | unit + integration | `cd backend && node --test api/sync/pull.test.js` | ✅ | ✅ green |
| 10-02-02 | 02 | 2 | PULL-03 | integration (Pool, transacción abierta) | `cd backend && DATABASE_URL=<neon-dev> node --test api/sync/pull.test.js` | ✅ | ✅ green |
| 10-03-01 | 03 | 1 | PULL-05 | manual | Notion "ERS · Backend — protocolo de sync" | ✅ | ✅ green |
| 10-04-01 | 04 | 3 | todos | audit | `cd backend && node --test` | ✅ | ✅ green |

*Status legend: pending (open square) · ✅ green · ❌ red · ⚠️ flaky*

Corrida completa contra rama Neon dev (compuerta Task 2, 2026-09-25): `tests 58, suites 0, pass 58,
fail 0, cancelled 0, skipped 0, todo 0` — incluye `PULL-03: pull concurrente espera al push abierto y
no saltea sus filas` como `ok` (no `# SKIP`).

---

## Wave 0 Requirements

- [x] `backend/api/_lib/auth.test.js` — stubs for AUTH-01 (dual-key accept/reject cases)
- [x] `backend/api/sync/pull.test.js` — stubs for PULL-01/02/03 (pagination, format parity, watermark-under-concurrency)
- [x] `backend/api/sync/state.test.js` — stub for PULL-04 (`recorridos` included in `serverCursor`/`lastSyncAt`)

*No new test framework needed — `node --test` and the existing `@neondatabase/serverless` dependency (via `Pool`/`Client` WebSocket client, no new package) cover all of the above per 10-RESEARCH.md.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pull contract published in Notion "ERS · Backend — protocolo de sync" | PULL-05 | Documentation publish action, not code | Confirm the Notion page has been updated with request/response shape, pagination, and watermark behavior before closing the phase; verify via `gestion-notion-rama` skill or direct page check |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-09-25
