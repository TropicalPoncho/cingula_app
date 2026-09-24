---
phase: 10
slug: pull-cerrado-auth-dual-key
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 10-01-01 | 01 | 1 | AUTH-01 | unit | `node --test backend/api/_lib/auth.test.js` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | PULL-01, PULL-02 | integration | `node --test backend/api/sync/pull.test.js` | ❌ W0 | ⬜ pending |
| 10-01-03 | 01 | 1 | PULL-03 | integration | `node --test backend/api/sync/pull.test.js` | ❌ W0 | ⬜ pending |
| 10-01-04 | 01 | 1 | PULL-04 | integration | `node --test backend/api/sync/state.test.js` | ❌ W0 | ⬜ pending |
| 10-02-01 | 02 | 2 | PULL-05 | manual | n/a — Notion publish | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/api/_lib/auth.test.js` — stubs for AUTH-01 (dual-key accept/reject cases)
- [ ] `backend/api/sync/pull.test.js` — stubs for PULL-01/02/03 (pagination, format parity, watermark-under-concurrency)
- [ ] `backend/api/sync/state.test.js` — stub for PULL-04 (`recorridos` included in `serverCursor`/`lastSyncAt`)

*No new test framework needed — `node --test` and the existing `@neondatabase/serverless` dependency (via `Pool`/`Client` WebSocket client, no new package) cover all of the above per 10-RESEARCH.md.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pull contract published in Notion "ERS · Backend — protocolo de sync" | PULL-05 | Documentation publish action, not code | Confirm the Notion page has been updated with request/response shape, pagination, and watermark behavior before closing the phase; verify via `gestion-notion-rama` skill or direct page check |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
