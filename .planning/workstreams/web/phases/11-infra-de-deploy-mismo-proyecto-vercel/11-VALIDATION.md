---
phase: 11
slug: infra-de-deploy-mismo-proyecto-vercel
status: complete
nyquist_compliant: true
wave_0_complete: true
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
| 11-01-01 | 01 | 1 | INFRA-01 | smoke script (Wave 0) | `bash -n web/scripts/smoke-preview.sh` + usage exit 2 | ✅ | ✅ green |
| 11-01-02 | 01 | 1 | INFRA-03 | file-existence | `test -z "$(git ls-files web/index.html web/manifest.json web/favicon.png web/icons)"` | ✅ | ✅ green |
| 11-02-02 | 02 | 1 | INFRA-02 | scripted env inspection (Wave 0) | `bash web/scripts/check-preview-db.sh ws/web` → `INFRA-02 OK` | ✅ | ✅ green |
| 11-03-01 | 03 | 2 | INFRA-01 | identidad de módulos | `SHIMS OK` (mecanismo (d), luego superseded — ver 11-03-SUMMARY addendum: `backend/` se disolvió, `web/api/` son handlers reales, no shims) | ✅ | ✅ green (superseded) |
| 11-03-02 | 03 | 2 | INFRA-01 | spike `vercel dev` | `bash web/scripts/smoke-preview.sh http://localhost:3000` — bloqueado por bug de `@vercel/node` local (ver 11-03-SUMMARY Deviations); ruteo/descubrimiento sí validado (404 vs 500) | ✅ (no concluyente localmente) | ⚠️ no concluyente local, ✅ real (ver 11-04) |
| 11-04-02 | 04 | 3 | INFRA-01, INFRA-02 | smoke Preview real + host + serverCursor | `SMOKE_API_KEY=... bash web/scripts/smoke-preview.sh <preview-url>` → `SMOKE OK`, `serverCursor: "3420"`; `check-preview-db.sh ws/web` → `INFRA-02 OK` contra el deploy real | ✅ | ✅ green |
| 11-05-01 | 05 | 4 | todos | audit + regresión | `cd web && npm test` → 48 pass/0 fail/5 skip | ✅ | ✅ green |
| 11-05-02 | 05 | 4 | INFRA-01 | manual (celular) + smoke prod | `bash web/scripts/smoke-preview.sh https://cingula.vercel.app` → `SMOKE OK`; celular real: push pre-merge (`"Mi rutaggfgg"`, confirmado por query directa a Neon) y post-merge con reconexión offline→online (`"Mi ruta prueba ultima ahora"`, confirmado igual) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Nota (plan 05):** la tabla del borrador asumía el mecanismo shim de `backend/vercel.json` +
`backend/scripts/*`. El mismo día, antes del checkpoint del plan 04, se decidió disolver `backend/`
como paquete separado y mover todo a `web/` (ver `11-03-SUMMARY.md` addendum) — todos los comandos
de esta tabla reflejan los paths reales (`web/scripts/`, `web/api/`), no los del borrador original.

---

## Wave 0 Requirements

- [x] `web/scripts/smoke-preview.sh` (creado como `backend/scripts/smoke-preview.sh` en 11-01, movido a `web/` en el merge del mismo día) — curls `/sync/state` en una Preview URL dada y verifica JSON, no HTML.
- [x] Procedimiento documentado (y scripteado: `web/scripts/check-preview-db.sh`) para la inspección de env vars de INFRA-02 (`vercel env pull --environment=preview`), repetible, nunca asumido.
- [x] `.github/workflows/` no existe (confirmado en 11-01) — ningún CI depende de la ubicación de `backend/api/`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real phone push against Production still works, unchanged | INFRA-01 | Requires a physical device with the real app pointed at the live production sync endpoint — not something a CI script can simulate | Before merging the routing change to `main`, run the real app's sync flow against production once and confirm it completes without error (per ROADMAP success criterion 2 and CONTEXT.md's cutover-risk discretion) |
| Neon↔Vercel native integration connection state | INFRA-02 | Requires live Vercel dashboard (Storage tab) or Neon console access — not filesystem-verifiable (RESEARCH.md Open Question 1 / Environment Availability) | Check Vercel project's Storage tab for an existing Neon integration scoped to Preview before assuming it needs to be created from scratch |
| Confirming Preview `DATABASE_URL` is never Production's | INFRA-02 | Preview env vars from the native integration are injected via webhook and are not visible in the dashboard's static Environment Variables page (RESEARCH.md Anti-Pattern) | Run `vercel env pull --environment=preview .env.preview.local`, `grep DATABASE_URL .env.preview.local`, and confirm the host differs from the known Production `DATABASE_URL` host — never print the Production value in logs |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-09-29
