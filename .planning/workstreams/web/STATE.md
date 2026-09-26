---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_plan: 11-02
status: executing
stopped_at: Completed 11-01-PLAN.md
last_updated: "2026-09-26T03:02:41.165Z"
last_activity: 2026-09-26
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 9
  completed_plans: 5
---

# Project State

## Current Position

Milestone: v1.0 Web de gestión (lectura)
Phase: 11
Plan: 1 of 5 complete
Status: In progress
Last activity: 2026-09-26

## Progress

**Phases Complete:** 1/4
**Current Plan:** 11-02

## Accumulated Context

- Numeración de fases del workstream web arranca en 10 (app usa 1–5).
- Alcance acotado a lectura: escritura desde la web (ADR-006 etapas 1 y 2) y `staleIds` fuera de este milestone.
- Research acotado: storage de audio (BE-04) y paginación de `GET /sync/pull` (BE-01). No re-investigar Neon/Vercel (ADR-001).
- Cada fase incluye auditoría ponytail.
- Roadmap: 4 fases — 10 (Pull cerrado + Auth dual-key, desbloquea `app` Phase 3), 11 (Infra de deploy mismo proyecto Vercel, spike `vercel dev` obligatorio), 12 (Web de lectura, SPA completa), 13 (Storage de audio + reproducción en la web, desbloquea `app` Phase 2.2). `WEB_API_KEY` backend plegado en Phase 10 (no fase propia); pantalla de acceso (AUTH-02) plegada en Phase 12 junto con el resto de la UI.
- Phase 10 y 11 son paralelizables entre sí; Phase 12 depende de ambas; Phase 13 depende de 10/11 (auth) y de 12 (STOR-04 es una feature de la web ya construida).
- Fase 10: el watermark del research (margen sobre `updated_at`) era inválido — esa columna la pone el cliente. Reemplazado por `pg_advisory_xact_lock` (push exclusivo, pull compartido), registrado en ADR-012 (Notion). Todo escritor futuro (web ADR-006, scripts de datos) tiene que tomar el mismo lock.
- Fase 10: pull en lista plana por `change_seq` (`{changes:[{table,change_seq,payload}], nextCursor, hasMore}`), ruta `/sync/pull`, limit 500/máx 1000, borradas como fila completa. `WEB_API_KEY` de solo lectura en este milestone (push responde 403 a una key web válida).
- Fase 11 plan 01: `backend/scripts/smoke-preview.sh` creado (GET-only, distingue JSON de función vs HTML de Vercel); `.github/workflows/` no existe hoy, ningún CI depende de la ubicación de `backend/api/`; `web/` limpio de restos de Flutter (borrado total, sin conservar favicon).

## Session Continuity

**Stopped At:** Completed 11-01-PLAN.md
**Resume File:** .planning/workstreams/web/phases/11-infra-de-deploy-mismo-proyecto-vercel/11-02-PLAN.md
