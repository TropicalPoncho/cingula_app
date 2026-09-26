---
phase: 11
slug: infra-de-deploy-mismo-proyecto-vercel
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-25
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node's built-in `node --test` (no external test framework) — `backend/package.json`: `"test": "node --test"` |
| **Config file** | none — plain `node --test` convention, picks up `*.test.js` files under `backend/api/` |
| **Quick run command** | `cd backend && npm test` |
| **Full suite command** | `cd backend && DATABASE_URL=<neon-dev-branch-url> npm test` |
| **Estimated runtime** | ~10-30 seconds (unit only) / longer with live `DATABASE_URL` (integration + PULL-03 concurrency test) |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && npm test` (fast unit pass — auth/spec validation untouched by routing change)
- **After every plan wave:** Run the full suite with `DATABASE_URL` pointed at the Neon dev branch, plus the scripted Preview smoke check (`backend/scripts/smoke-preview.sh`) against a real Preview deployment
- **Before `/gsd:verify-work`:** Both smoke checks green on a real Preview URL (INFRA-01 JSON response, INFRA-02 env var inspection), plus explicit confirmation the real phone still syncs against Production untouched
- **Max feedback latency:** ~60 seconds (unit suite is fast; the Preview smoke check requires a real deploy, which is the slowest step and must not be skipped per the phase's explicit "smoke test before merge to main" requirement)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 0 | INFRA-01 | smoke script | `bash backend/scripts/smoke-preview.sh <preview-url>` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | INFRA-01 | manual/scripted | `curl -s https://<preview-url>/sync/state -H "Authorization: Bearer $WEB_API_KEY"` returns valid JSON, not HTML | ✅ (curl, no file needed) | ⬜ pending |
| 11-02-01 | 02 | 1 | INFRA-02 | scripted env inspection | `vercel env pull --environment=preview .env.preview.local && grep DATABASE_URL .env.preview.local` differs from Production value | ✅ (documented command, no file needed) | ⬜ pending |
| 11-03-01 | 03 | 1 | INFRA-03 | trivial file-existence check | `test ! -f web/index.html && test ! -f web/manifest.json && test ! -d web/icons && test ! -f web/favicon.png && echo OK` | ✅ (one-liner, no dedicated test file) | ⬜ pending |
| 11-04-01 | 04 | 2 | INFRA-01/02/03 | unit (regression) | `cd backend && npm test` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/scripts/smoke-preview.sh` — curls `/sync/state` on a given Preview URL and asserts JSON content-type (not HTML), per RESEARCH.md "Pitfall 1" and "Don't Hand-Roll" — this is currently done ad hoc and must become repeatable for every future Preview deploy.
- [ ] Documented (not necessarily scripted) procedure for INFRA-02's env var inspection (`vercel env pull --environment=preview`) written into the plan text itself, so it's repeatable and never "assumed" (ADR-005 risk).
- [ ] `.github/workflows/*.yml` review — check whether any CI workflow assumes `cd backend && npm test` before finalizing which routing mechanism moves/keeps `backend/api/` in place (RESEARCH.md Open Question 3).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real phone push against Production still works, unchanged | INFRA-01 | Requires a physical device with the real app pointed at the live production sync endpoint — not something a CI script can simulate | Before merging the routing change to `main`, run the real app's sync flow against production once and confirm it completes without error (per ROADMAP success criterion 2 and CONTEXT.md's cutover-risk discretion) |
| Neon↔Vercel native integration connection state | INFRA-02 | Requires live Vercel dashboard (Storage tab) or Neon console access — not filesystem-verifiable (RESEARCH.md Open Question 1 / Environment Availability) | Check Vercel project's Storage tab for an existing Neon integration scoped to Preview before assuming it needs to be created from scratch |
| Confirming Preview `DATABASE_URL` is never Production's | INFRA-02 | Preview env vars from the native integration are injected via webhook and are not visible in the dashboard's static Environment Variables page (RESEARCH.md Anti-Pattern) | Run `vercel env pull --environment=preview .env.preview.local`, `grep DATABASE_URL .env.preview.local`, and confirm the host differs from the known Production `DATABASE_URL` host — never print the Production value in logs |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
