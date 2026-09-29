---
phase: 10-pull-cerrado-auth-dual-key
plan: 02
subsystem: backend/api (sync pull)
tags: [pull, advisory-lock, sync, auth]
dependency-graph:
  requires:
    - "apiKeyRole(request) -> 'sync' | 'web' | null (10-01, backend/api/_lib/auth.js)"
    - "SYNC_LOCK_KEY (10-01, backend/api/_lib/db.js)"
  provides:
    - "GET /sync/pull: lista plana {changes:[{table,change_seq,payload}], nextCursor, hasMore}"
  affects:
    - "app Fase 3 (pull en el celular) — puede empezar a programar contra este contrato"
    - "web Fase 12 (web de lectura) — mismo endpoint"
tech-stack:
  added: []
  patterns:
    - "SQL UNION ALL generado desde TABLE_SPEC (una tabla nueva del spec entra al pull sin tocar pull.js)"
    - "advisory lock compartido como primera sentencia de sql.transaction con isolationLevel ReadCommitted (D-01/ADR-012): el snapshot se fija después del lock, así un pull nunca lee por encima de un push con change_seq asignado y sin commit"
    - "limit+1 filas internas para derivar hasMore sin un COUNT aparte"
key-files:
  created:
    - backend/api/sync/pull.js
    - backend/api/sync/pull.test.js
  modified:
    - backend/README.md
decisions: []
metrics:
  duration: "~20 min"
  completed: "2026-09-24"
---

# Phase 10 Plan 02: GET /sync/pull (lock compartido + payload del spec) Summary

`GET /sync/pull` — lista plana ordenada por `change_seq` global, generada por `UNION ALL` sobre las
7 tablas de `TABLE_SPEC`, protegida por `pg_advisory_xact_lock_shared` para que nunca lea por
encima de un push con seqs asignados y sin commit.

## What Was Built

**Task 1 — `pull.js` + tests PULL-01/02 (AUTH-01, PULL-01, PULL-02):** `backend/api/sync/pull.js`
arma `PULL_SQL` a partir de `SYNCABLE_TABLES`/`TABLE_SPEC` (ninguna columna escrita a mano):
un `SELECT` por tabla con `WHERE change_seq > $1 ORDER BY change_seq LIMIT $2` (usa el índice
`<tabla>_change_seq_idx`), unidos y re-ordenados globalmente. El handler valida `cursor` (entero
>= 0, tope `MAX_BIGINT`) y `limit` (entero 1..1000) antes de tocar la DB, acepta ambos roles
(`sync`/`web`, D-09), y pide `limit + 1` filas para derivar `hasMore` sin un `COUNT` aparte.
`pull.test.js` cubre 405/401/400 sin DB y, con DB, paginación completa con `limit=1` hasta
`hasMore=false` (recorrido + 2 audios, uno borrado), `change_seq`/`nextCursor` como string
estrictamente crecientes, columnas del payload igual a `TABLE_SPEC[table].columns`, y acceso con
`WEB_API_KEY`. `backend/README.md` documenta `/sync/pull` y `WEB_API_KEY`.

**Task 2 — test de integración PULL-03 (PULL-03):** agrega a `pull.test.js` el caso que abre una
transacción real con `Pool` (WebSocket, sin agregar la dependencia `ws` — Node 22 trae `WebSocket`
global), toma `pg_advisory_xact_lock` exclusivo, inserta una fila y la deja sin commitear; verifica
que un pull concurrente (`SELECT pg_advisory_xact_lock_shared`) no resuelve en 3 segundos
(`assert.equal(settled, false, ...)`, prueba el bloqueo real, no solo el resultado final), y que
tras el `COMMIT` el pull resuelve 200 con esa fila incluida.

## Deviations from Plan

None — plan ejecutado tal cual estaba escrito. Único ajuste de proceso: sin `DATABASE_URL` en este
entorno de ejecución, los 5 tests con DB (PULL-01/02, WEB_API_KEY, PULL-03) quedaron salteados
(verde) — su corrida real contra una rama Neon dev, incluida la prueba de regresión de PULL-03 con
el lock comentado, queda para la compuerta humana del plan 10-04, tal como preveía el plan.

## Verification

- `cd backend && node --test api/sync/pull.test.js` → 4 pass, 0 fail, 3 skipped (sin DATABASE_URL).
- `cd backend && node --test` (suite completa) → 48 pass, 0 fail, 5 skipped.
- Todos los `acceptance_criteria` de ambas tasks verificados por grep (ver comandos en
  `10-02-PLAN.md`): `pg_advisory_xact_lock_shared($1)` y `isolationLevel: 'ReadCommitted'` presentes
  una vez cada uno en `pull.js`; `SYNC_LOCK_KEY` importado y usado (2 matches), literal `20260923`
  ausente; cero columnas hardcodeadas (`storage_key`/`recorrido_uuid`/`radius_meters`); cero
  `entity_prev` en `pull.js`; `/sync/pull` documentado en README; en `pull.test.js`: `Pool` importado,
  `pg_advisory_xact_lock($1)` con `SYNC_LOCK_KEY`, `settled, false` presente (prueba el bloqueo, no
  solo el resultado), `COMMIT` presente; `"ws"` ausente de `backend/package.json`.
- `grep -rn "pg_advisory_xact_lock" backend/api --include=*.js` → push.js (exclusivo), pull.js
  (shared), pull.test.js (exclusivo, simula el push abierto); todos con `SYNC_LOCK_KEY`.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: backend/api/sync/pull.js
- FOUND: backend/api/sync/pull.test.js
- FOUND: backend/README.md (/sync/pull, WEB_API_KEY)
- FOUND: commit 6e7d642 (Task 1)
- FOUND: commit 9c5ba0d (Task 2)
