---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_plan: 11-02
status: executing
stopped_at: Completed 11-02-PLAN.md
last_updated: "2026-09-28T23:07:04.279Z"
last_activity: 2026-09-28
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 9
  completed_plans: 6
---

# Project State

## Current Position

Milestone: v1.0 Web de gestión (lectura)
Phase: 11
Plan: 2 of 5 complete
Status: Ready to execute
Last activity: 2026-09-28

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
- Fase 11 plan 02 (INFRA-02, cerrado): la integración Neon Marketplace conectada al proyecto (`cingula-back`) no expone un toggle de "create a database branch for deployment" (solo "Update Name" en Settings) — se resolvió con Rama A: `DATABASE_URL` manual, scope Preview (branch-specific `ws/web`) + Development, apuntando a una rama Neon nueva (la rama `dev` de la Fase 10 había sido borrada). Verificado por host con `backend/scripts/check-preview-db.sh`: `INFRA-02 OK`. Gotchas para cualquier variable scoped-by-git-branch futura: (1) la rama tiene que existir en el remoto de GitHub antes de que `--git-branch` resuelva algo; (2) `vercel env add` sin `--no-sensitive` guarda la variable como Secret, y `vercel env pull` no puede leerla — imprime `[SENSITIVE]`, que el script interpretaría como un host real distinto de producción (falso OK silencioso). Deployment Protection ("Vercel Authentication") está activo en el proyecto pero no se confirmó si está scoped solo a Preview — riesgo para el smoke test del plan 04 (puede recibir HTML de login en vez de JSON), no bloqueante para este plan.
- Fase 11 plan 03 (BLOQUEADO en Task 2): Task 1 completa y commiteada (`68fe01c`) — shims `web/api/sync/{push,pull,state}.js` re-exportando los handlers de `backend/api/sync/` (identidad verificada, backend/ sin diff), `web/package.json` (`type: module`), `web/vercel.json` (rewrite `/sync/:path*` + `installCommand: npm ci --prefix ../backend`). Task 2 (spike `vercel dev`) no pudo decidir el mecanismo: tanto (d) `web/api/` con Root Directory=`web` como (a) `api/` de la raíz con Root Directory=raíz dan el MISMO resultado — `vercel dev` (CLI 60.1.3, `@vercel/node` 16.0.1, Node 22.14, Windows) responde `500 FUNCTION_INVOCATION_FAILED` para CUALQUIER función Node, incluso un handler trivial sin imports (`api/hello.js` con solo `res.status(200).json({ok:true})`) — confirmado con `--debug`: el proxy del CLI hacia el dev-server del builder da `Error: connect ETIMEDOUT 127.0.0.1:<puerto>` ~300ms después de spawnear el subproceso (pid distinto cada vez), es decir el subproceso del builder crashea al arrancar, no un timeout real. Networking de Node en la máquina funciona bien (servidor HTTP manual de prueba respondió sin problema). Lo que SÍ se validó para ambos mecanismos: la ruta/descubrimiento funciona — `/sync/pull`, `/sync/push`, `/sync/state` (directo y vía rewrite) dan 500 (encontrados e invocados) mientras que rutas inexistentes dan 404 (discriminación correcta); `spike.html` sirve 200 `text/html` desde la misma Root Directory en ambos casos. Es decir: el bug es de invocación local del builder `@vercel/node`, no del mecanismo de ruteo — pero bloquea completar la evidencia `SMOKE OK` que el plan exige antes de decidir. Limpieza completa: ambos proyectos descartables (`cingula-phase11-spike`, `cingula-phase11-spike-a`) borrados, todo archivo de spike (`web/spike.html`, `web/.vercel/`, `web/.gitignore` generado por el link, `api/`, `package.json`, `vercel.json`, `.vercelignore`, `.env.local` de la raíz) eliminado, `.vercel/` real (proyecto `cingula`) restaurado sin tocar. `git status --porcelain` limpio. Decisión pendiente del usuario: (1) validar el mecanismo directamente contra un Preview real (plan 04) en vez de local, dado que el bug parece específico del entorno local de `vercel dev` en Windows; o (2) investigar el bug de `@vercel/node` local (posible incompatibilidad con Node 22 en Windows) antes de seguir. Ninguna opción es una decisión de (b)/(c) — sigue sin evaluarse arquitectura nueva, es un problema de la herramienta de dev local.

## Session Continuity

**Stopped At:** 11-03-PLAN.md Task 1 complete (commit `68fe01c`), Task 2 blocked at CHECKPOINT — ver Accumulated Context
**Resume File:** .planning/workstreams/web/phases/11-infra-de-deploy-mismo-proyecto-vercel/11-03-PLAN.md (Task 2)
