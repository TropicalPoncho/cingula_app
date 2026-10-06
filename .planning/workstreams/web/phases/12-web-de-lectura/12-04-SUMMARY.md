---
phase: 12-web-de-lectura
plan: 04
subsystem: web-sync-state
tags: [sync-pill, popover, retry, incremental-refresh, WEB-07, tracer]

requires:
  - phase: 12-02
    provides: "pullAll/HttpError, store.js (useStore/load/resetStore), applyRows, format.js (rel), SyncPill básica, mock-api/fixtures"
provides:
  - "syncState.js: pillState(snapshot, now, online) puro con la matriz de 6 estados de la UI-SPEC y constantes STALE_MS / RETRY_MS / MAX_RETRIES"
  - "SyncPill: pill + popover accesible (dialog no modal, Esc / clic afuera con foco devuelto, role=alert sólo con error nuevo, < 900 px sólo punto + ícono)"
  - "store.js: pull único completo/incremental, load / refresh / retryNow, reintento automático 3 x 30 s, online/offline, cursor monótono por BigInt"
  - "mock-api: opción failTimes"
affects: [12-07, 12-09, 12-10]

tech-stack:
  added: []
  patterns:
    - "Matriz de estados como función pura sobre el snapshot del store: se testea sin DOM ni reloj (now inyectado)"
    - "Un solo `pull(incremental)` interno; load / refresh / retryNow son entradas finas que reinician la racha de reintentos"

key-files:
  created:
    - web/src/app/syncState.js
    - web/src/app/syncState.spec.js
    - web/src/app/SyncPill.spec.jsx
  modified:
    - web/src/app/SyncPill.jsx
    - web/src/app/shell.css
    - web/src/data/store.js
    - web/src/data/store.spec.js
    - web/e2e/mock-api.js
    - web/e2e/sync.spec.js

key-decisions:
  - "Refresco incremental todo-o-nada sobre una copia de los Maps (applyRows no muta) y reemplazo al final; el cursor sólo avanza (BigInt)"
  - "Reintento automático = 1 intento inicial + 3 reintentos cada 30 s; un éxito, resetStore o cualquier acción del usuario (load / refresh / retryNow) lo cancela y reinicia la racha"
  - "Prioridad de la matriz: Leyendo > Error > Sin conexión > Desactualizado > Al día; un error nunca queda oculto detrás de 'Sin conexión'"
  - "role=alert del bloque de errores sólo en el render en que aparece un error nuevo (ref con el último `at` visto)"

requirements-completed: [WEB-07]

status: complete
commits: 2
plan_head_before: eddd682739ef7d3716c1d0ccc1e7ef1cc366dfa8
plan_head_after: 34695220b174177c52de9128bbfb665035209c23
actuals:
  tokens: 8400   # chars/4 sobre el diff real de web/ (33 621 chars, specs incluidos)
  tasks: 2
  commits: 2

duration: ~35min
completed: 2026-10-06
---

# Phase 12 Plan 04: Estado de sync honesto Summary

**La pill del header implementa los 6 estados de la UI-SPEC con un popover accesible que lista cada intento fallido (`HH:MM:SS  GET /sync/pull?cursor={c} → {código} {texto} (página {k})`), reintento automático acotado a 3 x 30 s y refresco incremental que respeta borrados y no retrocede el cursor.**

## Decisiones que afectan el futuro (primero, por regla de oro)

| Decisión | Por qué | Alternativas descartadas | Riesgo mientras no se resuelva |
|----------|---------|--------------------------|--------------------------------|
| **Refresco incremental sobre una copia + reemplazo atómico**, y `retryNow` = `refresh` (incremental con datos, completo si `cursor == null`) | La UI-SPEC pide todo-o-nada; `applyRows` ya copia los Maps, así que un fallo a mitad no toca `tables` (test: misma identidad) | Aplicar página a página (vistas con huérfanos transitorios); pedir siempre desde `'0'` (O(filas) en cada clic) | Un borrado que el servidor **nunca emita como fila con `deleted_at`** (p. ej. un DELETE físico) no desaparecería en un incremental: sólo un `load()` completo lo corregiría. Hoy el contrato (Phase 10) usa soft-delete, por eso es seguro |
| **El cursor sólo avanza (`BigInt(nuevo) >= BigInt(actual)`)**; si el servidor devuelve uno menor se conserva el guardado | Evita reprocesar/perder la posición por una respuesta anómala (R12: bigint de Postgres, nunca `Number`) | Aceptar el cursor del servidor tal cual | Si el servidor **reiniciara** su secuencia (restore de backup), la web quedaría con cursor adelantado y no vería cambios nuevos hasta recargar la pestaña (un `load()` completo parte de `'0'`). Escenario fuera del v0 de usuario único |
| **Política de reintento [DEFAULT, OI-09]: inicial + 3 reintentos cada 30 s**, constantes con nombre en `syncState.js` (`RETRY_MS`, `MAX_RETRIES`, `STALE_MS` = 15 min) | Acota la carga sobre el backend (T-12-18) sin dejar al usuario sin recuperación automática ante cortes cortos de Lago Puelo | Backoff exponencial (más código, sin evidencia de necesidad); reintento infinito (tormenta) | Cortes > 90 s dejan la web en error hasta que el usuario pulse `Reintentar lectura`; los 3 valores no están validados con el usuario. El reintento no escucha el evento `online` (no reintenta solo al volver la red) |
| **Prioridad de estados: Error gana a Sin conexión** | "Nunca se oculta un error" (UI-SPEC) | Mostrar 'Sin conexión' primero (el error por falta de red quedaría tapado) | Con la red caída el usuario ve 'Error de pull', no 'Sin conexión', hasta que un pull exitoso lo limpie; el popover sí lista el motivo |

#### Secuencia — fallo, reintento automático y recuperación

```mermaid
sequenceDiagram
  autonumber
  participant U as Usuario
  participant P as SyncPill / popover
  participant S as store.js
  participant API as GET /sync/pull

  S->>API: pull (completo o incremental desde cursor)
  API-->>S: 500
  S->>S: errors += { at, cursor, page, status, text }; autoTry=0 < 3
  S->>P: status error, retry { attempt: 1, nextAt }
  P-->>U: "Error de pull · ..." (aunque el popover esté cerrado)
  loop hasta 3 veces, cada 30 s
    S->>API: pull (autoTry++)
    API-->>S: 500
    S->>P: errors += línea "(reintento i de 3)"
  end
  S->>P: retry = null -> nota "Reintentá cuando tengas conexión."
  U->>P: clic "Reintentar lectura"
  P->>S: retryNow() (autoTry = 0, cancela timer)
  S->>API: pull
  API-->>S: 200
  S->>P: status ready, errors = [], retry = null -> "Sync al día"
```

## Accomplishments

- **Tracer (Task 1)**: falla en la página 2 -> pill `Error de pull · sin datos` -> popover con `→ 500 mock failure (página 2)` (sin `Bearer`) -> `Reintentar lectura` -> `Sync al día`; verde en Playwright antes de expandir.
- **Matriz completa (Task 2)**: Leyendo, Al día (con `hoy HH:MM:SS · hace {rel}` / `dd.mm.aa HH:MM:SS`), Desactualizado (> 15 min, el límite exacto no cuenta), Error con datos, Error sin datos y Sin conexión; 9 casos en `syncState.spec.js` con `now` fijo.
- **Store**: reintento 3 x 30 s verificado con fake timers (exactamente 4 fetch: 1 inicial + 3; ninguno antes de los 30 s; ninguno después); un éxito, `retryNow` o `resetStore` cancelan el timer; refresco incremental con una edición y un borrado sobre las fixtures; cursor monótono; un refresh fallido deja `tables`, `cursor` y `lastPullAt` idénticos.
- **Popover accesible**: `aria-haspopup="dialog"` + `aria-expanded`, `role="dialog"` con `aria-label="Detalle del estado de sync"` sin `aria-modal`, Esc y clic afuera cierran y devuelven el foco, hora relativa refrescada cada 30 s (intervalo limpiado al desmontar).
- **Responsive [ASUNCIÓN OI-05]**: `@media (max-width: 899px)` oculta el texto (queda punto + ícono; el texto va al `aria-label` de la pill) y el popover pasa a casi ancho completo (margen de 8 px, `position: fixed`). Textos largos envuelven (`overflow-wrap: anywhere`). Ambos son `backstop` en el plan: **no hay verificación automatizada de estos dos**.

## Verification evidence

- `cd web && npm run test:ui`: 9 archivos, 73 tests OK (antes 52).
- `cd web && npx playwright test -c e2e/playwright.config.js`: 14 de 14 OK (7 de sync incluido el nuevo, 7 de acceso).
- `cd web && npm run build`: OK.
- `web/api/` sin diff (sin instalaciones nuevas, sin cambios de dependencias).

## Task Commits

1. **Task 1 (tracer):** `52fcb80` — `feat(12-04): visible pull failure and manual retry (WEB-07)`
2. **Task 2:** `3469522` — `feat(12-04): honest sync state matrix, retries and incremental refresh (WEB-07)`

## Deviations from Plan

### Auto-fixed / criterio propio

**1. [Rule 1 - Bug de copy] Estado de "Error sin datos" no repite la frase falsa**
- **Found during:** Task 2
- **Issue:** la UI-SPEC dice "igual" que con datos, pero `Pull incompleto: se muestran los datos del último pull completo.` es falso si no hay ningún pull completo.
- **Fix:** sin datos dice `Pull incompleto: todavía no hay datos para mostrar.` (copy nuevo, a validar con el usuario). Con datos, literal de la UI-SPEC.
- **Files modified:** `web/src/app/syncState.js`
- **Commit:** `3469522`

**2. [Interfaz] `lastOkAt` no se agregó al snapshot**
- `lastPullAt` ya es "el momento del último pull completo OK" (sólo se escribe al terminar con éxito y un error no lo toca), así que `lastOkAt` sería un duplicado. Agregados: `online`, `retry`. `retry.nextAt` se guarda (contrato de la interfaz) pero la pill usa el texto fijo "30 s" de la UI-SPEC, por lo que hoy ningún consumidor lo lee.

**3. [Alcance] `statusText` no se muestra**
- El plan dice "el `error` del JSON o el statusText". `HttpError` (`pull.js`, de 12-02, fuera de `files_modified`) no conserva el statusText, así que el texto es el `error` del JSON o vacío (la línea omite el hueco). Sólo se muestra ese string, nunca el cuerpo crudo (cierra T-12-17 de forma más estricta que antes: antes el store guardaba `body.slice(0, 200)`).

**4. [Interpretación] role=alert**
- Se aplica sólo en el render en que aparece un error nuevo (`ref` con el último `at` visto), por lo que un popover que se abre *después* del error no lo re-anuncia (la pill ya lo dijo). Consecuencia: el E2E de recuperación localiza el bloque con `.perr` y no con `getByRole('alert')`; la cobertura de `role=alert` está en `SyncPill.spec.jsx`.

**5. [Aditivo] Filas extra en el popover**
- Desactualizado y Sin conexión muestran además `Último pull` y `Cursor` (la matriz sólo listaba `Estado`): sin ellas el popover no diría desde cuándo son los datos.

**6. [Cambio de forma] `errors` se limpia en cada pull exitoso y se acota a los últimos 10**
- Un éxito deja `Sin errores`; el tope evita crecimiento sin límite durante un corte largo.

## Known Stubs

None.

## Threat Flags

None. T-12-17 (sin headers/clave en las líneas; aserción en E2E y en `syncState.spec.js`), T-12-18 (tope de 3 reintentos; spec con fake timers), T-12-19 (todo-o-nada + estados explícitos) y T-12-20 (React escapa el texto; sin HTML crudo) mitigadas según el plan.

## Self-Check: PASSED

- FOUND: `web/src/app/syncState.js`, `web/src/app/syncState.spec.js`, `web/src/app/SyncPill.spec.jsx` (más los 6 modificados).
- FOUND commits: `52fcb80`, `3469522` (`git rev-list --count eddd682..HEAD` = 2).
