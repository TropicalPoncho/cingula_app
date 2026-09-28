---
phase: 11-infra-de-deploy-mismo-proyecto-vercel
plan: 03
subsystem: infra-deploy
tags: [vercel, esm, routing, INFRA-01]

requires:
  - phase: 11-01
    provides: "backend/scripts/smoke-preview.sh, web/ limpio de restos de Flutter"
  - phase: 11-02
    provides: "proyecto Vercel real (cingula, ramas-projects-e2ba61a0) linkeado en .vercel/, INFRA-02 verificado"
provides:
  - "web/api/sync/{push,pull,state}.js: shims ESM que re-exportan (identidad verificada) los handlers reales de backend/api/sync/ — backend/ no se mueve ni cambia (ADR-005)"
  - "web/vercel.json: rewrite /sync/:path* -> /api/sync/:path* + installCommand npm ci --prefix ../backend"
  - "web/package.json: type module para que los shims ESM carguen"
  - "backend/README.md: documenta el mecanismo (d), dev local, y el flujo de deploy (smoke-preview.sh + check-preview-db.sh)"
  - "Mecanismo (b) descartado analíticamente (docs Vercel + vercel/vercel#7591); (c) nunca intentado, per regla de parada del plan"
affects: [11-04, 11-05, 12]

tech-stack:
  added: []
  patterns:
    - "Shim ESM de una línea (export { default } from '<ruta-relativa>') para exponer un handler fuera de la Root Directory del proyecto Vercel sin moverlo ni duplicarlo"

key-files:
  created:
    - web/api/sync/state.js
    - web/api/sync/push.js
    - web/api/sync/pull.js
    - web/package.json
    - web/vercel.json
  modified:
    - backend/README.md

key-decisions:
  - "Mecanismo elegido: (d) shims en web/api/sync/ con Root Directory del proyecto Vercel = web. Empataba en 'archivos movidos' (cero) con (a) (shims en /api/ de la raíz); (d) gana porque la raíz del repo ES la app Flutter (lib/, android/, ios/, pubspec.yaml) y (a) obliga a mantener un .vercelignore para todo ese árbol, mientras que (d) lo evita estructuralmente y web/ ya es la futura casa de la SPA (Fase 12)."
  - "(b) 'functions glob apuntando a backend/api/**' descartado sin probarlo: Vercel solo descubre funciones dentro de <Root Directory>/api (docs oficiales + respuesta de un maintainer en vercel/vercel#7591 — functions solo configura funciones YA descubiertas, no las descubre)."
  - "(c) 'mover backend/api/ a la raíz' nunca intentado: rompe la autocontención de backend/ (ADR-005 — su package.json, tests, .env.example, README), y el plan reserva esa decisión para el usuario si tanto (d) como (a) fallaran. No aplica aquí: (d) y (a) no fallaron por el mecanismo, fallaron por una herramienta local rota (ver Deviations)."
  - "La evidencia SMOKE OK / 401-405 JSON contra vercel dev queda diferida al Preview real de la Fase 11 Plan 04 — el spike local no pudo producirla por un bug de @vercel/node ajeno al mecanismo elegido (ver Deviations). El README documenta esto explícitamente para que nadie confunda la ausencia de smoke local con un mecanismo sin validar."

requirements-completed: [INFRA-01]

duration: ~1h 40min
completed: 2026-09-28
---

# Phase 11 Plan 03: Ruteo /sync/* vía shims web/api/ hacia backend/ Summary

**`web/api/sync/{push,pull,state}.js` re-exportan (identidad verificada) los handlers de `backend/api/sync/` sin mover ni duplicar código; `web/vercel.json` fija el rewrite `/sync/:path*` y el install de deps de `backend/` — mecanismo (d) elegido, (b) descartado analíticamente, (c) nunca necesario.**

## Performance

- **Duration:** ~1h 40min (incluye spike de `vercel dev`, debugging de un bug de tooling, y una pausa de checkpoint humano)
- **Completed:** 2026-09-28
- **Tasks:** 2/2
- **Files modified:** 6 (5 creados en `web/`, 1 modificado en `backend/`)

## Accomplishments

- Ruteo `/sync/*` → `backend/api/sync/*` resuelto sin mover `backend/` ni tocar el proyecto Vercel real: 3 shims ESM de una línea cada uno, identidad de handler verificada con `import()` + comparación de referencia de función (no solo de comportamiento).
- `web/vercel.json` fija de una vez el `installCommand: npm ci --prefix ../backend`, evitando que el deploy real (Root Directory = `web`) rompa en runtime por no tener `@neondatabase/serverless` instalado — riesgo explícito que el plan pedía anticipar.
- Mecanismo (b) queda descartado con su fuente exacta (docs de Vercel + `vercel/vercel#7591`) sin gastar tiempo probándolo — no es viable estructuralmente.
- El spike de `vercel dev` (Task 2) no pudo producir la evidencia `SMOKE OK` que el plan pedía, pero sí validó lo que importaba: el ruteo/descubrimiento de Vercel encuentra la función correcta y discrimina rutas inexistentes, para AMBOS candidatos (d) y (a) — la falla real fue un bug de invocación local de `@vercel/node`, documentado en detalle abajo y en el README para que nadie lo confunda con un problema del mecanismo elegido.
- `backend/README.md` reescrito: describe el mecanismo (d), el flujo de dev local, y agrega una sección "Deploy" nueva con el checklist pre-merge (`smoke-preview.sh` + `check-preview-db.sh`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Shims de re-export + config en `web/` (candidato d)** - `68fe01c` (feat)
2. **Task 2: Spike `vercel dev` en proyecto descartable + README** - `85bdd07` (docs)

Commit intermedio de checkpoint (no forma parte de una task, documenta el bloqueo mientras se esperaba la decisión del usuario):
- `a3ec05d` (docs) - registro del bloqueo de tooling en STATE.md, revertido en sustancia por esta misma resolución (el bloqueo se cerró con la decisión "Opción 1" del usuario).

**Plan metadata:** (this commit) `docs(11-03): complete plan`

## Files Created/Modified

- `web/api/sync/state.js` - shim: `export { default } from '../../../backend/api/sync/state.js'` + comentario `ponytail:` explicando el porqué y el techo (una función nueva en `backend/api/sync` necesita un shim nuevo acá)
- `web/api/sync/push.js`, `web/api/sync/pull.js` - shims idénticos, una línea cada uno
- `web/package.json` - `{"private": true, "type": "module"}`, sin `dependencies` (las deps de runtime son las de `backend/`)
- `web/vercel.json` - rewrite `/sync/:path* -> /api/sync/:path*` (mismo texto que `backend/vercel.json`, que NO se borra en este plan) + `installCommand: npm ci --prefix ../backend`
- `backend/README.md` - sección "Dev local" reescrita para el mecanismo (d); sección "Deploy" nueva (smoke + check-preview-db antes de mergear a `main`); "Setup" y "Test" intactas

## Decisions Made

Ver `key-decisions` en el frontmatter — resumen:
1. Mecanismo (d) elegido sobre (a) por regla de desempate del plan (raíz del repo es la app Flutter; `web/` ya es la futura casa de la SPA).
2. (b) descartado analíticamente, nunca probado.
3. (c) nunca necesario — no aplica la condición que lo dispara.
4. La evidencia `SMOKE OK` local queda diferida al Preview real de la Fase 11 Plan 04, documentado explícitamente en el README y en este SUMMARY para no generar una falsa sensación de "sin validar".

## Deviations from Plan

### Auto-fixed Issues

Ninguno de Rule 1/2/3 en el sentido estricto — la desviación real de este plan es de otra naturaleza (documentada abajo como hallazgo, no como fix), porque no había ningún bug de código propio que arreglar: el bug está en la herramienta `@vercel/node`/`vercel dev`, fuera del scope de este repo.

**1. [Hallazgo de entorno, no un bug de código] `vercel dev` local no puede invocar NINGUNA función Node, para ningún mecanismo**
- **Encontrado durante:** Task 2, spike de `vercel dev` para decidir entre (d) y (a)
- **Qué se encontró:** Probé (d) (shims en `web/api/`, Root Directory=`web`, proyecto descartable `cingula-phase11-spike`) contra un proyecto Vercel descartable: `/sync/pull`, `/sync/push`, `/sync/state` devuelven `500 FUNCTION_INVOCATION_FAILED` (tanto directo `/api/sync/*` como vía rewrite `/sync/*`). Por el paso 3 del plan, probé (a) (shims en `api/` de la raíz, Root Directory=raíz, `.vercelignore` para el árbol de Flutter, `.vercel/` real movido a un tmpdir y restaurado al final, proyecto descartable `cingula-phase11-spike-a`): **resultado idéntico**. Para descartar que fuera algo específico de los shims (import relativo hacia `backend/`, fuera de ambas Root Directory candidatas), agregué un handler trivial sin ningún import (`api/hello.js`, `res.status(200).json({ok:true})`) bajo el setup de (a): **falló igual**, `500 FUNCTION_INVOCATION_FAILED`. Con `--debug` se ve la causa real: el CLI spawnea el subproceso dev-server del builder `@vercel/node` (`Proxying to "@vercel/node" dev server (port=X, pid=Y)`) y ~300ms después reporta `Error: connect ETIMEDOUT 127.0.0.1:X` — el subproceso crashea al arrancar, no es un timeout genuino. Un servidor HTTP de Node hecho a mano (`http.createServer`) bindeó y respondió sin problema en el mismo entorno, descartando un problema general de red/loopback de Windows. Esto confirma que es un bug específico del bootstrap de `@vercel/node@16.0.1` (CLI 60.1.3, Node 22.14.0, Windows) — no del mecanismo de ruteo elegido.
- **Qué SÍ se validó pese al bug:** el ruteo/descubrimiento de Vercel funciona correctamente para ambos candidatos — rutas reales dan `500` (encontradas, intento de invocación) mientras que rutas inexistentes dan `404` (`curl /sync/doesnotexist` → 404, `curl /api/doesnotexist` → 404, verificado explícitamente); los estáticos (`spike.html`) sirven `200 text/html` desde la misma Root Directory en ambos casos.
- **Decisión (usuario, tras checkpoint):** Opción 1 — proceder con (d) (ya construido y commiteado en Task 1), no gastar más tiempo debugueando el bug de tooling local, diferir la evidencia `SMOKE OK` real al Preview de la Fase 11 Plan 04 (que no pasa por este código de dev-server local).
- **Archivos modificados:** ninguno de forma permanente — todos los artefactos del spike (2 proyectos descartables, `spike.html`, `web/.vercel/`, `web/.gitignore` autogenerado, `api/` y `package.json`/`vercel.json`/`.vercelignore`/`.env.local` de la raíz) fueron creados y eliminados dentro de la misma sesión; `git status --porcelain` limpio antes de cada commit.
- **Verificación de la limpieza:** `npx vercel@latest project ls --scope ramas-projects-e2ba61a0 | grep spike` → sin resultados; `.vercel/project.json` de la raíz muestra `"projectName":"cingula"` (el real, restaurado); `git status --porcelain` limpio.
- **Committed in:** N/A (nada que commitear del spike en sí — el hallazgo está documentado en `backend/README.md` (`85bdd07`) y en este SUMMARY)

---

**Total deviations:** 1 hallazgo de entorno documentado (no un auto-fix de código; no había código propio que arreglar)
**Impact on plan:** Cero impacto en el mecanismo elegido — Task 1 (los shims reales) no cambió. El único impacto es que la evidencia `SMOKE OK` de este plan se reemplaza por una nota explícita en el README y este SUMMARY, diferiendo esa evidencia al Preview real del plan 04. No hay deuda de código, solo una dependencia de verificación movida a la fase siguiente.

## Issues Encountered

Ver Deviations arriba — el "issue" y la "deviation" son la misma cosa en este plan (un hallazgo de entorno, no un bug de código a corregir).

## User Setup Required

None - no requiere configuración externa nueva. El Preview real del plan 04 usará el proyecto Vercel `cingula` ya linkeado (`.vercel/`, desde el plan 02), sin pasos manuales adicionales de este plan.

## Next Phase Readiness

- Plan 04 (primer Preview real) puede desplegar directamente con `web/` como Root Directory del proyecto `cingula` real — los 3 shims y `web/vercel.json` ya están commiteados y listos.
- El README ya documenta el checklist de smoke pre-merge (`smoke-preview.sh` + `check-preview-db.sh`) que el plan 04 va a ejecutar contra el Preview real.
- Pendiente para el plan 04: confirmar que la evidencia `SMOKE OK` / 401 (pull sin key) / 405 (push GET) / 200 `spike`-equivalente sale limpia contra el Preview real — eso cierra definitivamente la validación que el spike local no pudo completar.
- Pendiente para Notion/ADR-005 (mencionado también en 11-02-SUMMARY): agregar una nota sobre este bug de `@vercel/node` local en Windows, para que cualquier otro desarrollador que reproduzca el spike sepa que un `500 FUNCTION_INVOCATION_FAILED` en `vercel dev` local no implica necesariamente un problema del código o del mecanismo de ruteo.

## Known Stubs

Ninguno — este plan no toca UI ni lógica de aplicación; solo infraestructura de ruteo y documentación.

---
*Phase: 11-infra-de-deploy-mismo-proyecto-vercel*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: web/api/sync/state.js, web/api/sync/push.js, web/api/sync/pull.js, web/package.json, web/vercel.json
- FOUND: backend/README.md
- FOUND: .planning/workstreams/web/phases/11-infra-de-deploy-mismo-proyecto-vercel/11-03-SUMMARY.md
- FOUND: commit 68fe01c (Task 1), commit 85bdd07 (Task 2), commit a3ec05d (checkpoint doc, resolved by this SUMMARY)
- `git status --porcelain` clean before this SUMMARY's own commit
