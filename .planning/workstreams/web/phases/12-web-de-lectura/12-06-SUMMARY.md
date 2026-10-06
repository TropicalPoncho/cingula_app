---
phase: 12-web-de-lectura
plan: 06
subsystem: web-panel
tags: [audio-card, coverage-strip, portal-table, trigger-neighbors, a11y, WEB-05, WEB-06, tracer]

requires:
  - phase: 12-05
    provides: "buildView (audio, strip, table, note, neighbors ya calculados y testeados), SidePanel, EntityDetail genérico"
  - phase: 12-02
    provides: "modelo derivado (gaps, portales por obra), fixtures y mockApi"
provides:
  - "AudioCard: tarjeta de audio de 3 estados (sin audio / sin archivo todavía / archivo en el servidor) con slot vacío reservado para el reproductor de la Fase 13"
  - "CoverageStrip: tira de cobertura con huecos ámbar punteados, role=img y nota de huecos"
  - "PortalTable: tabla Portales de la obra con th scope=col y nombre como botón"
  - "EntityDetail con la columna derecha del expandido completa, nota fija y Vecinos en el path"
affects: [12-07, 12-08, 12-09, 12-10, 13]

tech-stack:
  added: []
  patterns:
    - "Los widgets reciben el dato ya calculado por buildView y no calculan nada: la lógica sigue testeada sin DOM"
    - "Un único componente Row para las listas y los vecinos del trigger"

key-files:
  created:
    - web/src/panel/AudioCard.jsx
    - web/src/panel/AudioCard.spec.jsx
    - web/src/panel/CoverageStrip.jsx
    - web/src/panel/PortalTable.jsx
    - web/src/panel/widgets.spec.jsx
  modified:
    - web/src/panel/EntityDetail.jsx
    - web/src/panel/panel.css
    - web/e2e/panel.spec.js

key-decisions:
  - "El contrato visual con la Fase 13 queda fijado en AudioCard: el estado `file` renderiza `div.player-slot` vacío (aria-hidden, alto 40 px, sin controles)"
  - "En el expandido de un path la tabla Portales de la obra reemplaza a la lista del mismo título; en compacto queda la lista"
  - "La nota fija del trigger, la nota de obra sin cobertura y Vecinos en el path se ven en compacto y expandido"

requirements-completed: [WEB-06, WEB-05]

status: complete
commits: 2
plan_head_before: 58e88c9cac5caaaec37278fbf63666a69153c159
plan_head_after: 46d23ff9a1d74e5f2114c2f8dcbd938d4c87f262
actuals:
  tokens: 6200   # chars/4 sobre el diff real de web/ (24 781 chars; incluye ~45 % de specs)
  tasks: 2
  commits: 2

duration: ~35min
completed: 2026-10-06
---

# Phase 12 Plan 06: Audio inline, tira de cobertura, tabla de portales y vecinos del trigger Summary

**El detalle de path, portal y trigger muestra ahora la tarjeta de audio de 3 estados, la tira de huecos, la tabla Portales de la obra, la nota fija y los vecinos, todo desde los datos que `buildView` ya calculaba; no hay ningún listado propio de audios (D-11).**

## Decisiones que afectan el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras no se resuelva |
|----------|---------|--------------------------|--------------------------------|
| **`AudioCard` fija el contrato de UI con la Fase 13: el estado `file` termina en un `div.player-slot` vacío (`aria-hidden`, 40 px de alto, sin botón ni barras)**; el estado `nofile` es el bloque ámbar `Sin archivo todavía` | STOR-04 reproduce en ese slot sin tocar el resto de la tarjeta; el prototipo traía barras decorativas y un Play falso (R7) y no se copiaron | Dejar un Play deshabilitado (promete algo que no existe); no reservar el espacio (la Fase 13 movería el layout) | Hasta la Fase 13, un audio con archivo muestra un hueco de 40 px sin nada dentro. Es intencional, pero se ve como espacio vacío |
| **La tarjeta sólo recibe `has_file`: la clave de storage y el checksum no existen en el modelo (T-12-23)** | Lista blanca de 12-02; AudioCard no tiene de dónde leerlos | Mostrar un enlace al archivo (necesita URL firmada: Fase 13) | Ninguno en esta fase; la Fase 13 tendrá que obtener la URL por otra vía sin ampliar la lista blanca del modelo |
| **La tabla Portales de la obra reemplaza a la lista del mismo título sólo en el expandido del path** (compacto sigue con la lista de 4 filas + `+N más`) | Es lo que dice la UI-SPEC y evita mostrar el mismo dato dos veces | Mostrar ambas (pregunta abierta de 12-05) | Ninguno; es un filtro de una línea en `EntityDetail` si se prefiere otra cosa |

## Performance

- **Duración:** ~35 min
- **Tareas:** 2/2 (Task 1 tracer, Task 2 auto/tdd)
- **Archivos:** 5 creados, 3 modificados bajo `web/`; `web/api`, `package.json` y el lockfile sin diff; sin dependencias nuevas

## Accomplishments

- Tracer verificado de punta a punta antes de expandir (spec + Playwright en verde): el path de la obra B muestra `Sin archivo todavía` y el portal de la obra A `Archivo en el servidor`, sin botones dentro de la tarjeta.
- `AudioCard` con los 3 estados; un uuid de audio inexistente da el mismo estado que `sin audio asignado`. El portal la muestra bajo la descripción (columna izquierda), el path al principio de la columna derecha.
- `CoverageStrip`: un cuadro azure de 6x20 por trigger, cuadro ámbar punteado de 18x20 por hueco, `flex-wrap`, `role="img"` con `32 triggers, 1 hueco`, nota de huecos (3 + `+N más`, o la nota de solape). Un path con 0 triggers dice `0 triggers` y no dibuja tira.
- `PortalTable`: `th scope="col"`, filas por nombre con `#`, nombre como botón que abre el portal, elipsis + `title`, scroll horizontal dentro de `.pbody`.
- Trigger: nota fija y `Vecinos en el path` (Anterior/Siguiente con `a {d} m`; el primero no tiene Anterior). También se ve ahora la nota de obra sin cobertura que 12-05 dejó sin pintar.

## Verification evidence

- `cd web && npm run test:ui`: 138 tests OK (panel: 65, de los cuales `AudioCard.spec.jsx` 5 y `widgets.spec.jsx` 11 son nuevos).
- `cd web && npx playwright test -c e2e/playwright.config.js`: 25 de 25 OK (11 de `panel.spec.js`, 4 nuevos: audio, tira+tabla+portal, trigger->Siguiente->Volver a; sync y acceso sin cambios).
- `cd web && npm run build`: OK (JS 256,86 kB / 81,02 kB gzip).
- Aceptación por grep: `scope="col"` en `PortalTable.jsx` = 1; `role="img"` en `CoverageStrip.jsx` = 1; sin `dangerouslySetInnerHTML`/`innerHTML` en `web/src/panel/` fuera de specs.
- `git diff 58e88c9 HEAD --stat -- web/api web/package.json web/package-lock.json` vacío.

## Task Commits

1. **Task 1: tracer, tarjeta de audio de 3 estados:** `18bceab` (feat)
2. **Task 2: tira de cobertura, tabla de portales, nota y vecinos del trigger:** `46d23ff` (feat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reset del branch de arranque del worktree**
- **Found during:** arranque. HEAD era `5b1ac2f` (merge del PR #1), sin `web/src/panel/`.
- **Fix:** `git reset --hard ws/web` (`58e88c9`, paso sanctioned de arranque), verificado `web/src/panel/buildView.js`, y `npm ci`.

**2. [Menor] Ledger de commits del plan**
- El protocolo 0c pide persistir `plan_head_before` en el git-dir del worktree; el entorno rechaza el comando compuesto. Se usó el HEAD de arranque (`58e88c9`, registrado arriba) y el conteo medido `git rev-list --count 58e88c9..HEAD` = 2 antes del commit de este SUMMARY.

### Decisiones de interpretación

- **El E2E "path -> portal -> trigger -> Siguiente -> Volver a" son dos tests, no una cadena.** No hay forma de llegar de un portal a un trigger desde el panel (los triggers de un path no se listan; el mapa de 12-07 los hace clickeables). El primer test cubre path -> tabla -> portal sin recargar (el `history.length` no cambia); el segundo entra por deep link al trigger y cubre Siguiente y `Volver a Ruta A`. Cuando 12-07 agregue marcadores se puede encadenar.
- **Nota fija, nota de obra y vecinos también en compacto.** La UI-SPEC los ubica en "sólo expandido / listas"; el trigger casi no tiene contenido en compacto y el plan dice "el panel de trigger muestra...", así que se ven en ambos modos. Un `{note}` y un `<Neighbors>` menos en el bloque compacto si se quiere el criterio estricto.
- **`0 triggers`** se escribe en `EntityDetail` (path sin `view.strip`), no en `buildView`: el hecho `Triggers` sigue valiendo `0`, como ya cubre `buildView.spec`.
- **Encabezado `Cobertura del path`** sobre la tira (etiqueta `.lbl`) para que la sección tenga título; la UI-SPEC no lo nombra.
- **`requirements-completed: [WEB-06, WEB-05]`** (los del plan). WEB-05 queda completo en la UI para path, portal y trigger; falta la comprobación humana en el Preview final (ver Known Stubs). El orquestador puede marcarlo distinto.

## Issues Encountered

- Para el spec de `+2 más` y de `2 huecos` hubo que desplazar bloques de triggers (no uno solo): mover un único trigger crea dos huecos (antes y después).

## Auth gates

Ninguno.

## Known Stubs

- `div.player-slot` vacío en el estado `file` es el espacio reservado intencional del reproductor de la Fase 13 (STOR-04); no hay datos falsos ni placeholders de texto.
- Pendiente de comprobación humana (Task 2, `<human-check>`): en el Preview final con datos reales, abrir el path más largo expandido; la tira envuelve sin desbordar, los huecos se ven en ámbar, la tabla se lee y cada nombre abre su portal. Automatizado: el E2E verifica que el cuerpo del panel no desborda con 32 triggers.

## Threat Flags

Ninguna superficie nueva fuera del `<threat_model>`.

- T-12-23 (clave de storage / checksum): mitigada. `AudioCard` sólo recibe metadata + `state`; el spec verifica que el texto de la tarjeta no contiene `secreto`, `storage_key`, `checksum` ni `.mp3` (la fixture del audio con archivo sí los trae en la fila cruda).
- T-12-24 (XSS por título/descripción/nombre): mitigada. Todo se renderiza como texto de React; specs con `<img src=x onerror=alert(1)>` como título de audio y como nombre de portal sin elemento `img`.
- T-12-SC (npm installs): sin instalaciones nuevas.

## Next Phase Readiness

12-07 (mapa) puede reutilizar `EntityDetail` sin cambios; los marcadores de trigger permitirán encadenar el E2E path -> portal -> trigger. 12-09 usa `EntityDetail expanded` con `buildView(model, sel, 'pageObras')`: ya trae audio, tira y tabla. La Fase 13 reproduce dentro de `.player-slot` (sólo existe en estado `file`).

---
*Phase: 12-web-de-lectura*
*Completed: 2026-10-06*

## Self-Check: PASSED
