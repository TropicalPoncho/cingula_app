---
phase: 12-web-de-lectura
plan: 10
subsystem: web-e2e-audit
tags: [playwright, csp, e2e, ponytail-audit, validation, adr, tracer]

requires:
  - phase: 12-04
    provides: "pill de sync y reintento"
  - phase: 12-09
    provides: "páginas Obras / Artistas, mini-mapa"
provides:
  - "web/e2e/journey.spec.js: recorrido completo en un solo E2E con detector de violaciones de CSP, errores no capturados y mensajes de consola de CSP"
  - "web/e2e/playwright.config.js: modo remoto (E2E_BASE_URL sin webServer + E2E_BYPASS -> x-vercel-protection-bypass)"
  - "Auditoría ponytail A-K de toda la SPA (abajo)"
  - "12-VALIDATION.md con estados reales y wave_0_complete: true"
  - "12-ADR-PUBLISH-PENDING.md: texto final del ADR + nota ADR-005 (pendiente de publicar en Notion)"
affects: []

status: partial
partial_reason: "Tasks 1-2 done, Task 3 pending (human gate)"
commits: 2   # MEASURED: git rev-list --count 963eaab..caa2b02 (sólo los 2 commits de tarea; este SUMMARY se commitea aparte)
plan_head_before: 963eaabdf76e3fdb973567b5f76725787c36d365
plan_head_after: caa2b0203ba7186479f8f075c8ef39ac3820a05c
actuals:
  tokens: 20000   # chars/4 sobre el diff real de web/ + docs; estimación aproximada
  tasks: 2
  commits: 2
requirements: [AUTH-02, WEB-01, WEB-02, WEB-03, WEB-04, WEB-05, WEB-06, WEB-07, WEB-08]
requirements-completed: []   # el cierre de requisitos queda para después de la compuerta humana (Task 3)
---

# Phase 12 Plan 10: E2E del recorrido completo + auditoría ponytail (PARCIAL) Summary

**PARCIAL: Tasks 1-2 hechas, Task 3 (compuerta humana: UAT en el Preview, merge a main, celular antes/después, smoke de producción) pendiente.**

## Decisión que afecta el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras la compuerta no esté hecha |
|----------|---------|--------------------------|--------------------------------------------|
| **El E2E del recorrido completo corre con la red y los tiles mockeados también en modo remoto** (`mockApi` sigue activo contra el Preview). Lo que el Preview agrega es lo que `vite dev` no tiene: los **headers reales** (CSP) y el bundle de producción | La CSP de `vercel.json` no existe en `vite dev` (RESEARCH Pattern 1); mockear la red mantiene el test determinista, sin tocar Neon ni gastar tiles de OSM, y sin necesitar `WEB_API_KEY` | Correr el E2E contra el Preview con la API real (depende de datos de producción que hoy no tienen recorridos/artistas, y exigiría una clave); desactivar el mock en modo remoto | **El E2E remoto NO se corrió contra el Preview en esta sesión** (no hay `VERCEL_BYPASS` ni rama pusheada). Hasta que se corra en la compuerta, una regresión de CSP sólo detectable con los headers reales no está descartada. El modo remoto está implementado y el detector está probado localmente (el test falla si aparece un `securitypolicyviolation`; en local no hay CSP, así que sólo se probó el camino sin violaciones) |
| **La auditoría ponytail dejó la SPA igual de chica pero corrigió dos fugas del contrato tipográfico (R10) que ningún test cubría** | Un escaneo de `getComputedStyle` de todas las páginas encontró dos elementos fuera de 13/15/20/40 px y 300/400: el encabezado de la tabla de portales (12 px / 500) y el glifo del control de zoom de Leaflet (22 px / 700) | Dejarlos (el contrato R10/R14 es explícito) | Ninguno funcional; es estético. El escaneo fue ad hoc (borrado) y **no quedó como test permanente**: una regresión de tamaños no se detectaría automáticamente |

## Tasks

### Task 1 (tracer): E2E del recorrido completo — `2d9b073`

- `web/e2e/journey.spec.js` (un test, ~8 s local): `/` -> `/acceso`; clave mockeada; pill `Sync al día`; leyenda `3 obras · 3 paths · 35 triggers · 1 portal`; filtro de recorrido 1 abre su panel con `Créditos`; obra A, `Ver detalle completo`, path `Ruta A` (tira `32 triggers, 1 hueco`, `Audio del path`); modo Círculos, `Trigger 001`, `Siguiente` -> `Trigger 002`; `Obras` filtrada por `Pública`, abrir A (breadcrumb `Obras`, mini-mapa `Mapa de Obra Aurora`); `Artistas`, artista con bio; `Salir de la web` -> `/acceso` con `sessionStorage` vacío.
- Detectores: `securitypolicyviolation` (vía `exposeFunction` + `addInitScript`, sobrevive a recargas), mensajes de consola `content security policy|refused to`, y `pageerror` (errores no capturados). El test falla si cualquiera aparece.
- `web/e2e/playwright.config.js`: con `E2E_BASE_URL` usa esa `baseURL` y **no** levanta `webServer`; con `E2E_BYPASS` agrega `extraHTTPHeaders: { 'x-vercel-protection-bypass': ... }`. Sin variables: el modo local de 12-01 sin cambios.
- Verificación: `npx playwright test -c e2e/playwright.config.js e2e/journey.spec.js` pasa (5 repeticiones sin fallo) y `npm run build` OK.

### Task 2: Auditoría ponytail + VALIDATION + ADR — `caa2b02`

Skill `ponytail:ponytail-audit` sobre `web/src`, `web/e2e`, `vite.config.js`, `vercel.json`, `package.json`, `scripts/smoke-preview.sh`, `scripts/measure-pull.mjs` (sin `web/api`).

| Chequeo | Resultado |
|---------|-----------|
| **A. Dependencias** | OK. `dependencies` = sólo `@neondatabase/serverless`; `devDependencies` = 12 (`node -e` sale 0). Sin librería de estado, router, cliente HTTP ni wrapper de Leaflet. Los 6 paquetes de testing/UI revisados tienen al menos un importador |
| **B. Estado global** | OK. Sin `createContext`/`useContext` en `src/`; el único store es `store.js` (useSyncExternalStore). Se agregó el comentario `ponytail:` con su techo |
| **C. Router ≤ 60 líneas** | **Corregido**: estaba en 65 (violaba el criterio). `setParams` con ternario en una línea y `A` como arrow-component con `(preventDefault, navigate)`: **57 líneas**. `router.spec.js` y la suite siguen verdes |
| **D. Abstracciones sin segundo consumidor** | OK con 4 excepciones deliberadas. Todo export de `src/` tiene un importador fuera de su spec, salvo `STALE_MS`, `USED_COLUMNS`, `CIRCLES_MAX`, `styleFor`: se usan dentro de su propio módulo y los specs los importan para fijar el umbral/contrato (de-exportarlos rompería los tests sin ahorrar código). Los módulos de un solo consumidor (`AudioCard`, `CoverageStrip`, `PortalTable` -> `EntityDetail`; `MapBar` -> `MapPage`) se **mantienen**: cada uno tiene su spec y fusionarlos no acorta nada. `parts.jsx` (4 exports) lo usan Obras y Artistas |
| **E. CSS** | **Borrado**: las 8 clases `.type-*` de `tokens.css` (sin uso, y con tamaños/pesos fuera de R10) y `.cg-label` (en `bundle.css` y `shell.css`). **Corregidas dos fugas de R10** detectadas con un escaneo de estilos computados de las 7 vistas: `.tbl th` (12 px / 500 -> 13 px / 400, `panel.css`) y el glifo del zoom de Leaflet (22 px / 700 -> 20 px / 400, `map.css`). Resultado del escaneo posterior: todo el texto renderizado de la SPA usa 13/15/20/40 px y 300/400 |
| **F. Fuentes** | OK. 3 `.woff2` y 3 `@font-face` |
| **G. `web/api` sin cambios** | OK. `git diff 5759616 -- web/api` vacío (5759616 = `docs(12): create phase plan`) |
| **H. `vercel.json` / smoke** | OK. Sin `functions`/`builds`/`routes`; `smoke-preview.sh` sin opciones sin uso (`bash -n` OK; `SMOKE_API_KEY` y `VERCEL_BYPASS` son opcionales y se usan) |
| **I. Tests** | OK. Una verificación ejecutable por lógica no trivial; revisé `AudioCard.spec` vs `widgets.spec` y no hay duplicados en la misma capa. No se borró ningún test |
| **J. Comentarios `ponytail:`** | **Agregados** los que faltaban con su techo: store global (`store.js`), ancho de corredor por mediana de radios OI-10 (`geometry.js`), filtro oscuro de tiles OI-07 (`map.css`). Ya existían: tope de círculos (`layers.js`), pesos de fuente (`tokens.css`), `fitKey` (`MapView.jsx`), proxy de dev (`vite.config.js`) |
| **K. NO se tocó** | Verificado por grep y por la suite verde: lista blanca de columnas (`USED_COLUMNS` en `model.js`), `parseSel` (`buildView.js`), manejo de 401 (`store.js:82`), guarda anti-bucle de `pullAll` (`pull.js`, `nextCursor === cursor`), headers de `vercel.json` (CSP con `frame-ancestors`), ARIA/tabindex, estados de error de la pill y de las páginas |

**Mantenido a propósito (hallazgo del audit que NO se aplicó):** `scripts/measure-pull.mjs` + su test (108 + ~60 líneas). Es una medición de una sola vez (OI-02, 12-03) con los resultados ya incorporados a las constantes, así que ponytail la marcaría `delete:`. Se conserva porque producción todavía no tiene recorridos/artistas/`obra_artistas` (12-03): hay que volver a medir cuando el celular los sincronice, antes de dar por buenos el tope de círculos y el ancho de corredor. Borrarla es una decisión del usuario (una línea en la compuerta).

**Diff de la auditoría:** código de `web/src` neto negativo (-12 líneas: router -8, tokens.css -8, bundle.css -1; +4 líneas de comentario `ponytail:` y +3 de CSS de las correcciones de R10). Sin dependencias quitadas (no había ninguna sobrante).

**Suite completa tras la auditoría:** `npm test` 52 ok / 5 skipped / 0 fail; `npm run test:ui` 185 ok (16 archivos); `npm run test:e2e` 57 ok (incluye `journey.spec.js`); `npm run build` OK (JS 427,38 kB / 131,28 kB gzip).

**VALIDATION:** columna Status completada con el resultado real de cada fila (todas ✅ salvo 12-10-03 ⬜ pending), Wave 0 marcado, `wave_0_complete: true`; `nyquist_compliant: false` y `status: draft` sin tocar. Las filas con comando propio se marcaron verdes por la suite completa (ejecuté la suite entera, no cada comando de fila por separado); las dos con parte remota (12-01-03, 12-10-01) dicen explícitamente qué falta.

**ADR:** NO publicado en Notion (sin herramientas de Notion en esta sesión). Texto final (decisión primero, alternativas, consecuencias/riesgos, C4 Contenedores + secuencia en Mermaid, estado real y la nota pendiente de ADR-005 acumulada desde 11-02..11-05) en `.planning/workstreams/web/phases/12-web-de-lectura/12-ADR-PUBLISH-PENDING.md`. **Estado: pendiente de publicar.**

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reset del branch de arranque del worktree**
- HEAD arrancó en `5b1ac2f`; `git reset --hard ws/web` -> `963eaab` (paso sanctioned de arranque), verificado `parts.jsx` y `12-09-SUMMARY.md`, `npm ci`.

**2. [Rule 1 - Bug] Leaflet lanza `TypeError` tras `map.remove()` si se sale del mapa durante un zoom animado**
- **Found during:** Task 1 (primer corrido en frío; Vite imprimió `Cannot read properties of undefined (reading '_leaflet_pos')` desde `_onZoomTransitionEnd`). Leaflet 1.9.4 deja un `setTimeout(250 ms)` que corre después de `remove()`.
- **Fix:** `map._animatingZoom = false` justo antes de `map.remove()` en la limpieza de `MapView.jsx` (la guarda privada de Leaflet vuelve el callback un no-op), con comentario `ponytail:`.
- **Limitación honesta:** el error apareció una sola vez y **no se pudo reproducir de forma determinista** (5 repeticiones del E2E sin error antes y después del fix); no hay test que lo cubra. Toca un campo privado de Leaflet: si se actualiza Leaflet, revisar. El `pageerror` del E2E del recorrido lo detectaría si reaparece.
- **Commit:** `2d9b073` (junto al tracer, en `web/src/map/MapView.jsx`, fuera de `files_modified` del plan).

**3. [Rule 1 - Bug] Dos fugas de tipografía fuera del contrato R10** — ver chequeo E; commit `caa2b02`.

### Chequeo C incumplido de origen
El router tenía 65 líneas (> 60 del criterio de aceptación); se redujo a 57 en esta auditoría.

### Otros
- Archivos fuera de `files_modified`: `web/src/map/MapView.jsx`, `map.css`, `panel.css`, `shell.css`, `ds/bundle.css`, `ds/tokens.css`, `data/store.js`, `data/geometry.js` (cambios de la auditoría; `web/src/` figura en el plan) y `12-ADR-PUBLISH-PENDING.md` (el fallback "pendiente de publicar" que pide el plan, pero en archivo propio en vez de dentro del SUMMARY por su tamaño y porque tiene diagramas).
- Un archivo vacío `scratch-exports.sh` creado por error en la raíz del repo principal (un `cat >` sin entrada) fue borrado de inmediato; no quedó rastro en git.
- Se corrió un E2E auxiliar de escaneo de estilos (`zz-scan.spec.js`) y se borró; no queda en el árbol.
- No se tocaron STATE.md, ROADMAP.md ni REQUIREMENTS.md, y no se corrió ningún verbo `state`/`roadmap`/`requirements` (el orquestador los actualiza).
- Procesos: sólo se usó `npx playwright test` (el runner levanta y cierra vite); no se lanzaron navegadores ni procesos auxiliares por fuera.

## Auth gates

Ninguno (la Task 3 es la compuerta humana).

## Known Stubs

Ninguno.

## Threat Flags

Ninguna superficie nueva. T-12-35 mitigada (chequeo K con grep y suite verde); T-12-37: ningún secreto en archivos (`E2E_BYPASS` y `VERCEL_BYPASS` sólo por entorno); T-12-SC: sin instalaciones (`package.json` y lockfile sin diff). **T-12-36 (regresión de CSP) sigue abierta** hasta correr el E2E remoto en la compuerta; **T-12-34 (ruteo del push del celular)** sigue abierta hasta la compuerta completa.

## PENDIENTE — Task 3 (compuerta humana, `gate="blocking-human"`)

**Task 3 pending — run AFTER 12-11 and 12-12** (planes post-UAT D-20..D-23, agregados 2026-10-08). Incluir en la UAT los ítems manuales (g)-(j) que 12-12 agrega a `12-VALIDATION.md`.

Checklist exacto de la compuerta (el ejecutor que la retome hace 1-4 antes de pausar y 5 al reanudar):

1. `git push origin ws/web` (nunca `main`) y esperar el Preview **Ready**.
2. `VERCEL_BYPASS` sólo en la sesión: `bash web/scripts/smoke-preview.sh <preview-url>` -> `SMOKE OK <preview-url>`.
3. E2E remoto con detector de CSP: `E2E_BASE_URL=<preview-url> E2E_BYPASS=$VERCEL_BYPASS npx --prefix web playwright test -c web/e2e/playwright.config.js web/e2e/journey.spec.js` (o desde `web/`: `-c e2e/playwright.config.js e2e/journey.spec.js`) -> `1 passed` sin violaciones de CSP. Si falla por una violación, NO mergear: arreglar la CSP/recurso.
4. `cd web && npm test && npm run test:ui && npm run test:e2e && npm run build` verde.
5. Presentar al usuario (con la URL del Preview, sesión de Vercel en el navegador, clave = `WEB_API_KEY` de Preview scope `ws/web`):
   - UAT con datos reales: entrar; el mapa encuadra todas las obras; filtrar por un recorrido abre su panel con créditos; abrir obra -> path -> trigger y volver; Obras y Artistas.
   - Manuales de 12-VALIDATION: (a) Tab + flechas sobre el path real más largo en modo Círculos; (b) obra con nombre largo; (c) ancho de 800 px (regla DEFAULT OI-05: aceptarla o pedir cambios); (d) contraste de etiquetas 13 px en peso 400 (R14); (e) legibilidad de los tiles oscurecidos (OI-07); (f) defaults de OI-09 (reintento 3 x 30 s, desactualizado 15 min, primera obra por defecto en Obras). Si algo falla: describirlo y NO mergear.
   - Decisión pendiente: ¿se borra `scripts/measure-pull.mjs` o se conserva para re-medir con datos reales (ver arriba)?
   - Interpretación mía sin validar de 12-09: un link a un recorrido desde Obras abre el mapa (`/?rec=&sel=recorrido:`).
6. **Antes del merge:** en el celular real, un cambio mínimo que genere push, sincronizar contra producción -> sin error, estado de sync honesto.
7. Mergear `ws/web` -> `main` por PR (lo hace el usuario) y esperar Production **Ready**.
8. En `https://cingula.vercel.app`: entrar con la `WEB_API_KEY` de **Production** (la de 12-03) y ver el mapa con los datos reales.
9. **Después del merge:** repetir el push real del celular -> sin error y sin ningún cambio en la app.
10. Al reanudar: `bash web/scripts/smoke-preview.sh https://cingula.vercel.app` -> `SMOKE OK https://cingula.vercel.app`. Registrar en el SUMMARY (sin valores secretos) la URL del Preview, la UAT ítem por ítem (a-f) y las confirmaciones de 6, 8 y 9. Si el smoke de producción falla: Vercel -> Deployments -> último deploy sano -> **Instant Rollback**, luego `git revert -m 1 <merge>` en `main`; el outbox del celular reintenta (sin pérdida de datos). No cerrar la fase.
11. Publicar el ADR de `12-ADR-PUBLISH-PENDING.md` en Notion (skill `gestion-notion-rama`), actualizar su "Estado" con el resultado de la compuerta y agregar la nota a ADR-005; luego `/gsd-validate-phase` fija `nyquist_compliant`/`status` de VALIDATION.

---
*Phase: 12-web-de-lectura — Plan 10 PARCIAL (Tasks 1-2 de 3)*

## Self-Check: PASSED

- Archivos: `web/e2e/journey.spec.js`, `web/e2e/playwright.config.js`, `12-VALIDATION.md`, `12-ADR-PUBLISH-PENDING.md` existen.
- Commits en `git log`: `2d9b073`, `caa2b02`; `git rev-list --count 963eaab..caa2b02` = 2.
- Criterios: `grep -c securitypolicyviolation web/e2e/journey.spec.js` ≥ 1; `grep -c E2E_BASE_URL web/e2e/playwright.config.js` ≥ 1; `devDependencies` = 12; router 57 líneas; `wave_0_complete: true` = 1 y `nyquist_compliant: false` = 1; `web/api` sin diff.
