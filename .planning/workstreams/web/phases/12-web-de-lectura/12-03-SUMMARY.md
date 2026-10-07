---
phase: 12-web-de-lectura
plan: 03
subsystem: web-measurement
tags: [measurement, OI-02, circles, production, WEB-01, WEB-08, tracer]

requires:
  - phase: 12-02
    provides: "pullAll, applyRows, buildModel, geometry.js y fixtures.js (el script los reusa tal cual)"
provides:
  - "web/scripts/measure-pull.mjs: medición de sólo lectura (summarize pura + CLI), sólo agregados"
  - "OI-02 cerrado en 12-UI-SPEC.md: CIRCLES_MIN_ZOOM = 16, CIRCLES_MAX = 600"
  - "WEB_API_KEY presente en Production (config del usuario), /sync/state sigue en 401 JSON"
affects: [12-08, 12-10]

tech-stack:
  added: []
  patterns:
    - "Script de medición = mismo cliente y mismo modelo que la SPA (pullAll + applyRows + buildModel): mide lo que la web verá"
    - "Clave sólo por variable de entorno del proceso; la salida son agregados (test falla si aparece un uuid o un nombre de fixture)"

key-files:
  created:
    - web/scripts/measure-pull.mjs
    - web/scripts/measure-pull.test.js
  modified:
    - .planning/workstreams/web/phases/12-web-de-lectura/12-UI-SPEC.md

key-decisions:
  - "CIRCLES_MIN_ZOOM = 16: mediana de radios real 12 m -> 12 * 0,563 * 2^0 = 6,8 px >= 6 px (z15 daría 3,4 px)"
  - "CIRCLES_MAX = 600 sin cambios: máx real 35 triggers por obra (p95 26); el tope nunca actúa con datos reales y queda como defensa"
  - "pull.js NO se tocó: 1 página de 280 526 bytes (0,28 MB << 3 MB), limit sigue en 1000"

requirements: [WEB-01, WEB-08]
requirements-completed: []

status: complete
commits: 2
plan_head_before: eddd682739ef7d3716c1d0ccc1e7ef1cc366dfa8
plan_head_after: 6aacbc242c2b37ffff9f901af9c549005264c8fd
actuals:
  tokens: 3000    # chars/4 sobre el diff propio (script 5 267 + test 3 436 + ~3 500 de edición de la UI-SPEC)
  tasks: 3
  commits: 2      # commits propios: 4c1f817 y 6aacbc2. El rango eddd682..HEAD incluye además lo mergeado por el orquestador (12-04..12-07), por eso no se midió con rev-list

duration: ~1h (incluye la pausa de la acción humana)
completed: 2026-10-07
---

# Phase 12 Plan 03: Medición real de pull y cierre de OI-02 Summary

**`measure-pull.mjs` lee Production con la clave de lectura, imprime sólo agregados, y con esos números el modo Círculos queda fijado en `CIRCLES_MIN_ZOOM = 16` y `CIRCLES_MAX = 600`.**

## Decisiones y riesgos que afectan el futuro (primero, por regla de oro)

| Decisión / hallazgo | Por qué | Alternativas descartadas | Riesgo mientras no se resuelva |
|---------------------|---------|--------------------------|--------------------------------|
| **RIESGO ABIERTO: `paths_portal: 0` en Production.** No existe ningún `paths.kind='portal'` | Medido (ver abajo). No se inventó ninguna corrección | Sintetizar portales o ajustar el modelo para "tener" portales | La capa de portales del mapa, el panel de portal y la tabla "Portales de la obra" sólo se validan con fixtures sintéticas en esta fase, nunca con datos reales. A confirmar con el usuario: el celular puede no haber producido todavía filas `kind='portal'`, o la migración v7 no las creó |
| **RIESGO ABIERTO (derivado de la misma medición): `filas_vivas` sólo tiene `audios`, `obras`, `paths`, `triggers`** (0 `recorridos`, 0 `artistas`, 0 `obra_artistas`) | Lo que muestra el output pegado: no aparecen esas tablas | Asumir que el output omitió ceros por formato (no: `summarize` cuenta por tabla sólo las que aparecen en `rows`, así que una tabla ausente = 0 filas) | Agrupación por recorrido, filtro de recorrido, créditos de artistas y la pantalla de Artistas tampoco se pueden validar con datos reales. A confirmar con el usuario junto con el punto anterior |
| `CIRCLES_MIN_ZOOM = 16` | Regla del plan: menor z en {15,16,17} con `mediana · 0,563 · 2^(z-16) >= 6 px`; mediana real 12 m | z15 (3,4 px, círculos ilegibles); z17 (innecesario) | Bajo. Si aparecen paths con radios mucho menores, revisar |
| `CIRCLES_MAX = 600` sin cambios | p95 de triggers por obra = 26 (máx 35) << 600 | Bajar el tope | Ninguno hoy; el corte por viewport + "sólo el path resaltado sobre el tope" (R6) queda como comportamiento defensivo, no esperado |
| `limit = 1000` en `pull.js` sin cambios | `bytes_max_pagina` = 280 526 << 3 MB (A3); el pull completo cabe en 1 página (~750 filas, 1 873 ms) | Bajar a 500 | Si el catálogo crece ~10x una página se acercaría al límite de respuesta de Vercel (4,5 MB); re-medir con el mismo script |

## Medición real (Production, 2026-10-07, corrida por el usuario en su terminal)

```
paginas: 1
bytes_total: 280526
bytes_max_pagina: 280526
ms_max_pagina: 1873
filas_vivas: {"audios":86,"obras":79,"paths":85,"triggers":500}
filas_descartadas: {"obras":1,"paths":1,"triggers":1}
paths_route: 85
paths_portal: 0
triggers_por_path_route_max_p50_p95: 35 / 3 / 19
triggers_por_obra_max_p50_p95: 35 / 2 / 26
radio_m_min_mediana_max: 9 / 12 / 20
paths_con_radios_mezclados_gt10pct: 0
separacion_mediana_m: 12.6
huecos_total: 4
paths_con_huecos: 3
paths_con_position_repetida: 0
paths_con_position_con_saltos: 0
obras_con_triggers_vivos: 74
obras_con_triggers_y_cobertura_null: 3
portales_con_mas_de_un_trigger: 0
audios_usados_por_mas_de_un_path: 2
huerfanos: {}
```

Regla aplicada (Task 3): 1) mediana 12 m -> z16 (6,8 px); 2) p95 por obra 26 < 600 -> tope 600; 3) bytes máx 0,28 MB < 3 MB -> `pull.js` intacto.

Hallazgos de datos (también anotados en `12-UI-SPEC.md`, "Items abiertos"):

- H4: 3 obras con triggers vivos y cobertura NULL (de 74).
- H5: 0 paths con `position` repetida o con saltos; el orden `(position, uuid)` es sólo defensivo.
- OI-10: 0 paths con radios mezclados > 10 %; el corredor por mediana es exacto con los datos reales.
- D-11: 2 audios usados por más de un path; `AudioCard` muestra el audio por path, no hace falta listado.
- 4 huecos en 3 paths: la regla de huecos se dispara con datos reales.
- Producción: `curl /sync/state` -> `401 application/json` antes del redeploy y de nuevo tras cerrar el plan (el ruteo del celular está intacto).

## Tasks

| Task | Nombre | Commit | Archivos |
|------|--------|--------|----------|
| 1 | Tracer: `measure-pull.mjs` + test con servidor HTTP local | 4c1f817 | web/scripts/measure-pull.mjs, web/scripts/measure-pull.test.js |
| 2 | Acción humana: WEB_API_KEY en Production, redeploy y corrida de la medición | (sin commit; la hizo el usuario) | — |
| 3 | Cierre de OI-02 en la UI-SPEC | 6aacbc2 | .planning/workstreams/web/phases/12-web-de-lectura/12-UI-SPEC.md |

Verificación: `cd web && npm test` -> 52 pass / 0 fail (incluye 4 casos nuevos: agregados paginados, sin uuids ni nombres, exit 2 sin clave, 401 con clave mala sin eco de la clave).

## Deviations from Plan

**1. [Rule 3 - criterio de aceptación literal] El script importa `env` de `node:process`**
- **Found during:** Task 1 (criterio `grep -cE "readFile|dotenv|\.env" web/scripts/measure-pull.mjs` = 0)
- **Issue:** `process.env.WEB_API_KEY` contiene la subcadena `.env`, el grep daba 2 aunque el script no lee ningún archivo.
- **Fix:** `import { env } from 'node:process'` y `env.WEB_API_KEY`; comentario reformulado. Comportamiento idéntico.
- **Files modified:** web/scripts/measure-pull.mjs
- **Commit:** 4c1f817

**2. [Medición de `commits`]** `commits: 2` es el recuento de commits propios, no `rev-list eddd682..HEAD`: la rama del worktree fue avanzada por el orquestador con el merge de 12-04..12-07 (el rango da 21). `plan_head_before` es el tip de `ws/web` al arrancar; `plan_head_after` es mi último commit.

Auth gate (Task 2): documentado como flujo normal, no desvío. El ejecutor nunca vio la clave.

## Known Stubs

None.

## Threat Flags

None. T-12-13 mitigado (el test falla si hay uuid o nombre de fixture en la salida); T-12-14 mitigado (clave sólo por entorno, no se imprime ni se escribe, el ejecutor no la vio); T-12-16 mitigado (curl a `/sync/state` antes y después: 401 JSON).

## Self-Check: PASSED

- web/scripts/measure-pull.mjs y web/scripts/measure-pull.test.js existen; commits 4c1f817 y 6aacbc2 presentes en el historial; `12-UI-SPEC.md` contiene `CIRCLES_MIN_ZOOM = 16`, `CIRCLES_MAX = 600` y OI-02 cerrado; `pull.js` sin cambios.
