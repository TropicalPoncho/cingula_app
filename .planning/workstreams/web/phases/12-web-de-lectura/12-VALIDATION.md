---
phase: "12"
slug: "web-de-lectura"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
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

Se completa cuando existan los PLAN.md (una fila por tarea). Mapa requisito → prueba (del research):

| Req | Behavior | Test Type | Automated Command | File Exists |
|-----|----------|-----------|-------------------|-------------|
| AUTH-02 | Login valida con `/sync/state`, guarda en `sessionStorage`, 401 limpia y redirige; ninguna clave en `src/`/`dist/` | unit + e2e + grep | `npx vitest run src/app/session.spec.js` · `npx playwright test e2e/acceso.spec.js` · `! grep -rEn "VITE_[A-Z_]*KEY" src vite.config.js` | ❌ W0 |
| WEB-01 | Capas por defecto, filtro por recorrido, auto-ajuste de bbox, clic abre panel | unit + e2e | `npx vitest run src/map src/data/geometry.spec.js` · `npx playwright test e2e/mapa.spec.js` | ❌ W0 |
| WEB-02 | Créditos = unión de artistas de las obras; obras del recorrido en el panel | unit | `npx vitest run src/panel/buildView.spec.js -t recorrido` | ❌ W0 |
| WEB-03 | Artista con sus obras (sin borradas) | unit + componente | `npx vitest run src/data/model.spec.js -t artistas` | ❌ W0 |
| WEB-04 | Filtros recorrido y visibilidad; "Sin cobertura todavía" | unit + componente | `npx vitest run src/pages/Obras.spec.jsx` | ❌ W0 |
| WEB-05 | Path: kind, tolerancia, grabación, audio, triggers `(position, uuid)` anónimos, huecos; portal = path `kind='portal'` hijo de la obra | unit | `npx vitest run src/data/geometry.spec.js src/panel/buildView.spec.js -t path` | ❌ W0 |
| WEB-06 | AudioCard: 3 estados inline en path/portal, sin listado propio | componente | `npx vitest run src/panel/AudioCard.spec.jsx` | ❌ W0 |
| WEB-07 | Estados de la pill (leyendo / al día / desactualizado / error con y sin datos / sin conexión); reintento 3 × 30 s (fake timers) | unit + componente | `npx vitest run src/app/syncState.spec.js src/app/SyncPill.spec.jsx` | ❌ W0 |
| WEB-08 | Ninguna colección contiene `deleted_at != null`; hijos de padres borrados descartados; `share_token`/`owner_id`/`user_id` no se propagan | unit | `npx vitest run src/data/model.spec.js src/data/store.spec.js` | ❌ W0 |
| Cross | Cliente de pull: páginas, cursor string, guarda anti-bucle; columnas usadas ⊆ `TABLE_SPEC` | unit | `npx vitest run src/data/pull.spec.js src/data/model.spec.js` | ❌ W0 |
| Cross | Ruteo de plataforma: `/sync/*` y `/api/sync/*` JSON, deep link SPA HTML, asset faltante no-HTML | smoke (Preview) | `bash web/scripts/smoke-preview.sh <preview-url>` (ampliar) | ⚠ ampliar |
| Cross | Teclado del mapa: Tab llega al portal, Enter abre, flechas recorren triggers, Esc contrae | e2e | `npx playwright test e2e/teclado.spec.js` (red y tiles mockeados) | ❌ W0 |
| Backend | Sin regresión del backend | node:test | `cd web && npm test` | ✅ |

*Status por tarea: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web/vite.config.js` con bloque `test` (include `src/**/*.spec.{js,jsx}`, jsdom) y `web/src/test-setup.js`
- [ ] `web/e2e/playwright.config.js` (`webServer: vite`; `page.route` para `/sync/**` y tiles de OSM, para no pegarle a OSM)
- [ ] Fábrica `makePull()` en `src/test/fixtures.js`, generada desde `TABLE_SPEC` (no copiar datos del prototipo, OI-03)
- [ ] Specs de la tabla anterior (todos nuevos)
- [ ] Ampliar `web/scripts/smoke-preview.sh` con chequeos de ruteo SPA
- [ ] Scripts de `package.json` (`dev/build/preview/test/test:ui/test:e2e`) y restringir `test` (backend) a globs, para que `node --test` no recoja los specs de la SPA y Vitest no recoja `api/**/*.test.js`
- [ ] `.vercelignore`: `**/*.spec.js`, `**/*.spec.jsx`, `e2e/`
- [ ] Instalación de devDependencies (con `checkpoint:human-verify` por los paquetes marcados "too-new" en el research)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tab-order en un path de 30+ triggers | WEB-05 / a11y | Depende de datos reales y del orden visual | Recorrer con Tab y flechas el modo Círculos sobre el path más largo |
| Nombre de 60 caracteres | UI Considerations (long-text) | Prueba visual | Cargar una obra con nombre largo; verificar elipsis y riel |
| Responsive < 900 px | OI-05 | Regla [DEFAULT] sin validar | Revisar a 800 px con el usuario |
| Contraste del peso 400 en etiquetas 13 px | R14 | Juicio visual | Revisar sobre `--surface-card` |
| Conteo real de triggers (umbral y tope de Círculos) | OI-02 | Requiere `WEB_API_KEY` del usuario | Correr `web/scripts/measure-pull.mjs` con la clave en sesión |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
