---
phase: 12-web-de-lectura
plan: 11
subsystem: web-map-outline-labels
tags: [leaflet, polygon-clipping, outline, semantic-zoom, labels, a11y, D-20, D-21, WEB-01, WEB-04]

requires:
  - phase: 12-07
    provides: "MapView / layers.js (buildLayers, applySelection, targetBounds)"
  - phase: 12-09
    provides: "mini-mapa de Obras"
  - phase: 12-10
    provides: "Tasks 1-2 (E2E del recorrido, auditoría); la compuerta humana 12-10 Task 3 corre después de 12-12"
provides:
  - "web/src/data/geometry.js: circlesOutline + OUTLINE_VERTICES (unión de círculos en metros -> polígonos [lat, lon] + bounds)"
  - "obra.outline en el modelo, calculado una vez por pull; el modelo ya no expone la caja del servidor ni maxRadius"
  - "layers.js: contorno L.polygon (cg-cover), outlineBounds, syncLabels, LABELS_PATH_ZOOM / LABELS_PORTAL_ZOOM"
  - "polygon-clipping@0.15.7 exacto en devDependencies (13)"
affects: [12-12, 12-10]

status: complete
commits: 4   # MEASURED: git rev-list --count f9ece0e..HEAD (sólo los 4 commits de tarea; este SUMMARY se commitea aparte)
plan_head_before: f9ece0e4bfc34a723a8315abb247927c3fe22350
plan_head_after: 52e7988bb8a1f022909f1f2ee05b5c5856eb5c20
actuals:
  tokens: 11750   # chars/4 sobre el diff real (sin package-lock): 46 972 chars
  tasks: 4
  commits: 4
requirements: [WEB-01, WEB-04]
requirements-completed: []   # lo cierra el orquestador
---

# Phase 12 Plan 11: Contorno de obra por unión de círculos + etiquetas por zoom Summary

**Cada obra se dibuja, se enfoca y se encuadra por el contorno exacto de la unión de los círculos de sus triggers (`polygon-clipping`, una vez por pull), el hecho Cobertura sale de ese contorno, y las etiquetas del mapa pasan a depender del zoom (obras de lejos; paths y portales de cerca) sin superponerse ni tocar el teclado.**

## Decisión que afecta el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras no se valide |
|----------|---------|--------------------------|------------------------------|
| **La cobertura de una obra la calcula el cliente** (unión de círculos con `polygon-clipping@0.15.7`, una vez por pull en `buildModel`) y la web ya no lee las seis columnas `cover_*` de `obras` (`USED_COLUMNS.obras` = 4 columnas). Supersede R2 de la UI-SPEC. | D-20 (usuario, UAT). La caja del servidor excluía el radio (H4) y era NULL en 3 de 74 obras con triggers (12-03); el contorno sale de los mismos triggers del pull: ninguna columna nueva, `web/api` sin cambios (`git diff f9ece0e -- web/api` vacío). | Rectángulo del servidor; casco convexo; truco SVG de trazo + relleno; cálculo en el servidor (cambia `web/api` y el contrato del pull de la fase 10). | **Dependencia nueva con mantenimiento bajo:** sin releases desde 2023-12-18; D-20 decía "sin dependencias", falso: trae `robust-predicates` y `splaytree`. Mitigado: una sola llamada (`union`) aislada en `geometry.js`, respaldo ante excepción (círculos sin unir, nunca pantalla en blanco, probado con spy) y alternativa API-compatible (`polyclip-ts`). **Costo en el bundle: JS 427,38 -> 455,99 kB (+28,6 kB), gzip 131,28 -> 140,53 kB (+9,3 kB)**, más de lo que sugería "librería chica". Las columnas `cover_*` siguen en el servidor (índice de `web/schema.sql:127`, escritas por `web/api/_lib/cover.js`): sólo la web dejó de leerlas. Esas escrituras son ahora trabajo muerto del servidor; quitarlas es un cambio de `web/api` fuera de este plan |
| **Umbrales de etiquetas [DEFAULT, sin validar]: `LABELS_PATH_ZOOM = 16`, `LABELS_PORTAL_ZOOM = 17`.** | D-21; 16 = `CIRCLES_MIN_ZOOM`; portales un nivel más cerca. | Umbrales por densidad medida (sin datos de portales: `paths_portal: 0`). | Bajo (cambiar un número). **Quedan como ítem manual para la compuerta de 12-10; 12-12 los registra en VALIDATION y UI-SPEC.** |

## Compuerta de legitimidad del paquete (Task 1)

Aprobada por el usuario antes de arrancar (el ejecutor no la repitió, sólo la registra): instalar `polygon-clipping@0.15.7` exacto (sin `^`/`~`) como devDependency; `polyclip-ts` NO elegido. Datos mostrados al usuario: MIT, ~1,03 M descargas/semana, sin scripts de instalación, última publicación 2023-12-18. Verificación del ejecutor al instalar: `npm view polygon-clipping@0.15.7` confirma nombre, licencia MIT, dependencias `robust-predicates ^3.0.2` y `splaytree ^3.1.0`, y scripts sólo de build/test/lint/`prepublishOnly` (ningún `preinstall`/`install`/`postinstall`).

Versiones que resolvió el lockfile (`npm --prefix web ls`): **polygon-clipping 0.15.7, robust-predicates 3.0.3, splaytree 3.2.3**. `dependencies` sigue siendo sólo `@neondatabase/serverless`; `devDependencies` pasó de 12 a 13 (el `node -e` del plan sale 0). Las transitivas no están en `package.json`.

## Tasks

### Task 1: compuerta de paquete — resuelta por el usuario, instalado en `de62021`

`chore(12-11): add polygon-clipping (gate approved)`: sólo `web/package.json` (+1 línea) y `web/package-lock.json` (+29).

### Task 2: capa de datos — `a5ed3cb` (commit verde intermedio, aditivo)

- `geometry.js`: `import polygonClipping from 'polygon-clipping'` (siempre el export por defecto, `polygonClipping.union(...)` sobre el objeto), `OUTLINE_VERTICES = 24` con su `ponytail:` (circunscrito: radio / cos(π/24), error hacia afuera ≈ 0,9 % del radio), `circlesOutline(circles, vertices)`: ignora radio <= 0 y coordenadas no finitas, `null` si no queda ninguno, respaldo con `try/catch` (`ponytail:`) que devuelve un polígono por círculo sin unir. Salida en `[lat, lon]` (orden de Leaflet) sin el vértice de cierre repetido, más `bounds`.
- `model.js`: `o.outline = circlesOutline([triggers de routes..., trigger de cada portal])` una vez por pull. Aditivo: la caja y `maxRadius` seguían intactos en este commit.
- Specs: 6 casos de geometría (vacío, un círculo con bounds circunscritos, 3 solapados = 1 polígono / hueco de 40 m = 2, 100 encadenados = 1 bajo el timeout por defecto, degenerados, spy que lanza) + outline de A (3 anillos), B (1), C (null).
- **Verde en ese commit:** `npx vitest run src/data` 49 ok; `npm run test:ui` 192 ok (con `--maxWorkers=3`, ver "Entorno"); `npm test` 52 ok / 5 skipped / 0 fail.

### Task 3: D-20 de punta a punta — `26eda22`

- `model.js`: fuera `cover`, `maxRadius`, `COVER` y las seis columnas de la lista blanca (obras = `uuid, name, recorrido_uuid, visibility`).
- `layers.js`: la obra es `L.polygon(o.outline.polygons, …)` (`pane: 'cover'`, `className: 'cg-cover'`, `cgKind: 'cover'`, mismos estilos y mismo `makeInteractive` `Obra {nombre}`); una obra sin `outline` se salta entera. `outlineBounds(L, obras)` reemplaza a `coverBounds` (sin agrandar por radio: H4 resuelto); `targetBounds` lo usa para obra y recorrido.
- `MapView.jsx`: `outlineBounds` en el efecto de `fitKey` (padding 70/24 px y `maxZoom: 18` sin cambios). `buildView.js`: Cobertura medida sobre `outline.bounds`, `COVER_HINT` = `Ancho × alto del contorno: incluye el radio de los triggers.`. `Obras.jsx`: mini-mapa si `current.outline`. `measure-pull.mjs`: borrada sólo la métrica `obras_con_triggers_y_cobertura_null`.
- Specs: `layers.spec.js` (helper `withTriggerOnC`, capa `L.Polygon` por obra con estilos de `styleFor`, `outlineBounds` contiene los círculos completos de A, obra sin contorno no dibuja nada), `model.spec.js` (obra sin `cover`/`maxRadius`; lista blanca de 4 columnas), `buildView.spec.js` (ancho del contorno >= 364 m > 340 m entre centros extremos, `title` nuevo). E2E nuevo **"contorno = unión"**: el `d` del trazo de `Obra Aurora` tiene exactamente 3 subtrazos `M` y el de B 1.
- Grep del criterio de aceptación: 0 coincidencias; `L.polygon(` x1, `outlineBounds` x2 en `MapView.jsx`.
- **Bundle (`npm run build`):** antes JS 427,38 kB / 131,28 kB gzip; después de Task 3 455,08 / 140,08; al cierre del plan 455,99 / 140,53 (CSS 40,23 kB).

### Task 4: D-21 etiquetas por zoom — `52e7988`

- `layers.js`: `LABELS_PATH_ZOOM = 16` y `LABELS_PORTAL_ZOOM = 17` ([DEFAULT] comentado). `buildLayers` arma `labels = { group, cands }` con un candidato por obra con contorno (centro de `outline.bounds`), por path route con triggers (trigger de índice `floor((n-1)/2)`) y por portal con trigger; cada uno un `L.marker` con `divIcon` cuyo `span` se crea con `textContent` + `aria-hidden="true"`, `interactive: false`, `keyboard: false`, ancho estimado `min(200, chars × 9)`.
- `syncLabels(state, { zoom, capas, project, size })`: nivel obra (casilla Cobertura) si `zoom < 16`; si no, path (Paths) y además portal (Portales) si `zoom >= 17`; descarta lo que cae fuera de `size`; greedy sin pisarse (cajas `w × 18 px`, 4 px de margen, la de portal desplazada hacia arriba); diff del grupo. `ponytail:` con el techo (ancho por caracteres, O(n²) sobre <= 160 candidatos; upgrade = medir el DOM o índice espacial). El grupo `labels` queda siempre en el mapa (`syncGroups` ya no lo ata a una casilla).
- `MapView.jsx`: `syncLabels` en `refresh()` (corre en `moveend`, cambios de casillas, modo y selección). `map.css`: `.map-label` / `.map-label span` (13 px, peso 400, `max-width: 200px`, elipsis), `.obra-label` mayúscula, `.path-label` en `--azure-soft`, `.portal-label` en `--c-mint` sobre el punto.
- Specs: 5 casos en `layers.spec.js` (umbrales 16/17, candidatos y texto/aria-hidden/teclado, `HTML_NAME` como texto sin `img`, niveles por zoom 14-17, casillas, superposición y viewport). E2E: "etiquetas por zoom" (nunca conviven obra y path, `pointer-events: none` computado, `aria-hidden`, ningún `tabindex`), "etiqueta larga recortada" (<= 200,5 px, `text-overflow: ellipsis`, `scrollWidth > clientWidth`) y Paths apagada = 0 `.path-label`.

## Deviations from Plan

**1. [Rule 3 - Blocking] `e2e/obras.spec.js:45` (selector, no comportamiento).** `d.getByText('Ruta A')` resolvía a 2 elementos en modo estricto porque el mini-mapa del detalle ahora muestra la etiqueta `Ruta A` (aria-hidden). Se cambió a `d.getByRole('button', { name: /^Ruta A/ })`. El plan pedía que `obras.spec.js` siguiera verde "sin cambios" para el mini-mapa sin elementos focuseables: esa propiedad se mantiene (los tests de mini-mapa pasan sin tocarlos); sólo se desambiguó el selector de la fila de la lista. Commit `52e7988`.

**2. [Rule 1 - ajuste de test] "path con 0 triggers" en `layers.spec.js`.** Con el helper nuevo (`withTriggerOnC`) la obra C ya tiene contorno, así que el caso vacía los triggers de la Ruta C después de armar el modelo para seguir probando "path vacío no produce capas"; se agregó aparte el caso "obra sin contorno no dibuja nada". Commit `26eda22`.

**3. [Alcance] Test del "Zoom out" en el E2E de etiquetas por zoom.** Dos obras a 55 m (A y B) se pisan a zoom 15, así que al alejar sólo queda la de A; el test exige "alguna `.obra-label`" (como el plan), y la chequea sobre el `span` (el contenedor `.obra-label` mide 0 × 0 y Playwright lo da por oculto).

Ningún cambio de arquitectura (Regla 4); `web/api` sin cambios.

## Entorno / verificaciones

- **`npm run test:ui` es sensible a la carga de esta máquina:** con todos los workers, 2-3 tests de `jsdom` (lentos al arrancar, p. ej. `SyncPill`, `Obras`, `SidePanel`) superaron el timeout de 5 s en las corridas con el worktree recién creado; los mismos archivos pasan solos y la suite completa pasa con `npx vitest run --maxWorkers=3`. Los fallos rotaron entre corridas y no son del código de este plan; no se tocó el timeout. Las cuentas finales (199 ok / 16 archivos) son con `--maxWorkers=3`.
- **Suite final:** `vitest` 199 ok; `npx playwright test -c e2e/playwright.config.js` (toda la suite) 60 ok; `npm test` 52 ok / 5 skipped / 0 fail; `npm run build` OK.
- No se lanzó ningún navegador ni servidor fuera de `npx playwright test`; no queda proceso mío corriendo. No se leyó ningún `.env*`. No se tocó STATE/ROADMAP/REQUIREMENTS.

## Threat Flags

Ninguno nuevo. T-12-SC (compuerta humana antes de instalar), T-12-38 (descartes de datos degenerados + respaldo si la unión lanza, con spec), T-12-39 (`textContent` + `aria-hidden`, caso `HTML_NAME`) y T-12-40 (la lista blanca sólo se achicó; los tests "⊆ TABLE_SPEC" y "sensibles fuera" siguen verdes) quedaron mitigados como el plan indicaba.

## Known Stubs

Ninguno.

## Self-Check: PASSED

Archivos verificados: `web/src/data/geometry.js` (`polygonClipping.union(`), `web/src/map/layers.js` (`LABELS_PORTAL_ZOOM`, `syncLabels`, `outlineBounds`), `web/package.json` (`"polygon-clipping": "0.15.7"`). Commits `de62021`, `a5ed3cb`, `26eda22`, `52e7988` presentes en `git log f9ece0e..HEAD`.
