---
phase: 10-pull-cerrado-auth-dual-key
plan: 03
subsystem: docs (Notion ERS/ADR + research)
tags: [notion, contract, adr, docs]
dependency-graph:
  requires: []
  provides:
    - "Contrato GET /sync/pull publicado en Notion (PULL-05)"
    - "research anotado inline: watermark de tiempo reemplazado por ADR-012 (D-02.3)"
  affects:
    - "10-04 (Task 1 checkG compara contrato Notion vs pull.js; Task 2 pide revisión humana del contrato)"
    - "app Fase 3 (programa contra este contrato sin leer el código backend)"
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - .planning/workstreams/web/research/SUMMARY.md
    - .planning/workstreams/web/research/ARCHITECTURE.md
    - .planning/workstreams/web/research/PITFALLS.md
decisions:
  - "ADR-007 y ADR-012 ya estaban completos en Notion (agregados en el discuss-phase de esta fase, 2026-09-23) — Task 1 solo necesitó publicar la sección GET /sync/pull en la ERS, verificado por fetch antes de tocar nada"
  - "Task 1 requería herramientas Notion no disponibles para el subagente gsd-executor (solo tiene Read/Write/Edit/Bash/Grep/Glob); lo ejecutó el orquestador directamente, que sí tenía el MCP de Notion cargado en la sesión"
requirements-completed: [PULL-05]
metrics:
  duration: "~10 min (Task 1, tras conectar Notion) + ~20 min (Task 2, sesión previa)"
  completed: "2026-09-26"
---

# Phase 10 Plan 03: Contrato de pull en Notion + notas de reemplazo en research Summary

Contrato de `GET /sync/pull` publicado en la página "ERS · Backend — protocolo de sync" de Notion,
con los mismos defaults, mensajes de error y forma de respuesta que implementa `backend/api/sync/pull.js`
(10-02). ADR-007 y ADR-012 ya cumplían los criterios de aceptación sin cambios adicionales.

## What Was Built

**Task 1 — Contrato en Notion (PULL-05, D-13):**
- Página: [ERS · Backend — protocolo de sync](https://app.notion.com/p/3e43d6cb9a58815dac21c85036b6c45f)
  — agregada sección `### GET /sync/pull` bajo "Contrato vigente" (ruta, auth, query params/errores,
  forma de la respuesta 200, borradas, orden al aplicar, garantía de no-salto, cursor válido, alcance
  de keys). Fila de "Estado actual" para `GET /sync/pull` actualizada de `❌ no existe` a
  `✅ implementado`. Nota agregada a `GET /sync/state` sobre el fix de `recorridos` (BE-05).
  Contenido verbatim de `10-03-PLAN.md` líneas 76-102, cruzado contra `backend/api/sync/pull.js` y
  `backend/api/_lib/auth.js` antes de escribir — coincide exacto (defaults 500/1000, strings de error,
  forma `{changes, nextCursor, hasMore}`).
- Página: [Cíngula App — ADRs](https://app.notion.com/p/3e43d6cb9a5881749a19d3439a68a085) —
  **sin cambios**: ADR-007 ya tenía la actualización "Fase 10 (web): WEB_API_KEY queda acotada a
  lectura... POST /sync/push la rechaza con 403" (agregada en el discuss-phase de la fase); ADR-012
  ya tenía los 5 elementos de D-02.1 (contexto, decisión, alternativas incluyendo `updated_at`,
  consecuencia/techo "todo escritor nuevo tiene que tomar el mismo lock", estado Aceptada). Verificado
  por fetch antes de tocar nada — no había nada que completar.

**Task 2 — Notas de reemplazo inline en research (D-02.3):** ya ejecutada y comiteada en una sesión
previa (commit `88ada0a`) — verificado que las 3 notas "Reemplazado por ADR-012" existen en
`SUMMARY.md`/`ARCHITECTURE.md`/`PITFALLS.md` según lo pedía el plan. No requirió trabajo adicional.

## Deviations from Plan

- El plan asumía que el executor del plan tendría acceso a herramientas Notion (vía skill
  `gestion-notion-rama` o MCP directo). El agente `gsd-executor` no tiene esas tools en su lista
  (solo Read/Write/Edit/Bash/Grep/Glob) — reportó correctamente un auth gate en dos intentos (antes y
  después de conectar Notion), sin escribir el contrato en un archivo del repo como sustituto, tal
  como pedía el plan. El orquestador (con el MCP de Notion cargado en su propia sesión) ejecutó
  Task 1 directamente una vez confirmado el acceso.
- ADR-007 y ADR-012 resultaron ya completos (trabajo de un discuss-phase anterior), así que el trabajo
  real de Task 1 fue más chico de lo que el plan anticipaba: solo la sección de la ERS.

## Verification

Fetch de "ERS · Backend — protocolo de sync" contiene todos los strings de acceptance_criteria:
`GET /sync/pull`, `nextCursor`, `hasMore`, `cursor must be an integer >= 0`,
`limit must be an integer between 1 and 1000`, `API key is read-only`, `500`, `1000`, `deleted_at`,
y la regla del cursor válido con `serverCursor` + "informativo". Fetch de ADR-007 contiene
"solo lectura" y "403". Fetch de ADR-012 contiene `pg_advisory_xact_lock`, `updated_at` (en
alternativas) y la frase del techo sobre "todo escritor".

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: sección GET /sync/pull en Notion (fetch verificado)
- FOUND: fila Estado actual actualizada
- FOUND: ADR-007 "solo lectura" + "403" (ya existía)
- FOUND: ADR-012 5 elementos (ya existía)
- FOUND: commit 88ada0a (Task 2, sesión previa)
