---
phase: "12"
slug: "web-de-lectura"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: true
created: "2026-10-06"
---

# Phase 12 — Validation Strategy

> Contrato de validación por fase para el muestreo de feedback durante la ejecución. Derivado de `12-RESEARCH.md` §Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Vitest + jsdom + Testing Library (unit/componente); `node:test` (backend, existente); Playwright (E2E teclado/foco/login) |
| **Config file** | `web/vite.config.js` (bloque `test`) y `web/e2e/playwright.config.js` — Wave 0 los instala |
| **Quick run command** | `cd web && npx vitest run --reporter=dot` |
| **Full suite command** | `cd web && npm test && npm run test:ui && npm run test:e2e` |
| **Estimated runtime** | ~30 s (quick); minutos (full + e2e) |

---

## Sampling Rate

- **After every task commit:** `cd web && npx vitest run --reporter=dot`
- **After every plan wave:** `npm test && npm run test:ui && npm run build`
- **Before `/gsd-verify-work`:** suite completa + `npm run test:e2e` + smoke contra Preview (ruteo)
- **Max feedback latency:** 30 segundos (lógica pura + componentes)

---

## Per-Task Verification Map

Una fila por tarea de los PLAN.md (completado al planificar, 2026-10-06). Los comandos corren desde la raíz del repo; `cd web` donde se indica. El plan 12-10 Task 2 actualiza la columna Status con lo que de verdad corrió. Las filas 12-11-xx y 12-12-xx (ajustes post-UAT D-20..D-23) se agregaron en 12-12 con el Status real; la compuerta humana 12-10-03 corre DESPUÉS de ellas.

| Task ID | Plan | Wave | Requirement | Threat Ref | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | AUTH-02 (prerrequisito) | T-12-SC | manual (checkpoint blocking-human: legitimidad de paquetes + fuentes/logo) | — (verificación humana en npmjs.com) | n/a | ✅ green (checkpoint humano resuelto antes de ejecutar 12-01; ver 12-01-SUMMARY) |
| 12-01-02 | 01 | 1 | AUTH-02 | T-12-01, T-12-04 | tracer: unit + node:test + build + e2e | `cd web && npm run test:ui && npm test && npm run build && npx playwright test -c e2e/playwright.config.js e2e/acceso.spec.js` | ❌ W0 (crea session/router specs, acceso.spec.js, configs) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok); `acceso.spec.js` incluido |
| 12-01-03 | 01 | 1 | AUTH-02, INFRA-01 (regresión) | T-12-01, T-12-02, T-12-03, T-12-05, T-12-07 | config + smoke Preview + canario de bundle | `bash -n web/scripts/smoke-preview.sh` + chequeo de vercel.json · `bash web/scripts/smoke-preview.sh "$PREVIEW_URL"` · build con canario + `! grep -rq <canario> web/dist` | ⚠ amplía smoke-preview.sh | ✅ green local (`bash -n web/scripts/smoke-preview.sh`, `.vercelignore`, build); smoke contra Preview corrido en 12-01 (A1/A2). Smoke del Preview final y de producción: pendiente en la compuerta 12-10-03 |
| 12-02-01 | 02 | 2 | WEB-07, WEB-08, AUTH-02 | T-12-08, T-12-09, T-12-11, T-12-12 | tracer: unit + e2e | `cd web && npx vitest run src/data src/app && npx playwright test -c e2e/playwright.config.js e2e/sync.spec.js` | ❌ W0 (crea fixtures.js, mock-api.js, pull/model/store specs) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-02-02 | 02 | 2 | WEB-08, WEB-02, WEB-03 | T-12-10 | unit (TDD) + e2e | `cd web && npx vitest run src/data src/app/format.spec.js && npx playwright test -c e2e/playwright.config.js e2e/sync.spec.js && npm run build` | ❌ W0 (geometry/format specs) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-03-01 | 03 | 3 | WEB-01, WEB-08 | T-12-13 | tracer: node:test con servidor HTTP local | `cd web && node --test scripts/measure-pull.test.js && npm test` | ❌ W0 | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-03-02 | 03 | 3 | WEB-01 | T-12-14, T-12-15, T-12-16 | manual (human-action: WEB_API_KEY en Production + medición) + curl | `curl -s -o /dev/null -w '%{http_code} %{content_type}' https://cingula.vercel.app/sync/state` -> `401 application/json` | n/a | ✅ green (human-action cerrado en 12-03, ver 12-03-SUMMARY); `401 application/json` de producción re-verificable en 12-10-03 |
| 12-03-03 | 03 | 3 | WEB-01 | — | doc (OI-02 cerrado) | `grep -c "CIRCLES_MIN_ZOOM" .planning/workstreams/web/phases/12-web-de-lectura/12-UI-SPEC.md` | ✅ (UI-SPEC existe) | ✅ green (`grep -c CIRCLES_MIN_ZOOM 12-UI-SPEC.md` = 4) |
| 12-04-01 | 04 | 3 | WEB-07 | T-12-17, T-12-20 | tracer: e2e falla -> reintento | `cd web && npx playwright test -c e2e/playwright.config.js e2e/sync.spec.js && npx vitest run src/app src/data` | ✅ (sync.spec.js de 12-02) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-04-02 | 04 | 3 | WEB-07, WEB-08 | T-12-18, T-12-19 | unit (TDD, fake timers) + componente + e2e | `cd web && npx vitest run src/app/syncState.spec.js src/data/store.spec.js src/app/SyncPill.spec.jsx && npx playwright test -c e2e/playwright.config.js e2e/sync.spec.js` | ❌ W0 (syncState/SyncPill specs) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-05-01 | 05 | 3 | WEB-04, WEB-08 | T-12-21, T-12-22 | tracer: unit + e2e deep link | `cd web && npx vitest run src/panel && npx playwright test -c e2e/playwright.config.js e2e/panel.spec.js` | ❌ W0 (buildView.spec.js, panel.spec.js) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-05-02 | 05 | 3 | WEB-08 (stale), D-05 | T-12-21 | componente (TDD) + e2e | `cd web && npx vitest run src/panel && npx playwright test -c e2e/playwright.config.js e2e/panel.spec.js` | ❌ W0 (SidePanel.spec.jsx) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-05-03 | 05 | 3 | WEB-02, WEB-05 | T-12-22 | unit (TDD) filtrado por tipo | `cd web && npx vitest run src/panel/buildView.spec.js -t recorrido && npx vitest run src/panel/buildView.spec.js -t path && npx vitest run src/panel` | ✅ (de 12-05-01) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-06-01 | 06 | 4 | WEB-06 | T-12-23, T-12-24 | tracer: componente + e2e | `cd web && npx vitest run src/panel/AudioCard.spec.jsx && npx playwright test -c e2e/playwright.config.js e2e/panel.spec.js` | ❌ W0 (AudioCard.spec.jsx) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-06-02 | 06 | 4 | WEB-05 | T-12-24 | componente (TDD) + e2e + build | `cd web && npx vitest run src/panel && npx playwright test -c e2e/playwright.config.js e2e/panel.spec.js && npm run build` | ❌ W0 (widgets.spec.jsx) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-07-01 | 07 | 4 | WEB-01 | T-12-26 | tracer: e2e con tiles mockeados + build | `cd web && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js && npm run build` | ❌ W0 (mapa.spec.js) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-07-02 | 07 | 4 | WEB-01 | T-12-25 | unit (TDD, jsdom) + e2e | `cd web && npx vitest run src/map && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js` | ❌ W0 (layers.spec.js) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-07-03 | 07 | 4 | WEB-01, WEB-02 | T-12-27, T-12-28 | e2e + suite + build | `cd web && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js e2e/panel.spec.js && npx vitest run && npm run build` | ✅ (de 12-07-01) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-08-01 | 08 | 5 | WEB-01 | T-12-29 | tracer: e2e modo Círculos | `cd web && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js && npx vitest run src/map` | ✅ | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-08-02 | 08 | 5 | WEB-01, WEB-05 | T-12-29, T-12-30 | unit (TDD) + e2e teclado | `cd web && npx vitest run src/map && npx playwright test -c e2e/playwright.config.js e2e/teclado.spec.js e2e/mapa.spec.js && npm run build` | ❌ W0 (teclado.spec.js) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-09-01 | 09 | 6 | WEB-04 | T-12-32, T-12-33 | tracer: componente + e2e | `cd web && npx vitest run src/pages/Obras.spec.jsx && npx playwright test -c e2e/playwright.config.js e2e/obras.spec.js` | ❌ W0 (Obras.spec.jsx, obras.spec.js) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-09-02 | 09 | 6 | WEB-03 | T-12-31, T-12-33 | componente (TDD) + e2e | `cd web && npx vitest run src/pages && npx playwright test -c e2e/playwright.config.js e2e/obras.spec.js` | ❌ W0 (Artistas.spec.jsx) | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-09-03 | 09 | 6 | WEB-04 (D-12) | T-12-32 | e2e + suite + build | `cd web && npx playwright test -c e2e/playwright.config.js e2e/obras.spec.js e2e/mapa.spec.js e2e/teclado.spec.js && npx vitest run && npm run build` | ✅ | ✅ green (12-10: `npm test` 52 ok / 5 skipped, `npm run test:ui` 185 ok, `npm run test:e2e` 57 ok, `npm run build` ok) |
| 12-10-01 | 10 | 7 | todos | T-12-36 | tracer: e2e del recorrido completo (+ CSP) | `cd web && npx playwright test -c e2e/playwright.config.js e2e/journey.spec.js && npm run build` | ❌ (journey.spec.js) | ✅ green local (`npx playwright test -c e2e/playwright.config.js e2e/journey.spec.js` + `npm run build`; 5 repeticiones sin fallo). Modo remoto implementado (`E2E_BASE_URL`/`E2E_BYPASS`) y NO corrido contra el Preview: pendiente en 12-10-03 |
| 12-10-02 | 10 | 7 | todos | T-12-35 | auditoría ponytail + suite completa + web/api sin cambios | `cd web && npm test && npm run test:ui && npm run test:e2e && npm run build && test -z "$(git diff <commit de planificación> -- api)"` | ✅ | ✅ green (auditoría ponytail A-K; ver 12-10-SUMMARY; diff de `web/api` contra el commit de planificación vacío) |
| 12-11-01 | 11 | 8 | WEB-01 (D-20) | T-12-SC | manual (checkpoint blocking-human: legitimidad de `polygon-clipping` + 2 transitivas) | — (verificación humana en npmjs.com antes de `npm install`) | n/a | ✅ green (compuerta resuelta por el usuario antes de ejecutar; instalado `polygon-clipping@0.15.7` exacto en `de62021`; ver 12-11-SUMMARY) |
| 12-11-02 | 11 | 8 | WEB-01 (D-20), WEB-08 | T-12-38, T-12-40 | tracer: unit (TDD), capa de datos aditiva (frontera verde) | `cd web && npx vitest run src/data && npm run test:ui && npm test` | ❌ W0 (`geometry.spec.js` casos de `circlesOutline`, outline en `model.spec.js`) | ✅ green (12-11: `src/data` 49 ok; `npm run test:ui` 192 ok con `--maxWorkers=3`; `npm test` 52 ok / 5 skipped) |
| 12-11-03 | 11 | 8 | WEB-01, WEB-04 (D-20) | T-12-38, T-12-40 | unit + e2e + build | `cd web && npx vitest run src/data src/map src/panel src/pages && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js e2e/obras.spec.js && npm test && npm run build` | ✅ | ✅ green (12-11: contorno = unión de punta a punta; grep de la caja del servidor = 0; ver 12-11-SUMMARY) |
| 12-11-04 | 11 | 8 | WEB-01 (D-21) | T-12-39 | unit (TDD) + e2e | `cd web && npx vitest run src/map && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js e2e/teclado.spec.js e2e/obras.spec.js && npm run build` | ✅ | ✅ green (12-11: 199 Vitest ok; E2E completo 60 ok; etiquetas por zoom, recorte a 200 px) |
| 12-12-01 | 12 | 9 | WEB-01 (D-22) | T-12-41, T-12-42, T-12-44 | tracer: componente + e2e (menú, chip, Esc, tab-order, teclas aisladas) | `cd web && npx vitest run src/map src/app src/panel && npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js e2e/journey.spec.js e2e/teclado.spec.js && npm run build` | ❌ W0 (`MapBar.spec.jsx`) | ✅ green (12-12: `MapBar.spec.jsx` 6 ok; `SyncPill.spec.jsx` sin cambios; 29 E2E ok; build ok) |
| 12-12-02 | 12 | 9 | WEB-05 (D-23), WEB-04 | T-12-42 | unit (TDD) + e2e + build | `cd web && npx vitest run src/panel src/pages && npx playwright test -c e2e/playwright.config.js e2e/panel.spec.js e2e/obras.spec.js && npm run build` | ✅ | ✅ green (12-12: 89 ok en `src/panel` + `src/pages`; 24 E2E ok; E2E de 380 px con 40 letras sin cortes) |
| 12-12-03 | 12 | 9 | todos (auditoría) | T-12-43, T-12-SC | auditoría ponytail + suite completa + doc-drift + `web/api` sin cambios | `cd web && npm test && npm run test:ui && npm run test:e2e && npm run build && test -z "$(git diff <commit de planificación> -- api)"` | ✅ | ✅ green (12-12: `npm test` 52 ok / 5 skipped; Vitest 206 ok con `--maxWorkers=3`; `npm run test:e2e` 67 ok; build ok; auditoría A-H y K en 12-12-SUMMARY) |
| 12-10-03 | 10 | 7 | todos, INFRA-01 (regresión) | T-12-34, T-12-37 | manual (human-action: UAT Preview + merge + celular) + smoke producción | `bash web/scripts/smoke-preview.sh https://cingula.vercel.app` -> `SMOKE OK` | ✅ | ⬜ pending (compuerta humana) |

*Status por tarea: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Mapa requisito → prueba (del research, con los nombres de archivo que fijaron los planes):

| Req | Behavior | Test Type | Automated Command | Plan/Task |
|-----|----------|-----------|-------------------|-----------|
| AUTH-02 | Login valida con `/sync/state`, guarda en `sessionStorage`, 401 limpia y redirige; ninguna clave en `src/`/`dist/` | unit + e2e + canario | `npx vitest run src/app/session.spec.js` · `npx playwright test -c e2e/playwright.config.js e2e/acceso.spec.js` · build con canario | 12-01-02, 12-01-03, 12-02-01 |
| WEB-01 | Capas por defecto, filtro por recorrido, auto-ajuste por los bounds del contorno, clic abre panel, Círculos. D-20: contorno = unión de círculos; D-21: etiquetas por zoom; D-22: menú `Capas y filtros` + chip + Esc/clic afuera + tab-order | unit + componente + e2e | `npx vitest run src/map src/data/geometry.spec.js src/map/layers.spec.js src/map/MapBar.spec.jsx` · `npx playwright test -c e2e/playwright.config.js e2e/mapa.spec.js e2e/journey.spec.js` | 12-07, 12-08, 12-11, 12-12-01 |
| WEB-02 | Créditos = unión de artistas de las obras; obras del recorrido en el panel | unit + e2e | `npx vitest run src/panel/buildView.spec.js -t recorrido` | 12-02-02, 12-05-03, 12-07-03 |
| WEB-03 | Artista con sus obras (sin borradas) | unit + componente | `npx vitest run src/data/model.spec.js src/pages/Artistas.spec.jsx` | 12-02-02, 12-09-02 |
| WEB-04 | Filtros recorrido y visibilidad; Cobertura = ancho × alto del contorno (D-20); "Sin cobertura todavía" = obra sin triggers; mini-mapa con el contorno | componente + e2e | `npx vitest run src/pages/Obras.spec.jsx` · `npx playwright test -c e2e/playwright.config.js e2e/obras.spec.js` | 12-05-01, 12-09-01, 12-09-03, 12-11-03 |
| WEB-05 | Path: `Tipo`, `Tolerancia` (D-23), grabación, audio, triggers `(position, uuid)` anónimos, huecos; portal = path `kind='portal'` hijo de la obra; `Volver a …` como flecha de 44 px con `aria-label` (D-23) | unit + componente + e2e | `npx vitest run src/data/geometry.spec.js src/panel/buildView.spec.js -t path src/panel/widgets.spec.jsx` · `npx playwright test -c e2e/playwright.config.js e2e/panel.spec.js` | 12-05-03, 12-06-02, 12-08-02, 12-12-02 |
| WEB-06 | AudioCard: 3 estados inline en path/portal, sin listado propio | componente | `npx vitest run src/panel/AudioCard.spec.jsx` | 12-06-01 |
| WEB-07 | Estados de la pill; reintento 3 × 30 s (fake timers); refresco incremental | unit + componente + e2e | `npx vitest run src/app/syncState.spec.js src/app/SyncPill.spec.jsx src/data/store.spec.js` | 12-02-01, 12-04 |
| WEB-08 | Sin `deleted_at` ni huérfanos; columnas sensibles fuera del modelo | unit | `npx vitest run src/data/model.spec.js src/data/store.spec.js` | 12-02, 12-04-02, 12-05-02 |
| Cross | Cliente de pull: páginas, cursor string, anti-bucle; columnas usadas ⊆ `TABLE_SPEC` | unit | `npx vitest run src/data/pull.spec.js src/data/model.spec.js` | 12-02-01 |
| Cross | Ruteo de plataforma: `/sync/*` y `/api/sync/*` JSON, deep link SPA HTML, asset faltante no-HTML, headers | smoke (Preview y producción) | `bash web/scripts/smoke-preview.sh <url>` | 12-01-03, 12-10-03 |
| Cross | Teclado del mapa: Tab llega al portal, Enter abre, flechas recorren triggers, Esc devuelve foco | e2e | `npx playwright test -c e2e/playwright.config.js e2e/teclado.spec.js` | 12-08-02 |
| Cross | CSP real sin violaciones en el recorrido completo | e2e remoto | `E2E_BASE_URL=<preview> npx playwright test -c e2e/playwright.config.js e2e/journey.spec.js` | 12-10-01, 12-10-03 |
| Backend | Sin regresión del backend | node:test | `cd web && npm test` | todas |

---

## Wave 0 Requirements

- [x] `web/vite.config.js` con bloque `test` (include `src/**/*.spec.{js,jsx}`, jsdom) y `web/src/test-setup.js` — 12-01-02
- [x] `web/e2e/playwright.config.js` (`webServer: vite`) — 12-01-02; `page.route` para `/sync/**` (`e2e/mock-api.js`, 12-02-01) y para tiles de OSM (12-07-01), para no pegarle a OSM
- [x] Fábrica de filas sintéticas en `src/test/fixtures.js` (`makeRows`/`makePages`), generada desde `TABLE_SPEC` (no copiar datos del prototipo, OI-03) — 12-02-01
- [x] Specs de la tabla anterior (todos nuevos) — cada uno en la tarea indicada
- [x] Ampliar `web/scripts/smoke-preview.sh` con chequeos de ruteo SPA, funciones y headers — 12-01-03
- [x] Scripts de `package.json` (`dev/build/preview/test/test:ui/test:e2e`) y restringir `test` (backend) a globs, para que `node --test` no recoja los specs de la SPA y Vitest no recoja `api/**/*.test.js` — 12-01-02
- [x] `.vercelignore`: `**/*.spec.js`, `**/*.spec.jsx`, `e2e/`, `src/test/` — 12-01-03
- [x] Instalación de devDependencies (con `checkpoint:human-verify` `blocking-human` por los paquetes marcados "too-new" en el research) — 12-01-01 / 12-01-02

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tab-order en un path de 30+ triggers | WEB-05 / a11y | Depende de datos reales y del orden visual | Recorrer con Tab y flechas el modo Círculos sobre el path más largo |
| Nombre de 60 caracteres | UI Considerations (long-text) | Prueba visual | Cargar una obra con nombre largo; verificar elipsis y riel |
| Responsive < 900 px | OI-05 | Regla [DEFAULT] sin validar | Revisar a 800 px con el usuario |
| Contraste del peso 400 en etiquetas 13 px | R14 | Juicio visual | Revisar sobre `--surface-card` |
| Conteo real de triggers (umbral y tope de Círculos) | OI-02 | Requiere `WEB_API_KEY` del usuario (Production no la tenía al planificar: la crea el usuario en 12-03-02) | Correr `WEB_API_KEY=<clave> node web/scripts/measure-pull.mjs` en la terminal del usuario (12-03-02) |
| Push real del celular antes y después del merge a `main` | INFRA-01 (regresión por `web/vercel.json`) | Requiere el dispositivo físico | 12-10-03 pasos 2 y 5 |
| Login real en producción con la `WEB_API_KEY` de Production | AUTH-02 | Requiere la clave del usuario | 12-10-03 paso 4 |
| (g) Umbrales de etiquetas por zoom `LABELS_PATH_ZOOM = 16` / `LABELS_PORTAL_ZOOM = 17` con los datos reales | WEB-01 (D-21), OI-11 | [DEFAULT] sin validar; Production no tiene portales (`paths_portal: 0`), así que el de 17 sólo se juzga con paths | En el Preview, alejar y acercar sobre la zona densa: ¿se leen los nombres sin pisarse y cambian en el zoom esperado? |
| (h) Aspecto del contorno de las 74 obras reales | WEB-01 (D-20) | Juicio visual: 24 vértices circunscritos, obras con partes y agujeros, costo de la unión con datos reales | Revisar el mapa completo en el Preview: contornos sin huecos raros y sin lentitud al cargar |
| (i) Menú `Capas y filtros` y chip a 800 px | WEB-01 (D-22), OI-05 | La regla < 900 px de la tarjeta (ancho completo, termina antes de la hoja inferior) es [DEFAULT] sin validar | Revisar a 800 px con el panel abierto: botón, tarjeta, chip y × |
| (j) El botón de flecha se entiende como "volver" | WEB-05 (D-23) | Juicio de usuario: botón "chico" interpretado como ícono de 20 px con área de 44 px | Abrir un path y un trigger; decidir si la flecha basta o si se quiere más chica también en área |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
