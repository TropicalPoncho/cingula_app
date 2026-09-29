---
phase: 10-pull-cerrado-auth-dual-key
plan: 04
subsystem: backend/api (audit + validation close-out)
tags: [ponytail, audit, neon, validation, gate]
dependency-graph:
  requires:
    - "apiKeyRole, SYNC_LOCK_KEY (10-01)"
    - "GET /sync/pull (10-02)"
    - "Contrato Notion (10-03)"
  provides:
    - "10-VALIDATION.md cerrado (nyquist_compliant: true)"
    - "Auditoría ponytail documentada (checks A-I, cero código borrado — todo limpio)"
  affects:
    - "Cierre de Phase 10 — desbloquea Phase 11/12/13 y app Fase 3"
tech-stack:
  added: []
  patterns: []
key-files:
  created:
    - .planning/workstreams/web/phases/10-pull-cerrado-auth-dual-key/10-04-SUMMARY.md
  modified:
    - .planning/workstreams/web/phases/10-pull-cerrado-auth-dual-key/10-VALIDATION.md
decisions: []
requirements-completed: [PULL-01, PULL-02, PULL-03, PULL-04, PULL-05, AUTH-01]
metrics:
  duration: "~15 min (Task 3, tras compuerta humana de una sesión previa)"
  completed: "2026-09-25"
---

# Phase 10 Plan 04: Auditoría ponytail + compuerta Neon dev + cierre de validación Summary

Auditoría ponytail de todo el código nuevo de la fase (auth dual-key, advisory lock, pull) sin
hallazgos — código ya limpio, cero borrado necesario. Suite completa corrida contra una rama Neon dev
real (58/58, cero salteados, PULL-03 en verde) confirma que el test de concurrencia que protege contra
pérdida silenciosa de datos corre de verdad, no solo se saltea. 10-VALIDATION.md cerrado con la tabla
de verificación real y las seis requirements de la fase completas.

## What Was Built

**Task 1 — Auditoría ponytail (checks A-I):** aplicada sobre `backend/api/_lib/auth.js`,
`backend/api/_lib/db.js`, `backend/api/sync/push.js`, `backend/api/sync/pull.js`,
`backend/api/sync/state.js` (diff contra `4c892c7`, todo lo agregado en 10-01/10-02). Resultado: los 9
checks pasaron limpios, sin hallazgos:

- **A. Lock único** — `SYNC_LOCK_KEY = 20260923` solo en `db.js`; exactamente 2 sentencias
  `pg_advisory_xact_lock`/`pg_advisory_xact_lock_shared` en push.js/pull.js, ambas usando la constante
  importada, lock como primer elemento del array de `sql.transaction` en push.js.
- **B. Aislamiento** — `isolationLevel: 'ReadCommitted'` solo en pull.js; cero
  `RepeatableRead`/`Serializable` en todo `backend/`.
- **C. Sin listas duplicadas** — 0 coincidencias de `storage_key`/`radius_meters`/`recorrido_uuid`
  hardcodeadas en pull.js/state.js; ambos generan su SQL desde `SYNCABLE_TABLES`/`TABLE_SPEC`.
- **D. Dead code** — `requireApiKey` ausente de todo `backend/` (reemplazado limpio en 10-01, sin
  alias muerto); `STATE_SQL` exportado solo para su test (aceptable, documentado en 10-01-SUMMARY);
  `pull.js` no exporta nada más que `default`.
- **E. Dependencias** — `backend/package.json` con 1 dependency (`@neondatabase/serverless`), 0
  devDependencies; `ws` no se agregó (10-02-SUMMARY confirma que Node 22 trae `WebSocket` global).
- **F. Abstracciones** — sin helpers de un solo uso; `parseQuery` en pull.js se queda (dos params con
  reglas propias, justifica su propia función).
- **G. Contrato vs código** — sección `GET /sync/pull` en Notion (publicada en 10-03) coincide exacto
  con pull.js: defaults 500/1000, strings de error, forma `{changes, nextCursor, hasMore}`.
- **H. Comentarios `ponytail:`** — presentes en `db.js` (techo: todo escritor toma el lock),
  `push.js` (el orden es la garantía) y `pull.js` (READ COMMITTED), cada uno documentando su techo.
- **I. Suite** — `cd backend && node --test` verde antes y después de la auditoría, sin cambios de
  código (el diff esperado era negativo o cero, y resultó cero).

**Task 2 — Compuerta humana (Neon dev + contrato):** el usuario corrió
`cd backend && node --test` contra su rama Neon dev y reportó
`tests 58, suites 0, pass 58, fail 0, cancelled 0, skipped 0, todo 0`. Cero salteados confirma que
`PULL-03: pull concurrente espera al push abierto y no saltea sus filas` corrió de verdad contra
Postgres real (no en verde por ausencia de `DATABASE_URL`, como en las corridas locales de 10-01/10-02
que salteaban 2 y 5 tests respectivamente). El usuario también confirmó en el chat que la sección
`GET /sync/pull` de "ERS · Backend — protocolo de sync" en Notion es suficiente para que `app` Fase 3
programe sin leer el código backend.

**Task 3 — Cierre de 10-VALIDATION.md:** frontmatter actualizado (`status: complete`,
`nyquist_compliant: true`, `wave_0_complete: true`); tabla "Per-Task Verification Map" reemplazada por
las filas reales (10-01-01, 10-01-02, 10-02-01, 10-02-02, 10-03-01, 10-04-01), todas en `✅ green` con
el resultado de la corrida Neon dev citado debajo de la tabla; los tres ítems de "Wave 0 Requirements"
marcados `[x]`; los seis ítems de "Validation Sign-Off" marcados `[x]` con
`**Approval:** approved 2026-09-25`.

## Deviations from Plan

None — plan ejecutado tal cual estaba escrito. La auditoría ponytail (Task 1) no encontró nada para
borrar; los 9 checks se corrieron de verdad (comandos y resultados documentados arriba), no es un
"no encontré nada" sin verificar.

## Verification

- `cd backend && node --test` (sin `DATABASE_URL`, este entorno) → 53 tests, 48 pass, 0 fail, 5
  skipped (los mismos casos con DB que 10-02, sin cambios de código en esta plan).
- Corrida del usuario contra Neon dev (Task 2, compuerta): `tests 58, pass 58, fail 0, skipped 0`.
- Acceptance criteria de Task 3 verificados por grep contra `10-VALIDATION.md`:
  `nyquist_compliant: true` (1 match), `wave_0_complete: true` (1 match), `⬜ pending` (0 matches tras
  corregir la línea de leyenda que usaba el mismo emoji), `- [ ]` (0 matches), las seis requirements
  (PULL-01/02/03/04/05, AUTH-01) presentes en la tabla, `Approval:** approved` (1 match).
- Acceptance criteria de Task 1 verificados por grep contra el código (ver comandos en 10-04-PLAN.md):
  todos pasaron sin necesidad de tocar código.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: .planning/workstreams/web/phases/10-pull-cerrado-auth-dual-key/10-VALIDATION.md (nyquist_compliant: true, wave_0_complete: true, Approval: approved 2026-09-25)
- FOUND: commit ac495d3 (Task 3, cierre de 10-VALIDATION.md)
