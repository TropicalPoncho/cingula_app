---
phase: 10-pull-cerrado-auth-dual-key
verified: 2026-09-25T00:00:00Z
status: passed
score: 5/5 must-haves verified
---

# Phase 10: Pull cerrado + Auth dual-key Verification Report

**Phase Goal:** El backend puede servir a cualquier cliente autenticado (celular o web) todos los cambios del servidor vía pull paginado con watermark, con auth dual-key, dejando el contrato cerrado para que `app` programe su Fase 3.
**Verified:** 2026-09-25
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP Success Criteria) | Status | Evidence |
|---|---|---|---|
| 1 | `GET /sync/pull?cursor=0&limit=N` con `SYNC_API_KEY` o `WEB_API_KEY` devuelve las 7 tablas, borradas incluidas, orden por `change_seq`, paginado con `hasMore`, formato simétrico al push | ✓ VERIFIED | `backend/api/sync/pull.js:15-23` genera `PULL_SQL` desde `SYNCABLE_TABLES`/`TABLE_SPEC` (7 tablas); `pull.test.js` "PULL-01/02" y "PULL-01: WEB_API_KEY..." pasan (skipped sin DB, corridos en verde contra Neon dev per 10-VALIDATION.md) |
| 2 | Un push que comitea tarde nunca es salteado por un pull posterior (watermark real, probado contra Neon dev) | ✓ VERIFIED | `pull.js:47-53` toma `pg_advisory_xact_lock_shared(SYNC_LOCK_KEY)` antes del SELECT bajo `ReadCommitted`; `push.js:44-47` toma `pg_advisory_xact_lock` como primer elemento del array de `sql.transaction`; `pull.test.js` "PULL-03" usa `Pool` con transacción abierta real y assert `settled === false` antes del COMMIT — 10-04-SUMMARY documenta corrida real contra Neon dev: 58/58 pass, 0 skipped, PULL-03 `ok` |
| 3 | `GET /sync/state` incluye `recorridos` en `serverCursor`/`lastSyncAt` | ✓ VERIFIED | `state.js:7-9` genera `STATE_SQL` desde `SYNCABLE_TABLES` (incluye recorridos); `state.test.js` verifica `STATE_SQL.includes('"recorridos"')` y test con DB confirma `lastSyncAt` viene de un recorrido insertado |
| 4 | Key que no matchea ninguna variable configurada (o ninguna configurada) es rechazada, nunca abre por default | ✓ VERIFIED | `auth.js:15-25` `apiKeyRole`: `if (expected.length === 0) continue` — variable vacía/ausente nunca matchea; `auth.test.js` cubre los 12 casos de ausencia/vacío para ambas keys |
| 5 | Contrato de pull publicado en Notion "ERS · Backend — protocolo de sync" antes de cerrar la fase | ✓ VERIFIED | 10-03-SUMMARY documenta la publicación (no se pudo re-verificar Notion en vivo desde esta sesión); 10-04-SUMMARY Task 1 check G confirma coincidencia contrato↔código (defaults 500/1000, mensajes de error, forma de respuesta) |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `backend/api/_lib/auth.js` | `apiKeyRole` dual-key, `AUTH_ERROR`, `READ_ONLY_ERROR` | ✓ VERIFIED | Exports exactamente lo esperado; `requireApiKey` eliminado (0 matches en `backend/`) |
| `backend/api/_lib/db.js` | `SYNC_LOCK_KEY` única constante | ✓ VERIFIED | `export const SYNC_LOCK_KEY = 20260923` con comentario `ponytail:` documentando el techo |
| `backend/api/sync/push.js` | lock exclusivo primero, 403 para `web` | ✓ VERIFIED | Orden correcto en `sql.transaction`; `role !== 'sync'` → 403 |
| `backend/api/sync/pull.js` | GET /sync/pull, lock compartido, paginación | ✓ VERIFIED | Único export `default`; SQL generado desde spec, sin columnas hardcodeadas |
| `backend/api/sync/state.js` | `STATE_SQL` desde `SYNCABLE_TABLES` | ✓ VERIFIED | `grep -c FROM artistas` = 0 (no queda lista a mano) |
| `backend/api/_lib/auth.test.js`, `push.test.js`, `pull.test.js`, `state.test.js` | Tests PULL-01..04, AUTH-01 | ✓ VERIFIED | Todos presentes, cubren exactamente los casos del `<behavior>` de cada plan |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `push.js` | `pg_advisory_xact_lock` | primer elemento de `sql.transaction` | ✓ WIRED | `push.js:44-47`, confirmado antes de `...outbox.map` |
| `pull.js` | `pg_advisory_xact_lock_shared` | primer elemento bajo `ReadCommitted` | ✓ WIRED | `pull.js:47-53` |
| `push.js`/`pull.js` | `db.js` (`SYNC_LOCK_KEY`) | import compartido | ✓ WIRED | `grep -rln "20260923" backend/api` = solo `db.js`; ambos importan la constante, cero literales duplicados |
| `state.js`/`pull.js` | `spec.js` (`SYNCABLE_TABLES`/`TABLE_SPEC`) | `.map()` | ✓ WIRED | Confirmado por lectura directa y por ausencia de columnas hardcodeadas |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| PULL-01 | 10-02 | Pull paginado, 7 tablas, borradas, orden por change_seq | ✓ SATISFIED | `pull.js` + `pull.test.js`; REQUIREMENTS.md marcado Complete |
| PULL-02 | 10-02 | Payload simétrico al push, epoch segundos, strings | ✓ SATISFIED | `field()`/`selectTable()` en `pull.js`; test verifica columnas y tipos |
| PULL-03 | 10-01 (lado push), 10-02 (lado pull + test) | No-salto por watermark, probado contra Neon dev | ✓ SATISFIED | Test de concurrencia real (Pool + transacción abierta), corrida documentada 58/58 sin skip |
| PULL-04 | 10-01 | `/sync/state` incluye recorridos | ✓ SATISFIED | `STATE_SQL` generado desde spec (7 tablas) |
| PULL-05 | 10-03 | Contrato publicado en Notion | ✓ SATISFIED (no re-verificable en vivo esta sesión) | 10-03-SUMMARY + check G de 10-04 |
| AUTH-01 | 10-01 | Dual-key, revocable por separado, cerrado por default | ✓ SATISFIED | `apiKeyRole`, 12 casos de test cubriendo ausencia/vacío |

No orphaned requirement IDs found — REQUIREMENTS.md lists only these 6 for Phase 10, all claimed across the four plans.

### Anti-Patterns Found

None. `grep` for `TODO|FIXME|XXX|HACK|PLACEHOLDER` and stub-return patterns across the 5 modified backend files returned nothing beyond the intentional `ponytail:` comments (which document deliberate simplifications with their ceiling, per convention). `backend/package.json` has exactly 1 dependency, 0 devDependencies — no speculative additions.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full suite (no DB) | `cd backend && node --test` | `tests 53, pass 48, fail 0, skipped 5` | ✓ PASS (skips are the 5 DB-only cases, expected without `DATABASE_URL`) |
| Lock literal uniqueness | `grep -rln "20260923" backend/api` | only `db.js` | ✓ PASS |
| No dead `requireApiKey` | `grep -rn "requireApiKey" backend/` | 0 matches | ✓ PASS |
| No stray isolation levels | `grep -rn "isolationLevel: 'RepeatableRead'\|'Serializable'" backend/` (excluding node_modules) | 0 matches | ✓ PASS |
| ponytail comments present with ceiling | `grep -c "ponytail:" db.js push.js pull.js` | 1, 2, 1 | ✓ PASS |

Live Neon-dev run (58/58 pass, 0 skipped, PULL-03 `ok`) was executed outside this session per the phase's human gate (Task 2 of 10-04) and is documented consistently in `10-04-SUMMARY.md` and `10-VALIDATION.md`. Code inspected in this session (lock ordering, isolation level, SQL generation) matches what that documented run would need to actually exercise the concurrency guarantee — no inconsistency found between the SUMMARY's narrative and the code.

### Data-Flow Trace (Level 4)

Not applicable in the UI sense — this phase is a backend API. Traced instead: `pull.js` response `changes[].payload` → built via `json_build_object` directly from live table columns (`SELECT ... FROM "${t}" WHERE change_seq > $1`), not a static/hardcoded return. `state.js` `currentState` → real `MAX(change_seq)`/`MAX(updated_at)` aggregate query, not a stub. Both flow from real Postgres queries, no disconnected hardcoded values.

### Human Verification Required

None outstanding. The one genuinely human-only item (Notion contract review, PULL-05) was already executed as the phase's blocking human gate (10-04 Task 2), with the user's approval documented in `10-04-SUMMARY.md` and `10-VALIDATION.md` ("El usuario también confirmó en el chat que la sección GET /sync/pull ... es suficiente"). This session did not have live Notion access to re-fetch and re-confirm the page content independently — if the user wants an independent re-check of the live Notion page text against the acceptance strings in `10-03-PLAN.md`, that would be the only remaining optional check, but it is not a gap: the phase's own process already required and recorded this confirmation.

### Gaps Summary

None. All 5 ROADMAP success criteria are backed by code that exists, is substantive (no stubs), is wired (imports/exports trace correctly, SQL generated from the single source of truth `spec.js`), and — for the concurrency guarantee — was exercised for real against Neon Postgres (not skipped) per the documented human gate. All 6 requirement IDs (PULL-01 through PULL-05, AUTH-01) are implemented, tested, and marked Complete in REQUIREMENTS.md with no orphans. The ponytail audit (10-04 Task 1) found nothing to remove, and independent grep checks in this session reproduce the same clean results.

---

*Verified: 2026-09-25*
*Verifier: Claude (gsd-verifier)*
