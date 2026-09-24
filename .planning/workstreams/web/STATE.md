---
workstream: web
created: 2026-09-23
---

# Project State

## Current Position

Milestone: v1.0 Web de gestión (lectura)
Phase: Phase 10 (Pull cerrado + Auth dual-key) — contexto listo, pendiente planning
Plan: —
Status: Contexto de Fase 10 capturado, lista para /gsd:plan-phase 10
Last activity: 2026-09-23 — 10-CONTEXT.md creado (watermark → advisory lock, ADR-012)

## Progress
**Phases Complete:** 0/4
**Current Plan:** N/A

## Accumulated Context

- Numeración de fases del workstream web arranca en 10 (app usa 1–5).
- Alcance acotado a lectura: escritura desde la web (ADR-006 etapas 1 y 2) y `staleIds` fuera de este milestone.
- Research acotado: storage de audio (BE-04) y paginación de `GET /sync/pull` (BE-01). No re-investigar Neon/Vercel (ADR-001).
- Cada fase incluye auditoría ponytail.
- Roadmap: 4 fases — 10 (Pull cerrado + Auth dual-key, desbloquea `app` Phase 3), 11 (Infra de deploy mismo proyecto Vercel, spike `vercel dev` obligatorio), 12 (Web de lectura, SPA completa), 13 (Storage de audio + reproducción en la web, desbloquea `app` Phase 2.2). `WEB_API_KEY` backend plegado en Phase 10 (no fase propia); pantalla de acceso (AUTH-02) plegada en Phase 12 junto con el resto de la UI.
- Phase 10 y 11 son paralelizables entre sí; Phase 12 depende de ambas; Phase 13 depende de 10/11 (auth) y de 12 (STOR-04 es una feature de la web ya construida).
- Fase 10: el watermark del research (margen sobre `updated_at`) era inválido — esa columna la pone el cliente. Reemplazado por `pg_advisory_xact_lock` (push exclusivo, pull compartido), registrado en ADR-012 (Notion). Todo escritor futuro (web ADR-006, scripts de datos) tiene que tomar el mismo lock.
- Fase 10: pull en lista plana por `change_seq` (`{changes:[{table,change_seq,payload}], nextCursor, hasMore}`), ruta `/sync/pull`, limit 500/máx 1000, borradas como fila completa. `WEB_API_KEY` de solo lectura en este milestone (push responde 403 a una key web válida).

## Session Continuity
**Stopped At:** Contexto de Fase 10 capturado (`10-CONTEXT.md`, `10-DISCUSSION-LOG.md`), ADR-012 creado en Notion, REQUIREMENTS.md y research corregidos. Pendiente `/gsd:plan-phase 10`.
**Resume File:** .planning/workstreams/web/phases/10-pull-cerrado-auth-dual-key/10-CONTEXT.md
