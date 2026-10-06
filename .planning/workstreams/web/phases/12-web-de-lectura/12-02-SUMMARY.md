---
phase: 12-web-de-lectura
plan: 02
subsystem: web-data-layer
tags: [pull, store, model, geometry, sync-pill, WEB-07, WEB-08, tracer]

requires:
  - phase: 12-01
    provides: "SPA Vite + React 19, router propio, session.js (única puerta a la clave), Shell, Acceso, DS"
  - phase: 10
    provides: "GET /sync/pull (limit 1..1000, cursor string, hasMore) y TABLE_SPEC como contrato"
provides:
  - "pullAll: cliente único de pull paginado (SPA y script de medición de 12-03), cursor siempre string, guarda anti-bucle"
  - "model.js: lista blanca USED_COLUMNS (H3), applyRows (merge por uuid, descarta deleted_at) y buildModel (grafo derivado con filtro en cascada)"
  - "geometry.js puro: haversine, mediana de radios, huecos, tramos, ancho de corredor"
  - "store.js: useStore/useModel/load/resetStore, pull todo-o-nada"
  - "SyncPill en el header (Leyendo / Al día con cursor / Error sin datos) y home con leyenda de conteos y estados E1"
  - "fixtures.js (filas sintéticas desde TABLE_SPEC) y e2e/mock-api.js (Wave 0)"
affects: [12-03, 12-04, 12-05, 12-06, 12-07, 12-08, 12-09, 12-10]

tech-stack:
  added: []
  patterns:
    - "Contrato por test, no por tipos: model.spec.js importa api/_lib/spec.js y exige USED_COLUMNS ⊆ TABLE_SPEC (D-19)"
    - "El modelo de vista es un grafo en memoria con referencias de objeto (obra.recorrido, path.obra, trigger.path); no se serializa"
    - "Store de módulo + useSyncExternalStore, con contador de generación para ignorar pulls en vuelo tras salir de la web"

key-files:
  created:
    - web/src/data/pull.js
    - web/src/data/pull.spec.js
    - web/src/data/model.js
    - web/src/data/model.spec.js
    - web/src/data/geometry.js
    - web/src/data/geometry.spec.js
    - web/src/data/store.js
    - web/src/data/store.spec.js
    - web/src/test/fixtures.js
    - web/src/app/format.js
    - web/src/app/format.spec.js
    - web/src/app/SyncPill.jsx
    - web/src/pages/MapPage.jsx
    - web/e2e/mock-api.js
    - web/e2e/sync.spec.js
  modified:
    - web/src/app/App.jsx
    - web/src/app/Shell.jsx
    - web/src/app/shell.css
    - web/e2e/acceso.spec.js

key-decisions:
  - "El pull es todo-o-nada: buffer de filas y recién con hasMore=false se reemplaza el store; un pull roto jamás deja una vista a medias"
  - "Lista blanca en el ingreso al store (H3): share_token, owner_id, user_id, checksum y el texto de storage_key nunca entran; audios sólo exponen has_file"
  - "Filtro en cascada en buildModel (WEB-08): lo que cuelga de algo ausente o borrado no existe y se cuenta en orphans"
  - "Salir de la web y el 401 vacían el store (resetStore), no sólo la clave"

requirements-completed: []

status: complete
commits: 2
plan_head_before: 11c6a1e000eb72877968a6ca6f4026e0fc1846d9
plan_head_after: 39a4ecb1e32b626bdeca5ed5aed7c5ccea6e1a71
actuals:
  tokens: 12500   # chars/4 sobre el diff real de web/ (50 099 chars, sin package-lock.json)
  tasks: 2
  commits: 2

duration: ~50min
completed: 2026-10-06
---

# Phase 12 Plan 02: Pull, store, modelo derivado y pill de sync Summary

**La web lee todo el servidor con `GET /sync/pull` (páginas de 1000, cursor string, todo-o-nada), lo reduce a un modelo sin borradas, sin huérfanos y sin columnas sensibles, y lo dice en la pill del header y en la leyenda del home.**

## Decisiones que afectan el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras no se resuelva |
|----------|---------|--------------------------|--------------------------------|
| **Pull todo-o-nada con reemplazo total** del store: `load()` siempre pide desde cursor `'0'` y aplica todo al final | Las FKs son diferidas (un hijo puede llegar antes que su padre) y la UI-SPEC prohíbe vistas a medias; el modelo sólo es consistente con todas las páginas | Aplicar página a página (vistas con huérfanos transitorios); refresco incremental ya (lo entrega 12-04) | Cada carga relee TODO el servidor: costo O(filas) por carga. Con ~1000 filas por página y un solo editor es aceptable; 12-03 mide el tamaño real. **El refresco incremental desde `cursor` guardado no existe todavía** (12-04) |
| **Lista blanca en el ingreso al store** (`USED_COLUMNS`) en vez de filtrar en la vista | H3: el payload trae `share_token`, `owner_id`, `user_id`, `checksum`, `storage_key`; si entran al store cualquier componente podría pintarlos. `storage_key` sólo deriva `has_file` | Confiar en que las vistas no los lean; tipos estáticos (D-19 descarta TypeScript) | Si el servidor agrega una columna a `TABLE_SPEC`, la web la ignora en silencio: está bien para seguridad, pero una vista futura que la necesite exige tocar `USED_COLUMNS` (el test de contrato sólo vigila el sentido `USED_COLUMNS ⊆ TABLE_SPEC`) |
| **Modelo de vista = grafo con referencias de objeto** (`obra.recorrido`, `path.obra`, `trigger.path`) | Navegación O(1) para panel y mapa; créditos y huecos se calculan una vez por pull | Ids planos con joins en cada vista | No es serializable (`JSON.stringify` cicla). Cualquier cosa que quiera persistir/loggear el modelo debe proyectarlo primero |
| **`counts.portales` cuenta paths `kind='portal'` aunque no tengan trigger** (literal del plan) | Es lo que dice la interfaz del plan | Contar sólo portales con trigger (la UI-SPEC dice que un portal sin trigger "no cuenta en el mapa") | La leyenda de 12-07 filtra por selección/visibilidad y debe decidir si excluye portales sin trigger; hoy el home puede contar uno de más en un dataset con portales vacíos (las fixtures no tienen ese caso) |

#### Secuencia — lectura del servidor (cierra el flujo de Acceso de 12-01)

```mermaid
sequenceDiagram
  autonumber
  participant App as App.jsx (efecto)
  participant St as store.js
  participant Pull as pull.js (pullAll)
  participant API as GET /sync/pull
  participant M as model.js
  participant UI as SyncPill / MapPage

  App->>St: load() (clave presente, status idle)
  St->>UI: status loading, read 0
  loop hasta hasMore=false
    St->>Pull: pullAll({ key, cursor })
    Pull->>API: cursor=<string>&limit=1000 (Bearer, no-store)
    API-->>Pull: { changes, nextCursor, hasMore }
    Pull-->>St: onPage { page, rows } (sólo contadores)
    St->>UI: Leyendo… {n} filas
  end
  alt todas las páginas OK
    St->>M: applyRows(emptyTables(), rows) (whitelist, descarta deleted_at)
    St->>UI: status ready, tables nuevas, cursor, lastPullAt
    UI->>M: useModel() -> buildModel (cascada, huecos, créditos)
  else 401
    St->>St: clearKey() + resetStore()
    St->>App: navigate(/acceso?motivo=401)
  else otro error
    St->>UI: status error; tables previas intactas; errors += { cursor, page, status }
  end
```

## Performance

- **Duración:** ~50 min
- **Tareas:** 2/2 (Task 1 tracer, Task 2 auto/tdd)
- **Archivos:** 15 creados, 4 modificados bajo `web/`; `web/api/` sin diff

## Accomplishments

- Tracer end-to-end verificado antes de expandir: pull paginado -> store con lista blanca -> pill. Pasa en Playwright con 2 páginas (limit 30 en el mock), con falla en la página 2 y con 401.
- Modelo derivado con todos los puntos de `<behavior>` cubiertos por un caso en `model.spec.js` sobre las fixtures (obra D y sus hijos, trigger y obra_artistas borrados, audio inexistente, orden `(position, uuid)` con `index` 0..n-1, portal con su primer trigger, obra sin recorrido, créditos del recorrido).
- Geometría pura (0 imports de Leaflet): 111195 m ±1, hueco sólo con distancia > r_a + r_b, `corridorPx(12,-42,16)` ≈ 13,5.
- Home (`/`) con leyenda `3 obras · 3 paths · 35 triggers · 1 portal` sobre las fixtures y estados cargando / vacío / error con `Reintentar lectura`.

## Verification evidence

- `cd web && npm run test:ui`: 7 archivos, 52 tests OK (pull, model, geometry, store, format, router, session).
- `cd web && npm test` (backend, node:test): 48 pass / 0 fail / 5 skipped (igual que antes: sin `DATABASE_URL`).
- `cd web && npm run build`: OK (`dist/` con JS 234,86 kB / 74,55 kB gzip).
- Playwright `e2e/sync.spec.js` + `e2e/acceso.spec.js`: 13 de 13 OK (6 de sync, 7 de acceso).
- `git diff 5759616 -- web/api` vacío (5759616 = `docs(12): create phase plan`); `grep -c "from 'leaflet'" web/src/data/geometry.js` = 0.

## Task Commits

1. **Task 1: tracer pull + store + pill:** `51ea8de` (feat)
2. **Task 2: modelo derivado + geometría + leyenda:** `39a4ecb` (feat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reset del branch de arranque del worktree**
- **Found during:** arranque. HEAD era `5b1ac2f` (merge del PR #1), sin los archivos de la Fase 12.
- **Fix:** `git reset --hard ws/web` (paso sanctioned de arranque) y `npm ci`. Verificados `router.jsx` y los archivos de planificación.

**2. [Rule 1 - Bug] `acceso.spec.js` empezó a pegarle a la red real**
- **Found during:** Task 1. Tras entrar, el shell ahora llama `load()`, y el e2e de 12-01 sólo mockeaba `/sync/state`; `/sync/pull` caía por el proxy de Vite a `https://cingula.vercel.app`.
- **Fix:** `mockState` ahora también responde un pull vacío. Mantiene la regla "ninguna request sale a un servidor real". Commit `51ea8de`.

**3. [Rule 2 - Missing critical] El store sobrevivía a "Salir de la web" y al 401**
- **Found during:** Task 1. El plan sólo pedía `clearKey()`; pero con el store de módulo, entrar luego con otra clave en la misma pestaña mostraba los datos de la sesión anterior sin releer (status `ready`).
- **Fix:** `resetStore()` (vacía el estado e invalida pulls en vuelo con un contador de generación), llamado desde `Salir de la web` y desde el 401. Test: "salir de la web mientras hay un pull en vuelo: el resultado tardío se ignora". Commit `51ea8de`.

**4. [Menor] Ledger de commits del plan**
- El protocolo 0c pide persistir `plan_head_before` en `.git/.../gsd-plan-head-before-12-02`; el entorno bloqueó escribir ahí (worktree aislado). Se usó el HEAD de arranque (`11c6a1e`, registrado arriba) y el conteo `git rev-list --count 11c6a1e..HEAD` = 2.

### Decisiones de interpretación

- **`requirements-completed: []` y no se marcaron WEB-02, WEB-03, WEB-07, WEB-08.** El frontmatter del plan los lista, pero este plan entrega la capa de datos y el home, no las vistas que los satisfacen: WEB-07 exige popover con errores/cursor (12-04), WEB-02/03 los paneles y páginas (12-05, 12-09), WEB-08 "ninguna *vista*" se cierra recién con todas (la verificación final es 12-10). Marcarlos completos ahora sería un overclaim. AUTH-02 ya estaba completo desde 12-01. El orquestador puede marcarlos distinto si prefiere el criterio literal.
- Si el primer pull falla pero había datos previos, el `status` queda `error` (no `ready`) con `tables` intactas; la matriz completa (desactualizado, offline, reintento automático) es de 12-04.
- `has_file` = `storage_key` no vacío (el servidor no valida existencia del objeto en storage; eso es de la fase de Storage).

## Issues Encountered

- La primera corrida de Playwright en frío falló 2 tests por timeout de `page.goto` (la primera carga del dev server de Vite tarda ~18 s optimizando dependencias); la segunda corrida pasó 10/10 y la tercera 13/13 en 26 s. No es un fallo de código, pero **en CI o en una máquina fría conviene precalentar Vite o subir el timeout**: lo hereda cualquier plan posterior que corra Playwright.

## Auth gates

Ninguno.

## Known Stubs

Ninguno. El home no dibuja mapa todavía por diseño (lo agrega 12-07 alrededor de la leyenda); las rutas `/obras` y `/artistas` siguen montando el shell vacío hasta 12-09 (documentado desde 12-01). No hay datos falsos ni placeholders de UI.

## Threat Flags

Ninguna superficie nueva fuera del `<threat_model>`.

Estado de las amenazas del plan:
- T-12-08 (columnas sensibles): mitigada. `USED_COLUMNS` + `applyRows`; test: ninguna fila resultante trae las 5 columnas ni `deleted_at`; audios sólo `has_file`.
- T-12-09 (clave revocada): mitigada. 401 -> `clearKey()` + `resetStore()` + `/acceso?motivo=401`; E2E y spec.
- T-12-10 (borradas/huérfanas): mitigada. `applyRows` descarta `deleted_at`; `buildModel` filtra en cascada; `orphans` = `{ paths: 1, triggers: 1, obra_artistas: 1 }` sobre las fixtures.
- T-12-11 (pull que no termina): mitigada. Guarda anti-bucle en `pullAll`; spec.
- T-12-12 (precisión del cursor): mitigada. Cursor siempre string; spec con `9007199254740993`.
- T-12-SC (npm installs): sin instalaciones nuevas; `package.json` y lockfile sin cambios.
- Nota XSS: los nombres con HTML de prueba (`<img src=x onerror=alert(1)>`) llegan al modelo como texto; hoy ninguna vista los interpola (el home sólo muestra conteos). Las vistas de 12-05+ deben seguir renderizándolos como texto (React lo hace por defecto; Leaflet `divIcon`/`bindTooltip` no, ver research Pattern 3).

## Next Phase Readiness

12-03 puede reutilizar `pullAll` desde Node (sin dependencias; `onPage` expone `bytes` y `ms`) y `geometry.js`/`buildModel` puros. 12-04 extiende `store.js` (refresco incremental desde `cursor`, reintentos, popover) y `SyncPill.jsx`. 12-05..12-09 consumen `useModel()` y las fixtures (`makeRows`, `ID`, `LONG_NAME`, `HTML_NAME`) y `mockApi`/`loginAs` para sus E2E. Dato para 12-03: el modelo hoy asume `limit` 1000 por página (el default del servidor es 500, el máximo 1000); la medición debe confirmar que 1000 filas por página no excede el límite de respuesta de Vercel (A3 de la research).

---
*Phase: 12-web-de-lectura*
*Completed: 2026-10-06*

## Self-Check: PASSED
