---
phase: 10-pull-cerrado-auth-dual-key
plan: 01
subsystem: backend/api (auth + sync push/state)
tags: [auth, dual-key, advisory-lock, sync]
dependency-graph:
  requires: []
  provides:
    - "apiKeyRole(request) -> 'sync' | 'web' | null (backend/api/_lib/auth.js)"
    - "SYNC_LOCK_KEY (backend/api/_lib/db.js)"
    - "/sync/state incluye recorridos (STATE_SQL desde SYNCABLE_TABLES)"
  affects:
    - "10-02 (pull.js importa apiKeyRole y SYNC_LOCK_KEY compartido)"
tech-stack:
  added: []
  patterns:
    - "timingSafeEqual por candidata en un loop de [rol, env var], config faltante = cerrado"
    - "advisory lock exclusivo como primera sentencia del array de sql.transaction (el orden ES la garantía, D-01)"
    - "SQL generado desde SYNCABLE_TABLES (spec.js) en vez de listas a mano, para que una tabla nueva no pueda volver a faltar"
key-files:
  created:
    - backend/api/sync/state.test.js
  modified:
    - backend/api/_lib/auth.js
    - backend/api/_lib/auth.test.js
    - backend/.env.example
    - backend/api/_lib/db.js
    - backend/api/sync/push.js
    - backend/api/sync/push.test.js
    - backend/api/sync/state.js
decisions:
  - "requireApiKey eliminado sin dejar alias muerto; sus dos llamadores (push.js, state.js) migrados a apiKeyRole en la misma tarea que introduce la función (Task 2), per plan"
metrics:
  duration: "~35 min"
  completed: "2026-09-24"
---

# Phase 10 Plan 01: Auth dual-key + advisory lock (lado push) + fix recorridos en /sync/state Summary

Auth dual-key con alcance (`apiKeyRole` reemplaza `requireApiKey`), advisory lock de Postgres tomado
por push como primera sentencia de su transacción, y `/sync/state` generado desde `SYNCABLE_TABLES`
para que `recorridos` (y cualquier tabla futura del spec) no pueda volver a faltar.

## What Was Built

**Task 1 — `apiKeyRole` (AUTH-01, D-09/D-10/D-11):** `backend/api/_lib/auth.js` reemplaza
`requireApiKey(request) -> null | AUTH_ERROR` por `apiKeyRole(request) -> 'sync' | 'web' | null`.
Itera `[['sync', 'SYNC_API_KEY'], ['web', 'WEB_API_KEY']]`, compara cada candidata con
`timingSafeEqual` por separado, y salta cualquier variable de entorno vacía o ausente (config
faltante nunca abre acceso, ni siquiera contra un header vacío). `auth.test.js` migrado con un
helper `withEnv({SYNC_API_KEY, WEB_API_KEY}, fn)` que setea/borra ambas variables por caso; 12 tests
(8 migrados + 4 nuevos de `WEB_API_KEY`). `backend/.env.example` documenta la variable nueva.

**Task 2 — advisory lock + 403 + recorridos (D-01/ADR-012, PULL-04):**
- `backend/api/_lib/db.js` exporta `SYNC_LOCK_KEY = 20260923`, única constante importada por push
  (esta tarea) y por pull (plan 10-02) — dos literales distintos habrían dado contención cero
  (Pitfall 3 del research).
- `backend/api/sync/push.js`: `apiKeyRole` decide 401 (sin rol) vs 403 (rol `web`, solo lectura);
  el `SELECT pg_advisory_xact_lock($1)` es el primer elemento del array de `sql.transaction`, antes
  de cualquier `upsertStatement` — el orden importa porque `bump_change_seq()` asigna `change_seq`
  dentro de la misma transacción, antes del commit.
- `backend/api/sync/state.js`: `STATE_SQL` se arma con `SYNCABLE_TABLES.map(...)` en vez de una lista
  de `UNION ALL` escrita a mano (la lista a mano era la causa raíz de PULL-04: le faltaba
  `recorridos`). Handler acepta ambos roles (`sync` y `web` leen state).
- Tests: `push.test.js` gana dos casos sin DB (403 contra `WEB_API_KEY`, 401 contra key inválida) y
  un subtest con DB (`handler con lock: push real -> 200`, ackedIds/serverCursor reales). `state.test.js`
  es nuevo: caso sin DB (`STATE_SQL` contiene cada tabla del spec) y caso con DB (upsert de un
  `recorrido` con `updated_at` en 2100, verifica `lastSyncAt` exacto y `serverCursor >= change_seq`).

## Deviations from Plan

None — plan ejecutado tal cual estaba escrito. Único ajuste operativo: `backend/node_modules` no
estaba instalado en este worktree (`@neondatabase/serverless` faltante); se corrió `npm install`
dentro de `backend/` para poder correr la suite completa — no es un cambio de código, está en
`.gitignore`.

## Verification

- `cd backend && node --test` → 44 pass, 0 fail, 2 skipped (los dos casos que requieren
  `DATABASE_URL`: `push tipado contra Neon` y el caso con DB de `state.test.js`; no hay
  `DATABASE_URL` en este entorno de ejecución — se corren en la compuerta del plan 10-04 según el
  plan).
- `grep -rn "requireApiKey" backend/` → 0 coincidencias.
- Todos los `acceptance_criteria` de ambas tasks verificados por grep, ver comandos en
  `10-01-PLAN.md` (conteos de `apiKeyRole`, `timingSafeEqual`, `SYNC_LOCK_KEY`, posición del lock
  antes de `...outbox.map`, ausencia del literal `20260923` en `push.js`, `SYNCABLE_TABLES` en
  `state.js`, ausencia de `FROM artistas` hardcodeado).

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: backend/api/_lib/auth.js
- FOUND: backend/api/_lib/auth.test.js
- FOUND: backend/.env.example (WEB_API_KEY)
- FOUND: backend/api/_lib/db.js (SYNC_LOCK_KEY)
- FOUND: backend/api/sync/push.js (403 + lock)
- FOUND: backend/api/sync/push.test.js
- FOUND: backend/api/sync/state.js (STATE_SQL desde SYNCABLE_TABLES)
- FOUND: backend/api/sync/state.test.js
- FOUND: commit b3fb5ad (Task 1)
- FOUND: commit 2cbffb3 (Task 2)
