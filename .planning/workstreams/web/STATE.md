---
gsd_state_version: "1.0"
milestone: v1.0
milestone_name: (Web de gestión, lectura)
current_phase: 12
current_phase_name: Web de lectura
current_plan: 12-10
status: executing
stopped_at: "Completed 12-09 (wave 6); next wave 7 (12-10: e2e, ponytail audit, Preview UAT, merge)"
last_updated: "2026-10-08T03:00:00.000Z"
last_activity: 2026-10-06
last_activity_desc: "12-09 completo: Obras y Artistas; falta 12-10"
state_head: 39a4ecb1e32b626bdeca5ed5aed7c5ccea6e1a71
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 19
  completed_plans: 11
  percent: 50
---

# Project State

## Current Position

Milestone: v1.0 Web de gestión (lectura)
Phase: 12 (Web de lectura)
Plan: 2 of 10 complete (12-01 y 12-02 hechos; siguiente 12-03)
Status: Executing Phase 12
Last activity: 2026-10-06 — 12-02 completo (pull todo-o-nada + store + modelo derivado + pill de lectura + leyenda del home)

## Progress

**Phases Complete:** 2/4
**Current Plan:** 12-02

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
- Fase 11 plan 03 (INFRA-01, cerrado, **luego superseded el mismo día — ver nota abajo**): mecanismo (d) elegido originalmente — shims `web/api/sync/{push,pull,state}.js` re-exportando (identidad verificada) los handlers de `backend/api/sync/` (backend/ sin diff), `web/package.json` (`type: module`), `web/vercel.json` (rewrite `/sync/:path*` + `installCommand: npm ci --prefix ../backend`). (b) "functions glob" descartado analíticamente (docs Vercel + vercel/vercel#7591, nunca probado); (c) "mover backend/api/ a la raíz" nunca necesario en ese momento. El spike local de `vercel dev` no pudo producir la evidencia `SMOKE OK`: tanto (d) como (a) (candidato de respaldo) dan `500 FUNCTION_INVOCATION_FAILED` para CUALQUIER función Node local, incluso un handler trivial sin imports — bug de bootstrap de `@vercel/node@16.0.1` (CLI 60.1.3, Node 22.14, Windows). Ruteo/descubrimiento sí se validó para ambos mecanismos (rutas reales → 500, inexistentes → 404, estáticos → 200). Decisión del usuario tras checkpoint: proceder con (d) sin seguir debugueando el bug de tooling local, diferir `SMOKE OK` real al plan 04.
- **Fase 11, mismo día, previo al checkpoint del plan 04:** el usuario cuestionó la separación `backend/`↔`web/` en sí misma ("no entiendo por qué separado... backend y front gestionan la misma bd"). Investigación confirmó que el patrón estándar de Vercel es `api/` colocado en el mismo proyecto que el frontend, sin indirección (shim era la opción atípica). **Decisión revisada: `backend/` se disolvió por completo, todo su contenido se movió a `web/`** (`api/`, `scripts/`, `package.json`, `schema.sql`, `.env.example`, `README.md`) — commit `524da3e`. `web/api/sync/*.js` ahora son los handlers reales, no shims; `installCommand` eliminado (deps locales a `web/`). Ver addendum en `11-03-SUMMARY.md`. ADR-005 (Notion) necesita revisión para reflejar esto.
- Fase 11 plan 04 (INFRA-01 + INFRA-02 contra deploy real, cerrado): Root Directory del proyecto Vercel real cambiada a `web` (usuario, dashboard) — "Include files outside the root directory" quedó DESACTIVADO (ya no hace falta tras el merge a `web/`). Primer Preview real de `ws/web`: `SMOKE OK` (401 sin key, 200 con key y `serverCursor`), `pull`→401, `push` GET→405, todos JSON real. `check-preview-db.sh` → `INFRA-02 OK` contra el deploy real. Producción en vivo (`cingula.vercel.app`) verificada intacta. Bloqueadores resueltos en el camino: (1) Deployment Protection devolvía 302 a login SSO — resuelto con el secreto "Protection Bypass for Automation" (usuario lo generó, agente lo usó solo en memoria para el header, nunca persistido); (2) `WEB_API_KEY` no existía en Preview — generada por el agente (`openssl rand -hex 32`, no es credencial ajena) y agregada vía CLI; (3) **hallazgo operativo importante:** una env var agregada a un entorno con deploy ya activo no llega a la función en runtime hasta hacer un redeploy explícito (`vercel redeploy <url> --non-interactive`) — aplica a cualquier env var futura. Hallazgo diferido al ponytail audit del plan 05: Vercel despliega `*.test.js` de `api/` como funciones reales (no rompe nada, pero es ruido — candidatos: `.vercelignore` o mover tests fuera de `api/`). Ventana de riesgo sigue abierta: no pushear a `main` hasta que el plan 05 mergee `ws/web`.

## Session Continuity

**Last session:** 2026-10-06T23:13:34.406Z

**Stopped At:** Completed 12-02-PLAN.md
**Resume File:** None

## Performance Metrics

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 12 P01 | 45min | 3 tasks | 23 files |
| Phase 12 P02 | 50min | 2 tasks | 19 files |

## Decisions

- [Phase 12]: 12-01 ADR: SPA Vite en web/ servida desde el mismo proyecto Vercel que web/api/ (vercel.json: /sync primero, fallback SPA con exclusiones api/ sync/ assets/, headers de seguridad); A1 y A2 validadas en Preview real
- [Phase 12]: 12-01: todas las dependencias del SPA como devDependencies con versión exacta; la clave de acceso sólo en sessionStorage
- [Phase 12]: 12-02: pull todo-o-nada (reemplazo total del store; relee todo en cada carga hasta que 12-04 agregue refresco incremental)
- [Phase 12]: 12-02: lista blanca USED_COLUMNS en el ingreso al store (H3); audios sólo exponen has_file; el modelo de vista es un grafo con referencias de objeto (no serializable)
- [Phase 12]: 12-02: counts.portales cuenta paths kind=portal aunque no tengan trigger; 12-07 decide si la leyenda filtrada los excluye
