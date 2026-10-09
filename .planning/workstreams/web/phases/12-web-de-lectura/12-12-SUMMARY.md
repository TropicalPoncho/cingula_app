---
phase: 12-web-de-lectura
plan: 12
subsystem: web-map-filters-panel-audit
tags: [popover, menu, chip, a11y, ponytail-audit, D-22, D-23, WEB-01, WEB-04, WEB-05]

requires:
  - phase: 12-11
    provides: "contorno de obra (D-20) y etiquetas por zoom (D-21)"
provides:
  - "web/src/app/usePopover.js: único popover no modal (Esc en captura + preventDefault, clic afuera, foco de vuelta), usado por SyncPill y MapBar"
  - "MapBar: botón `Capas y filtros` + tarjeta no modal + chip de recorrido (D-22)"
  - "Panel: facts `Tipo` / `Tolerancia` sin superposición y `Volver a …` como flecha de 44 px (D-23)"
  - "UI-SPEC / VALIDATION / ADR pendiente enmendados por D-20..D-23"
affects: [12-10]

status: complete
commits: 5   # MEASURED: git rev-list --count 26215fa..HEAD (5 commits de tarea; este SUMMARY se commitea aparte)
plan_head_before: 26215fad28fff92e7068755efb72567a25547cea
plan_head_after: 6f21173e71d5ad39fd046e9692fc8d2475bc0ae5
actuals:
  tokens: 28829   # chars/4 sobre el diff real (115 315 chars)
  tasks: 3
  commits: 5
requirements: [WEB-01, WEB-04, WEB-05]
requirements-completed: []   # lo cierra el orquestador
---

# Phase 12 Plan 12: Menú Capas y filtros, panel D-23 y auditoría ponytail Summary

**Los filtros del mapa viven detrás de un botón de 44 px con chip honesto del recorrido activo (un solo hook `usePopover` para la pill y el menú, Esc que nunca cierra lo que no corresponde), el panel nombra `Tipo`/`Tolerancia` sin pisar valores y vuelve con una flecha, el código post-UAT pasó la auditoría ponytail sin perder controles, y UI-SPEC / VALIDATION / ADR reflejan D-20..D-23.**

## Decisión que afecta el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras no se valide |
|----------|---------|--------------------------|------------------------------|
| **D-22 supera la parte "selector fijo arriba" de D-04** (la interacción de D-04/D-10 no cambia). Los popovers no modales de la SPA usan UN hook, `usePopover`: Esc en captura + `preventDefault` (el Esc del panel ya ignora `defaultPrevented`), clic afuera, foco de vuelta al botón. **Chip también para `Sin recorrido`** [DEFAULT]. | Decisión del usuario en el UAT. Dos consumidores del mismo patrón: extraerlo elimina el duplicado y corrige en los dos el conflicto de Esc (antes, con el foco en la pill y el panel abierto, un Esc cerraba ambos). `Sin recorrido` esconde obras: sin chip el mapa filtraría en silencio. | Menú inline duplicando el efecto; `<dialog>` modal (atrapa el foco; D-22 pide no modal); chip sólo para uuid. | Bajo. La regla < 900 px de la tarjeta (ancho completo, termina antes de la hoja inferior) es [DEFAULT] sin validar y se suma a OI-05. `SyncPill.spec.jsx` pasó sin cambios. |

## Tasks

### Task 1 (tracer): menú `Capas y filtros` — `09e36e2`
- `usePopover.js` nuevo; `SyncPill.jsx` lo usa sin cambiar su JSX ni su comportamiento (`git diff` de `SyncPill.spec.jsx` vacío).
- `MapBar.jsx`: mismo contrato de props. Botón (`Layers`, `aria-haspopup`, `aria-expanded`, `aria-controls`), tarjeta `role=dialog` con los tres grupos (mismos controles nativos), chip con el nombre **del modelo** (nunca el texto de la URL) y × `Quitar filtro de recorrido` (44 px) que llama `onRec('')` y enfoca el botón. `MapPage` renderiza `MapBar` antes de `MapView` (primer control del mapa en el orden de Tab).
- `map.css`: reglas de la barra anterior borradas; `.mbtn`, `.mchip`, `.mmenu`; `< 900 px` tarjeta `fixed` de ancho completo.
- Tests: `MapBar.spec.jsx` (6: atributos y contenido, Esc/clic afuera + foco, Esc con panel abierto cierra sólo la tarjeta, elegir recorrido → chip → × cierra el panel y enfoca el botón, `?rec=none`, `?rec=<img …>` sin chip y sin `img[src="x"]`). E2E (`mapa.spec.js` + helper en `journey.spec.js`): D-03, D-04/D-10 con chip, chip ×, enlace desde Obras, Esc/clic afuera, aislamiento de teclas (<2 px de movimiento, tarjeta y panel siguen), **tab-order real** (primer foco dentro de `.mapwrap` = `Capas y filtros`), tarjeta junto al panel a 1280 px y de ancho completo / sobre la hoja a 800 px.
- Verde: 29 E2E (mapa + journey + teclado), Vitest, build.

### Task 2: D-23 — `8b9d38e`
- `pathView`: `Tipo` y `Tolerancia` (valores y `mono` sin cambio). `.fact` = `124px minmax(0, 1fr)` con `overflow-wrap: anywhere` en la etiqueta. `EntityDetail`: botón `.ib` con sólo `ArrowLeft` (20 px) en la fila de la etiqueta de tipo, `aria-label` y `title` `Volver a {nombre}`; el botón de texto se borró. Mismo componente en compacto, expandido y detalle de Obras.
- Tests: `buildView.spec.js`, `widgets.spec.jsx` (path/portal/trigger × compacto/expandido, sin texto visible, misma fila que la etiqueta, `onSelect(back.sel)`, recorrido y obra sin botón), E2E de 380 px (botón ≥ 43,5 px, centro a ≤ 12 px de la etiqueta `PATH`, ningún `.fact dt` desborda, ni con 40 letras sin cortes; `&x=1` conserva el botón). `Obras.spec`, `SidePanel.spec`, `panel.spec`, `obras.spec` verdes sin cambios.

**Aviso D-23 (botón "chico"):** se interpreta como chico **a la vista** (sólo un ícono de 20 px, sin texto ni fondo) con área de toque de 44 px (`--touch-min`, regla de accesibilidad de la UI-SPEC). Si el usuario lo quiere más chico también en área, es una decisión explícita en la compuerta de 12-10 (ítem (j)).

### Task 3: auditoría ponytail + enmiendas — `c152704`, `a2cb722`, `6f21173`
Skill `ponytail:ponytail-audit` acotada a los archivos web de 12-11 y 12-12 (sin `web/api`). **Corrido primero; los documentos después.**

| Chequeo | Resultado |
|---------|-----------|
| A. Dependencias | `dependencies` = sólo `@neondatabase/serverless`; `devDependencies` = 13 exactas (el `node -e` del plan sale 0); `polygon-clipping` tiene un único importador (`web/src/data/geometry.js`; el otro archivo que lo nombra es su spec) |
| B. Código muerto | grep de la caja del servidor (`cover_`, `maxRadius`, `coverBounds`, `o.cover`) = **0**. Clases de `panel.css` y `map.css`: ninguna sin uso (las tres que un script marcó, `obra-label`/`path-label`/`portal-label`, se usan por plantilla `${level}-label` en `layers.js`: se conservan) |
| C. Un popover | `pointerdown` sólo en `usePopover.js`; dos consumidores (`SyncPill`, `MapBar`) |
| D. Etiquetas | sólo `LABELS_PATH_ZOOM`, `LABELS_PORTAL_ZOOM` y `syncLabels`; sin objetos de configuración |
| E. Geometría | una sola llamada `polygonClipping.union`; comentarios `ponytail:` con techo en `OUTLINE_VERTICES`, en el respaldo de la unión, en la regla greedy de etiquetas y en `usePopover` |
| F. Tipografía | las reglas nuevas sólo usan `--fs-xs/sm/md` (13/15/20) y peso 400 |
| G. `web/api` | `git diff f9ece0e -- web/api` y `git diff a82b090 -- web/api` vacíos |
| H. Router | 57 líneas (≤ 60), sin cambios |
| K. No se toca | `USED_COLUMNS` (4 columnas en obras) y su test, `parseSel`, manejo de 401 y guarda anti-bucle de `pull.js`, `vercel.json` (sin diff), ARIA/tabindex del contorno / roving / etiquetas `aria-hidden` / `aria-expanded` + `aria-haspopup` del menú y la pill / `aria-label` del × y la flecha, estados de error, `try/catch` de la unión, Esc en captura con `preventDefault`, `rec` validado contra el modelo antes del chip; sin `innerHTML`/`dangerouslySetInnerHTML` en `src/` (T-12-42): **intactos** |

**Qué se simplificó o borró** (`c152704`): `circlesOutline(circles, vertices = OUTLINE_VERTICES)` perdía un parámetro que ningún llamador pasa → ahora usa la constante (yagni). Nada más que cortar: el resto del alcance es mínimo y todo lo demás tiene consumidor real. **Hallazgo propio corregido (`a2cb722`):** la fila de la flecha de Volver reusaba la clase `.phead`, que ya estiliza la cabecera del panel (borde inferior, padding): se renombró a `.trow` (código, specs y UI-SPEC). Los tests no lo detectaban (verificaban geometría, no el estilo heredado).

Alcance de la auditoría vs `<files>`: el diff contra el commit "plan post-UAT adjustments" (`a82b090`) también lista `web/package.json`, `web/package-lock.json` y `web/e2e/obras.spec.js` (de 12-11: instalación aprobada y selector desambiguado, ver 12-11-SUMMARY). No se tocó ninguno en 12-12; no hay desvío.

**Enmiendas (`6f21173`):** `12-UI-SPEC.md` (nota de enmienda; R2 superado; R15..R18; Component Inventory; Responsive; Volver; Contenido por tipo; Controles reescrito al menú + chip; Auto-ajuste; Capas y reglas incl. filas de etiquetas de obra/path/portal; Accesibilidad y tab-order real; Copywriting; OI-11 y OI-12; H4 resuelto; UI Considerations; Registry Safety con `polygon-clipping` + transitivas; Checker Sign-Off honesto: **la enmienda NO pasó otra vez por gsd-ui-checker**), `12-VALIDATION.md` (filas 12-11-01..04 y 12-12-01..03 con el Status real; mapa WEB-01/04/05; ítems manuales (g)-(j); `nyquist_compliant: false` y `status: draft` sin tocar), `12-ADR-PUBLISH-PENDING.md` (segundo ADR "Cobertura de obra calculada en la web como unión de los círculos de sus triggers", con diagrama Mermaid; estado aceptado, pendiente de la compuerta; se publica junto al otro en el paso 11).

**Chequeo de desvío doc-código (paso 7):** `OUTLINE_VERTICES = 24`, `LABELS_PATH_ZOOM = 16`, `LABELS_PORTAL_ZOOM = 17`, `outlineBounds`, `syncLabels`, `usePopover`, `Capas y filtros`, `Quitar filtro de recorrido`, `Tipo`, `Tolerancia`, `Ancho × alto del contorno: incluye el radio de los triggers.`, `Volver a`, `Sin cobertura todavía`, anclaje de la etiqueta de path (`floor((n-1)/2)`), ancho de etiqueta `min(200, chars × 9)`, `LABEL_H = 18`/`LABEL_GAP = 4`, área de 44 px del portal: **todos existen tal cual en `web/src`**. Una diferencia hallada y corregida en el documento: el nombre de clase de la fila de Volver (`.phead` → `.trow`, ver arriba; el código mandó).

## Deviations from Plan

**1. [Rule 3 - Blocking] z-index del menú sobre el velo del mapa.** El plan decía "z-index por encima del mapa"; el velo de estado (`.mapstate`, z 3) cubría el botón con el pull fallido, y el E2E "primer pull fallido" necesita abrir la tarjeta para ver el select deshabilitado. `.mapbar` quedó en z-index 4 (sobre el velo y la leyenda). Commit `09e36e2`.

**2. [Rule 1] `.phead` duplicado** (ver Task 3). Commit `a2cb722`.

**3. [Alcance de test]** "sin ningún `img`" del plan se acotó a `img[src="x"]` en `MapBar.spec.jsx`: Leaflet monta `<img class="leaflet-tile">` reales en jsdom.

**4. [Entorno]** `npm run test:ui` se corrió con `npx vitest run --maxWorkers=3` (conocido de 12-11); no se tocaron timeouts.

Ningún cambio de arquitectura (Regla 4); `web/api` sin cambios.

## Verificación final

`npm test` 52 ok / 5 skipped / 0 fail; `npx vitest run --maxWorkers=3` 206 ok (17 archivos); `npx playwright test -c e2e/playwright.config.js` (suite completa) **67 ok**; `npm run build` OK (JS 457,4 kB, gzip 140,95 kB); `git diff f9ece0e -- web/api` vacío. Browsers sólo vía `npx playwright test`; no queda ningún proceso mío corriendo. No se leyó ningún `.env*`. No se tocó STATE/ROADMAP/REQUIREMENTS.

## Para la compuerta humana de 12-10 (próxima acción: retomar 12-10 Task 3)

Ítems manuales nuevos en `12-VALIDATION.md`:
- **(g)** umbrales de etiquetas 16/17 con datos reales (OI-11).
- **(h)** aspecto del contorno de las 74 obras reales y costo de la unión.
- **(i)** menú y chip a 800 px (OI-05).
- **(j)** la flecha se entiende como "volver" (y decisión sobre el área de 44 px).

Más: publicar los dos ADR en Notion (paso 11) y revisar la elección de `polygon-clipping` (OI-12).

## Threat Flags

Ninguno nuevo. T-12-41 (chip sólo con `rec` validado contra el modelo, caso `?rec=<img …>`), T-12-42 (atributos por JSX, sin `innerHTML`), T-12-43 (chequeo K + suite completa), T-12-44 (Esc en captura + `preventDefault`, caso en `MapBar.spec` y E2E) y T-12-SC (no se instaló nada) quedaron mitigados.

## Known Stubs

Ninguno.

## Self-Check: PASSED

Archivos: `web/src/app/usePopover.js`, `web/src/map/MapBar.spec.jsx`, `12-UI-SPEC.md` (`Quitar filtro de recorrido`, `OI-11`), `12-VALIDATION.md` (`12-12-03`), `12-ADR-PUBLISH-PENDING.md` (`polygon-clipping`) presentes. Commits `09e36e2`, `8b9d38e`, `c152704`, `a2cb722`, `6f21173` presentes en `git log 26215fa..HEAD`.
