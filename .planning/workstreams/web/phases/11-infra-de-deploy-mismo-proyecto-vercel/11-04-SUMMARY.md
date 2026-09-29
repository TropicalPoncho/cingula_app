---
phase: 11-infra-de-deploy-mismo-proyecto-vercel
plan: 04
subsystem: infra-deploy
tags: [vercel, preview, deploy, INFRA-01, INFRA-02]

requires:
  - phase: 11-02
    provides: "proyecto Vercel real (cingula, ramas-projects-e2ba61a0) linkeado, INFRA-02 verificado contra env vars"
  - phase: 11-03
    provides: "web/api/sync/{push,pull,state}.js (handlers reales tras el merge backend/ -> web/, ver 11-03-SUMMARY addendum)"
provides:
  - "Root Directory del proyecto Vercel real = web, confirmado ON (sin 'Include files outside the root directory': ya no hace falta tras disolver backend/)"
  - "Primer Preview real de ws/web: SMOKE OK, 401/405 JSON, INFRA-02 OK contra el deploy real"
  - "WEB_API_KEY nueva en Preview (scope ws/web) — no existía, generada por el agente (openssl rand -hex 32, no es credencial ajena)"
  - "Producción en vivo (cingula.vercel.app) verificada intacta post-cambio de Root Directory"
affects: [11-05, 12]

tech-stack:
  added: []
  patterns:
    - "Vercel Deployment Protection (Vercel Authentication) bloquea automatización sin 'Protection Bypass for Automation'; el secreto no sale por env pull/ls, solo por Settings -> Deployment Protection"
    - "Env vars nuevas no llegan a un deploy ya construido: agregar una variable requiere redeploy explicito (npx vercel@latest redeploy <url> --non-interactive) para que la función la vea en runtime"

key-files:
  created: []
  modified: []

key-decisions:
  - "Cambio de Root Directory (web) + toggle 'Include files outside the root directory' quedó DESACTIVADO — a diferencia de lo que el plan 11-03 original preveía (shim), tras el merge backend/ -> web/ (mismo día, antes de este checkpoint) ya no hay imports que crucen la Root Directory, así que ese toggle ya no aplica."
  - "WEB_API_KEY para Preview no existía (solo SYNC_API_KEY). Se generó con openssl rand -hex 32 y se agregó vía CLI (vercel env add --no-sensitive --value=... --git-branch=ws/web) — no es una credencial de un tercero, es una key nueva para este proyecto, así que no aplica la restricción de nunca entrar credenciales ajenas."
  - "La comparación de serverCursor Preview vs Production (evidencia complementaria del ROADMAP) no se pudo completar: SYNC_API_KEY de producción es tipo Secret (Hidden), no legible por vercel env pull/ls por diseño de Vercel. No es un fallo — la evidencia primaria y suficiente para INFRA-02 (comparación de HOST vía check-preview-db.sh) ya dio OK."

requirements-completed: [INFRA-01, INFRA-02]

duration: ~50min (incluye 2 checkpoints humanos: Root Directory + generar Protection Bypass secret)
completed: 2026-09-29
---

# Phase 11 Plan 04: Preview real del proyecto único (Root Directory = web) Summary

**Primer deploy real contra el proyecto Vercel `cingula`: Root Directory cambiada a `web`, Preview de `ws/web` responde `SMOKE OK` (401/405/200 JSON real, no HTML), `INFRA-02 OK` verificado contra el deploy real, y producción en vivo confirmada sin cambios.**

## Performance

- **Duration:** ~50min (2 checkpoints humanos: cambio de Root Directory + generación del Protection Bypass secret)
- **Completed:** 2026-09-29
- **Tasks:** 2/2

## Accomplishments

- Root Directory del proyecto Vercel real (`cingula`, `ramas-projects-e2ba61a0`) cambiada de `backend` a `web`. El toggle "Include files outside the root directory" quedó **desactivado** — ya no hace falta porque el merge `backend/` → `web/` (mismo día, ver `11-03-SUMMARY.md` addendum) eliminó todo import que cruzara la Root Directory.
- Se pusheó `ws/web` (con el merge `backend/`→`web/` incluido) disparando un build Preview real: `web/api/sync/{push,pull,state}.js` se descubren y despliegan como funciones reales, sin indirección.
- Deployment Protection (Vercel Authentication) bloqueaba las requests con `302` a un login SSO — riesgo ya anticipado en `11-02-SUMMARY.md`. Se resolvió generando el "Protection Bypass for Automation" secret (el usuario lo generó en el dashboard; su valor se usó solo para el header `x-vercel-protection-bypass` de la verificación, nunca se escribió en el repo).
- `WEB_API_KEY` no existía en Preview (solo `SYNC_API_KEY`). Se generó una nueva (`openssl rand -hex 32`) y se agregó vía CLI, scopeada a Preview + rama `ws/web`.
- **Hallazgo operativo:** una env var agregada después de que un deploy ya está construido NO llega a esa función en runtime — hace falta un redeploy explícito (`npx vercel@latest redeploy <url> --non-interactive`) para que la tome. Sin este redeploy, el chequeo 2 del smoke daba 401 pese a la key ser correcta.
- `SMOKE OK` completo contra el Preview real: chequeo 1 (401 JSON sin key, ruteo puro) y chequeo 2 (200 JSON con `serverCursor: "3420"` usando la `WEB_API_KEY` nueva). `pull` sin key → 401 JSON; `push` sin key (GET) → 405 JSON.
- `check-preview-db.sh ws/web` → `INFRA-02 OK` contra el deploy real (no solo contra env vars como en 11-02): `production` resuelve a `ep-fancy-waterfall-...`, `preview(ws/web)`/`development` resuelven a `ep-calm-dream-...` (la rama dev nueva de 11-02).
- Producción en vivo (`https://cingula.vercel.app`) verificada sin cambios: `SMOKE OK` (chequeo 1; chequeo 2 salteado porque `SYNC_API_KEY` de producción es Secret, no legible — comportamiento esperado del script, no una falla).

## Task Commits

Este plan no generó commits de código — toda la config vive en el proyecto Vercel (Root Directory, env vars) y en el estado del deploy. Los commits que hicieron posible este Preview (merge `backend/`→`web/`) ya estaban hechos antes del checkpoint de Task 1:
- `524da3e` refactor(11): dissolve backend/ as a separate package, unify into web/
- `42e4bfe` docs(11-03): mark shim mechanism as superseded by backend/ -> web/ merge

**Plan metadata:** (this commit) `docs(11-04): complete real Preview deploy verification plan`

## Files Created/Modified

Ninguno — este plan es 100% verificación contra infraestructura real (Vercel dashboard, Neon, deploy). Ningún archivo del repo se creó o modificó como parte de este plan específico.

## Decisions Made

Ver `key-decisions` en el frontmatter. Resumen:
1. Root Directory = `web`, sin "Include files outside the root directory" (ya no aplica tras el merge).
2. `WEB_API_KEY` nueva generada y agregada para Preview — no existía, necesaria para el chequeo 2 del smoke.
3. Comparación de `serverCursor` Preview vs Production no concluyente por diseño (Secret ilegible), evidencia de host ya es suficiente.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — bloqueante, resuelto] `WEB_API_KEY` no existía en Preview**
- **Encontrado durante:** Task 2, intento de correr el chequeo 2 del smoke.
- **Qué se hizo:** generada con `openssl rand -hex 32`, agregada vía `vercel env add WEB_API_KEY preview --no-sensitive --value=... --git-branch=ws/web`.
- **Por qué no bloqueó con un checkpoint:** el plan 11-02 ya había anotado esto como "pendiente para el plan 04"; generar una key nueva propia del proyecto no es una acción que requiera credenciales de un tercero.

**2. [Hallazgo operativo, no bug de código] Env var nueva no visible hasta redeploy**
- **Encontrado durante:** primer intento del chequeo 2 tras agregar `WEB_API_KEY` — seguía dando 401 con la key correcta.
- **Causa:** Vercel snapshotea las env vars al momento del build/deploy; una variable agregada después no llega a la función corriendo hasta que se redeploya.
- **Fix:** `npx vercel@latest redeploy <preview-url> --non-interactive`. Confirmado: el chequeo 2 pasó inmediatamente después.
- **Nota para plan 05 / futuros deploys:** cualquier env var nueva agregada a un entorno con un deploy ya activo necesita un redeploy explícito, no alcanza con agregarla.

**3. [Hallazgo, registrado para el ponytail audit del plan 05] Archivos `*.test.js` se despliegan como funciones**
- **Encontrado durante:** inspección del build (`npx vercel@latest inspect`) del primer Preview.
- **Qué se encontró:** `api/sync/pull.test`, `api/sync/push.test` (y probablemente los de `_lib`) aparecen listados como funciones Lambda desplegadas junto a los handlers reales — Vercel descubre CUALQUIER `.js` en `api/` como función, sin distinguir tests.
- **Impacto:** no rompe nada (los tests no exportan `default` compatible con handler HTTP, así que invocarlos fallaría, pero consumen build time/slots de función y quedan listados en el output del build).
- **No se resolvió en este plan** (fuera de scope — es infraestructura de ruteo, no verificación de deploy). Queda anotado explícitamente para la auditoría ponytail del plan 11-05: candidatos son excluir `*.test.js` vía `.vercelignore` o mover los tests fuera de `api/`.

---

**Total deviations:** 2 auto-resueltas (Rule 3) + 1 hallazgo diferido a 11-05 (ponytail audit)
**Impact on plan:** Ninguno sobre el resultado final — todas las verificaciones pedidas por el plan (`SMOKE OK` Preview, INFRA-02 OK real, producción intacta) se completaron.

## Issues Encountered

Ver Deviations arriba.

## User Setup Required

Completado durante este plan (no queda pendiente):
- Root Directory = `web` en Vercel Dashboard (usuario).
- "Include files outside the root directory" desactivado (usuario, correcto para el estado post-merge).
- "Protection Bypass for Automation" generado (usuario) — el agente lo usó solo para verificación, nunca lo persistió.

## Next Phase Readiness

- Plan 05 (cierre de fase: auditoría ponytail + merge a `main`) puede proceder. Insumos que deja este plan:
  - Preview de `ws/web` verificado end-to-end (ruteo + base de datos aislada).
  - Ventana de riesgo (Root Directory ya cambiada, `main` todavía sin los shims/merge de `web/`) sigue abierta — **no pushear a `main` hasta que el plan 05 mergee `ws/web`**.
  - Hallazgo pendiente para el ponytail audit: `*.test.js` desplegándose como funciones (ver Deviations #3).
  - Pendiente para Notion/ADR-005 (acumulado con 11-02 y 11-03): registrar el bypass secret, el WEB_API_KEY nuevo, y el hallazgo de env-vars-necesitan-redeploy.

## Known Stubs

Ninguno.

---
*Phase: 11-infra-de-deploy-mismo-proyecto-vercel*
*Completed: 2026-09-29*

## Self-Check: PASSED

- VERIFIED: Root Directory = web (confirmado por el usuario)
- VERIFIED: Preview `ws/web` — `SMOKE OK` con ambos chequeos (401 sin key, 200 con key y serverCursor)
- VERIFIED: `pull` sin key -> 401 JSON, `push` sin key (GET) -> 405 JSON
- VERIFIED: `check-preview-db.sh ws/web` -> `INFRA-02 OK` contra el deploy real
- VERIFIED: producción (`cingula.vercel.app`) -> `SMOKE OK` (chequeo 1; chequeo 2 salteado por diseño, Secret ilegible)
- VERIFIED: `git status --porcelain` limpio (ningún `.env` bajado quedó en el repo)
