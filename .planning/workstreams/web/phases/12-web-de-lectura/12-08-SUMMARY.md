---
phase: 12-web-de-lectura
plan: 08
subsystem: web-map
tags: [leaflet, circles-mode, keyboard, roving-tabindex, a11y, focus-return, WEB-01, WEB-05, tracer]

requires:
  - phase: 12-03
    provides: "CIRCLES_MIN_ZOOM = 16 y CIRCLES_MAX = 600 medidos con datos reales (OI-02), fijados en 12-UI-SPEC R6"
  - phase: 12-05
    provides: "SidePanel con onClose / Esc, MapPage con sel / x en la URL, buildView de trigger (index, Orden)"
  - phase: 12-07
    provides: "MapView / layers.js / MapBar, pane `circles` (z 450), applySelection, fitKey / fitTarget"
provides:
  - "Segmentado Corredor / Círculos en MapBar y `?modo=circ` por replaceState (no entra en fitKey)"
  - "layers.js: CIRCLES_MIN_ZOOM, CIRCLES_MAX, syncCircles (diff por uuid + tope), clearCircles, roving tabindex, flechas"
  - "MapView: prop `modo`, refresh() único (corredor <-> círculos, recorte por viewport) y pista `Acercá el mapa para ver los círculos.`"
  - "MapPage: foco devuelto al elemento del mapa al cerrar el panel"
  - "e2e/teclado.spec.js (4 tests) y 2 tests de modo Círculos en e2e/mapa.spec.js"
affects: [12-09, 12-10]

tech-stack:
  added: []
  patterns:
    - "Un solo `refresh()` en MapView lee refs (modo, capas, sel) y lo llaman moveend, [capas], [modo], [sel] y la reconstrucción de capas: ningún efecto decide por su cuenta qué grupo va en el mapa"
    - "Estado de círculos fuera de React: `{ group, byUuid: Map<uuid, L.Circle>, onSelect, pendingFocus }` creado por buildLayers"
    - "tabindex de capas vectoriales en `layer.options.cgTab` (el nodo SVG se recrea al apagar/prender la capa)"
    - "Foco programático diferido: la flecha sólo anota `pendingFocus` y selecciona; el sync posterior (cuando el círculo existe) enfoca"

key-files:
  created:
    - web/e2e/teclado.spec.js
  modified:
    - web/src/map/layers.js
    - web/src/map/layers.spec.js
    - web/src/map/MapView.jsx
    - web/src/map/MapBar.jsx
    - web/src/map/map.css
    - web/src/pages/MapPage.jsx
    - web/e2e/mapa.spec.js

key-decisions:
  - "Los números de R6 no se re-derivan: CIRCLES_MIN_ZOOM = 16 y CIRCLES_MAX = 600 se importan como constantes con el comentario de la medición de 12-03"
  - "El modo Círculos reemplaza SOLO el corredor (con zoom >= 16); línea, huecos ámbar, portales y cobertura se dibujan siempre"
  - "Los círculos son del casillero de capa `Paths`: apagar Paths los quita junto con la línea y los huecos"
  - "Un tab stop por path: el trigger seleccionado o, si no hay uno en ese path, el de menor `index` entre los dibujados"

requirements: [WEB-01, WEB-05]
requirements-completed: [WEB-01, WEB-05]

status: complete
commits: 2
plan_head_before: c7fdeb112f78943f0a61d35b73e709cafaaa21bf
plan_head_after: c46c829065bffb2370e931c739601fb65bfb46e3
actuals:
  tokens: 8700   # chars/4 sobre el diff real de web/ (34 843 chars; ~60 % son specs)
  tasks: 2
  commits: 2

duration: ~60min
completed: 2026-10-07
---

# Phase 12 Plan 08: Modo Círculos (D-17) y teclado del mapa (R9) Summary

**El mapa tiene ahora el modo Círculos (cada trigger como `L.circle` en metros, sólo con zoom >= 16, recortado al viewport +20 % y con tope de 600) y se opera entero con teclado: roving tabindex entre triggers con flechas, Enter/Espacio, foco visible en SVG y foco devuelto al elemento del mapa al cerrar el panel.**

## Decisiones que afectan el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras no se resuelva |
|----------|---------|--------------------------|--------------------------------|
| **Los círculos son un grupo propio (`circles`, pane z 450) que `syncCircles` mantiene por diff sobre un `Map<uuid, L.Circle>`; se crean al entrar al viewport ampliado 20 % y se destruyen al salir, salvo el seleccionado y el enfocado** | Datos reales: máx 35 triggers por obra (12-03), pero el diff acota también un servidor con cientos; el seleccionado/enfocado nunca se destruyen (Pitfall 7: el foco de teclado sobrevive a panear) | Dibujar todos los triggers de golpe (render de miles de SVG, T-12-29); Canvas (no tiene nodos focuseables, R9) | `CIRCLES_MAX = 600` nunca actúa con datos reales: su rama (sólo el path activo) sólo la ejerce el spec. Si el path activo solo superara el tope se dibuja entero (comentado como `ponytail:`) |
| **Roving tabindex: un tab stop por path** (el trigger seleccionado o el de menor `index` dibujado); flechas mueven selección y foco | Es lo que fija la UI-SPEC (tabla Mapa) y evita 30+ tab stops por path (E1 backstop `tab-order`) | `tabindex=0` en todos (cientos de Tab); un solo tab stop global (rompe "Tab llega a paths") | Con varios paths en pantalla hay un tab stop por path en modo Círculos (35 círculos -> 2 stops en las fixtures). No validado con un usuario real de lector de pantalla |
| **El foco se devuelve al último elemento vectorial/marcador del mapa que tuvo foco (`focusin` en `.mapwrap`), no al "que originó la selección"** | Cubre clic con mouse (Chromium enfoca el nodo SVG con `tabindex`), Enter y flechas con un único mecanismo, sin pasar el elemento por `onSelect` | Pasar el nodo origen por la cadena `onSelect(sel, el)` (toca layers, MapView y MapPage por un caso que `focusin` ya cubre) | Si el usuario enfocó un elemento del mapa, abrió otro panel desde un enlace del propio panel y luego lo cierra, el foco vuelve al último elemento del mapa enfocado (no necesariamente el que muestra el panel). Si el nodo ya no está en el DOM (pull con modelo nuevo) no se devuelve nada |

#### Secuencia — flecha derecha sobre un trigger en modo Círculos

```mermaid
sequenceDiagram
  autonumber
  participant U as Usuario (foco en círculo i)
  participant C as L.Circle i (keydown)
  participant S as state.circles
  participant P as MapPage (onSelect, setParams)
  participant V as MapView (efecto [sel])
  participant Y as syncCircles

  U->>C: ArrowRight
  C->>C: preventDefault (no scrollea)
  C->>S: pendingFocus = trigger i+1 (de t.path.triggers)
  C->>P: onSelect("trigger:" + uuid i+1)
  P-->>V: sel nuevo (replaceState, panel muestra "Orden i+1 de n")
  V->>V: applySelection (sólo setStyle)
  V->>Y: refresh() -> syncCircles(sel, bounds)
  Y->>Y: keep = viewport+20 % + seleccionado + enfocado (nunca se destruyen)
  Y->>Y: cgTab 0 sólo en el seleccionado de su path, -1 el resto
  Y->>S: byUuid.get(pendingFocus).getElement().focus(); pendingFocus = null
```

## Performance

- **Duración:** ~60 min
- **Tareas:** 2/2 (Task 1 tracer, Task 2 tdd)
- **Archivos:** 1 creado, 7 modificados bajo `web/`; `web/api/`, `package.json` y el lockfile sin diff (sin dependencias nuevas)

## Accomplishments

- Tracer verificado de punta a punta antes de seguir (Playwright, tiles mockeados): Círculos activo + 4 zoom-out -> pista y 0 círculos; elegir `Ruta A` en el panel encuadra el path y aparecen sus 32 círculos (35 en total con los 3 de la ruta B, que cae dentro del viewport); el hueco ámbar sigue; clic abre `Trigger 005` con `5 de 32`; volver a Corredor quita los círculos y `modo` sale de la URL.
- `?modo=circ` no toca `fitKey` (D-02): test E2E que alterna modos y compara la posición de la cobertura (< 2 px).
- `syncCircles` cubierto en jsdom: sólo los de adentro de los bounds ampliados, nunca quita el seleccionado ni el enfocado, tope (sólo el path resaltado/seleccionado), un tab stop por path, `role=button` + `aria-label` `Trigger {i} de {n}, radio {r} m`, las 4 flechas, extremos sin efecto, Enter selecciona, `pendingFocus` se consume.
- Teclado E2E (R9): Tab llega al portal de la obra A y Enter abre `Portal A`; en modo Círculos Tab llega al trigger activo, `ArrowRight` -> `Orden 2 de 32`, recorre los 32 en orden con `ArrowDown`, los extremos no hacen nada, y Tab sale del path (sin trampa de foco); Esc expandido -> compacto -> cerrado devuelve el foco a `Obra Obra Aurora`; `Cerrar panel` devuelve el foco al círculo 2.

## Verification evidence

- `cd web && npm run test:ui`: 161 tests OK (23 en `layers.spec.js`, 8 nuevos del modo Círculos).
- `cd web && npm run test:e2e` (config estándar): 44 de 44 OK (`mapa.spec.js` 15, `teclado.spec.js` 4, más los 25 previos).
- `cd web && npm run build`: OK (JS 419,33 kB / 129,34 kB gzip).
- `grep -n "CIRCLES_MIN_ZOOM" web/src/map/layers.js` = 16, igual que `12-UI-SPEC.md` R6 (`CIRCLES_MIN_ZOOM = 16`, `CIRCLES_MAX = 600`).
- `git diff c7fdeb1 HEAD -- web/api web/package.json web/package-lock.json` vacío. `innerHTML|dangerouslySet` no aparece en `src/map` ni `src/pages`: el label del trigger no lleva nombre (R4) y se escribe con `setAttribute`.

## Task Commits

1. **Task 1: tracer, segmentado + círculos sobre el umbral medido + pista:** `df75d82` (feat)
2. **Task 2: specs de escala/teclado y E2E de teclado:** `c46c829` (feat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reset del branch de arranque del worktree**
- **Found during:** arranque. HEAD era `5b1ac2f`, sin los archivos de la Fase 12.
- **Fix:** `git reset --hard ws/web` (paso sanctioned de arranque; `c7fdeb1`), verificado `layers.js` y `12-03-SUMMARY.md`, y `npm ci`.

### Decisiones de interpretación

- **Reparto de código entre los dos commits:** el recorte por viewport, el tope, el roving tabindex, las flechas y la devolución de foco se escribieron juntos con el tracer porque comparten `syncCircles`, `refresh()` y `MapPage`; el commit 1 los contiene (verificados por los E2E de Task 1), y el commit 2 aporta los specs (`layers.spec.js`, `teclado.spec.js`) que ejercen el contrato de `<behavior>`. El foco visible de Task 2.4 ya lo cubría la regla `.mapview .leaflet-interactive:focus-visible` de 12-07 (los círculos son `path.leaflet-interactive`): no hubo cambio de CSS adicional.
- **Firma de `syncCircles`:** `syncCircles(state, { L, paths, bounds, sel, focusedUuid, max })`. Sin `map` (basta `bounds`, MapView pasa `map.getBounds()` y la función amplía 20 % adentro). `state` es un objeto `{ group, byUuid, onSelect, pendingFocus }` y no un `Map` pelado, porque el diff necesita el grupo y la cola de foco. `focusedUuid` es opcional: por defecto se deduce de `document.activeElement`. Se agregó `clearCircles(state)` (fuera de modo o bajo el umbral).
- **`buildLayers` devuelve además `circles` y `paths`** (las rutas dibujables); el grupo `circles` entra en `CAPA_OF` bajo `paths`. `syncGroups` recibe un 4.º parámetro `circulos` que esconde el corredor y muestra los círculos.
- **Un path con 1 trigger** conserva su `L.circle` interactivo del grupo `lines` (12-07) y, en modo Círculos, también tiene el círculo de trigger encima: dos capas coincidentes. Con datos reales no es un caso observado.
- **Tracer: 35 círculos, no 32.** Con las fixtures la ruta B (3 triggers) queda dentro del viewport; el E2E cuenta 35 en total y 32 con `de 32`.
- **Zoom-out en el E2E con espera de 400 ms:** Leaflet ignora el segundo clic del control mientras anima el zoom; sin la espera la pista no aparecía.
- **No hay E2E de recorte en navegador:** con el viewport de Playwright el path entero cabe en pantalla, así que el recorte y la conservación del seleccionado/enfocado sólo están cubiertos en jsdom (`layers.spec.js`), con bounds simulados.

## Issues Encountered

- Un helper de test llamado `key` pisaba la clave `key` del objeto `originalEvent` (`{ key, preventDefault }` tomaba la función). Corregido a `key: k`.
- La primera corrida de Playwright en frío usa un `--timeout=60000` pasado por línea de comandos; los tests individuales tardan 1-5 s.

## Auth gates

Ninguno.

## Known Stubs

Ninguno.

## Human check pendiente (Task 2 `<human-check>`)

En el Preview final con el path real más largo (OI-02, 35 triggers): el modo Círculos con zoom alto se mueve fluido; Tab y flechas recorren los triggers en orden sin trampas de foco; Esc devuelve el foco al mapa. También sigue pendiente la comprobación humana de 12-07 (legibilidad de los tiles oscurecidos, OI-07).

## Threat Flags

Ninguna superficie nueva fuera del `<threat_model>`.

- T-12-29 (render de miles de círculos): mitigada. Umbral de zoom 16 + recorte por viewport ampliado 20 % + tope 600, con la rama del tope cubierta por spec. Con datos reales el tope no actúa (máx 35).
- T-12-30 (aria-label desde el servidor): mitigada. `setAttribute` (texto); el label del trigger sólo lleva posición, total y radio, nunca nombre (R4).
- T-12-SC (npm installs): sin instalaciones; `package.json` y lockfile sin cambios.

## Next Phase Readiness

12-09 (mini-mapa) reutiliza `MapView`: la prop `modo` tiene default `'corr'`, así que el mini-mapa no necesita pasarla; si llegara a montar círculos habría que apagar el efecto `moveend` para el modo `mini`. `makeInteractive` ahora lee `options.cgTab` (default 0), por lo que el resto de las capas siguen teniendo un tab stop. 12-10 puede reutilizar `tabTo` de `teclado.spec.js` (extraerlo a un helper si lo necesita).

---
*Phase: 12-web-de-lectura*
*Completed: 2026-10-07*

## Self-Check: PASSED

- Archivos verificados: `web/e2e/teclado.spec.js`, `web/src/map/layers.js` (`syncCircles`, `clearCircles`, `CIRCLES_MIN_ZOOM`), `web/src/map/MapView.jsx`, `web/src/map/MapBar.jsx`, `web/src/pages/MapPage.jsx`.
- Commits verificados en `git log`: `df75d82`, `c46c829`; `git rev-list --count c7fdeb1..HEAD` = 2 antes de este SUMMARY.
