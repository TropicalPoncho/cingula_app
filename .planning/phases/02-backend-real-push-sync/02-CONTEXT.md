# Phase 2: Backend Real + Push Sync - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Esta fase reemplaza `SyncApiStub` por un backend real que implementa el contrato de outbox ya existente (`SyncApi.pushOutbox`), con push automático (no manual), reintentos con backoff exponencial + jitter, autenticación mínima por API key, dedupe idempotente por `uuid`+`logical_version`, versionado limitado (actual + 1 anterior) en el servidor, y estado de sync honesto visible en el panel de debug. Pull sync (`SyncApi.pullChanges`) queda fuera de esta fase — es Fase 3.

</domain>

<decisions>
## Implementation Decisions

### Hosting del backend
- **D-01:** Neon (Postgres serverless, scale-to-zero) + Vercel Functions — ya investigado y documentado en CLAUDE.md con alternativas descartadas (Supabase, VPS propio, PowerSync/ElectricSQL) y justificación de costo/escala. No se discutió de nuevo en esta sesión porque el research existente ya es sólido; se confirma como decisión por defecto. `PROJECT.md` todavía lo marca "Pending" en la tabla de Key Decisions — actualizar a confirmado al escribir CONTEXT.

### Autenticación mínima (SYNC-07)
- **D-02:** API key estática, fijada en tiempo de compilación vía `--dart-define` (mismo patrón que `ApiConfig._defaultBaseUrl` ya usa con `String.fromEnvironment`). Sin login, sin rotación automática — encaja con v0 de un solo editor/dispositivo.
- **D-03:** Un 401 (auth inválida) se trata como error terminal, NO se reintenta con el backoff normal — es un problema de configuración (clave mal puesta), reintentarlo indefinidamente solo gasta batería sin arreglar nada. El outbox queda pendiente hasta que se corrija la clave; el intento se loguea.

### Disparo automático de sync (SYNC-01, SYNC-03)
- **D-04:** El push se dispara automáticamente inmediatamente después de cada escritura local que genera una fila de outbox (grabar un geo_path, trigger, audio, etc.), no solo bajo demanda manual como hoy.
- **D-05:** Además del disparo inmediato, un push se reintenta cuando se recupera conectividad (usar `connectivity_plus` solo como el pre-check barato que ya recomienda CLAUDE.md — nunca como fuente de verdad de "el push funcionó").
- **D-06:** El botón manual "Push outbox (stub)" en `DiagnosticsPanel` (ya conectado a `RunSyncUseCase.pushOutboxOnce`) se mantiene como respaldo de debug para forzar un push puntual — no es una acción destructiva, no aplica el precedente D-03/D-04 de Fase 1 de eliminar acciones de debug.

### Claude's Discretion
- Backoff exponencial + jitter exacto (curva, límites, cuántos intentos antes de considerar "detenido" temporalmente) — implementar el patrón estándar de la industria, informado por `attempt_count` ya presente en `sync_outbox`.
- Mecanismo exacto de dedupe idempotente server-side por `uuid`+`logical_version` (SYNC-02) — detalle de implementación SQL en el backend.
- Formato exacto de la validación del header de auth (`Authorization: Bearer <token>` vs `X-API-Key`) — elegir el más simple de implementar en Vercel Functions.
- Cómo se conecta el disparo "inmediato tras escritura" a los distintos data sources (`GeoPathLocalDataSource`, `AudioLocalDataSource`, etc.) sin acoplar demasiado — evaluar durante research/planning.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Stack y contrato de sync
- `CLAUDE.md` sección "Technology Stack" — Neon+Vercel research completo, alternativas descartadas y por qué, versiones compatibles, fuentes citadas. Es el research de stack para esta fase, no repetir el trabajo.
- `lib/data/sync/sync_api.dart` — contrato `SyncApi` que el backend real debe implementar (pushOutbox, fetchState, pullChanges)
- `lib/data/sync/sync_client.dart` — outbox local ya operativo (`pendingOutbox`, `ackOutbox`, `markAttempt`, `getState`/`saveState`)
- `lib/domain/usecases/run_sync_usecase.dart` — flujo de push ya implementado contra la interfaz `SyncApi` (falta solo la implementación real detrás)
- `lib/core/config/api_config.dart` — patrón de configuración de base URL vía `--dart-define`, a extender con la API key del mismo modo
- `lib/core/di/service_locator.dart` (líneas ~51-66) — registro actual de `SyncApi`/`SyncApiStub`/`RunSyncUseCase`, punto donde se reemplaza el stub por la implementación real
- `.planning/REQUIREMENTS.md` — SYNC-01, SYNC-02, SYNC-03, SYNC-06, SYNC-07, SYNC-08 (texto exacto de cada requisito)
- `.planning/ROADMAP.md` — Fase 2: objetivo y criterios de éxito

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SyncClient` (`lib/data/sync/sync_client.dart`) — ya envuelve outbox local completo: `pendingOutbox(limit)`, `ackOutbox(id)`, `markAttempt(id)`, `getState()`/`saveState()`. No hace falta tocarlo.
- `RunSyncUseCase.pushOutboxOnce()` — ya orquesta el ciclo completo push→ack→markAttempt→saveState contra la interfaz `SyncApi`. Solo falta que `SyncApi` tenga una implementación real detrás en vez de `SyncApiStub`.
- `ApiConfig` — patrón `String.fromEnvironment` con override en runtime (`static String baseUrl`) ya establecido; extender igual para la API key.
- DI ya wireado en `service_locator.dart`: `SyncApi` → `SyncApiStub()`, `RunSyncUseCase` → construido con `SyncClient` + `SyncApi`. El reemplazo es literalmente cambiar qué implementación de `SyncApi` se registra ahí.

### Established Patterns
- `sync_outbox` (tabla SQLite, `app_database.dart` líneas ~138-148 y ~238-250): `table_name`, `record_uuid`, `op`, `payload`, `device_id`, `created_at`, `attempt_count` — ya tiene todo lo necesario para backoff (contador de intentos) e idempotencia (uuid).
- `sync_state` (tabla SQLite): `server_cursor`, `last_sync_at`, `device_id` — estado local de sync ya persistido.
- `DiagnosticsPanel` (`lib/presentation/pages/home/widgets/diagnostics_panel.dart` líneas ~102-115, ~482-514): YA muestra "Última sync" + "Outbox pendiente" (SYNC-08 parcialmente ya satisfecho en UI) y tiene el botón manual "Push outbox (stub)" conectado a `RunSyncUseCase`.

### Integration Points
- El push automático (D-04) necesita engancharse en el punto donde cada data source local escribe a `sync_outbox` — actualmente eso ya pasa vía `SyncLocalDataSource` (usado por `AudioLocalDataSource`, `GeoTriggerLocalDataSource`, `GeoPathLocalDataSource`, `RegionLocalDataSource`). El trigger automático probablemente vive ahí o como listener sobre esas escrituras.
- `connectivity_plus` (ya en el stack recomendado de CLAUDE.md, no instalado todavía) es el punto de enganche para D-05 (reintentar al recuperar conexión).

</code_context>

<specifics>
## Specific Ideas

- El research de stack en CLAUDE.md ya es exhaustivo (fuentes citadas, alternativas comparadas) — no reinvestigar Neon vs Supabase vs VPS, usarlo como research de entrada de esta fase.
- Prioridad del Core Value del proyecto aplicada aquí: minimizar la ventana entre "grabar en el campo" y "estar respaldado en el backend" es la razón detrás de D-04/D-05 (push inmediato + retry al reconectar, no solo periódico).

</specifics>

<deferred>
## Deferred Ideas

- Pull sync (`SyncApi.pullChanges`, SYNC-04/SYNC-05) — explícitamente Fase 3, no tocar en esta fase.
- Reconsiderar reintroducir funciones destructivas de administración de BD ahora que sync/backup es una red de seguridad real — mencionado en Fase 1 (D-05 de `01-CONTEXT.md`) como algo a revisar "cuando sync esté funcionando", pero eso es al cierre de esta fase o después, no una decisión a tomar ahora antes de construir el backend.
- Visibilidad de estado de sync en modo usuario final (hoy solo vive en el panel de debug, oculto en modo usuario por D-10 de Fase 1) — no se discutió, se asume que sigue siendo debug-only por ahora.

### Reviewed Todos (not folded)
None — no matching todos found for this phase.

</deferred>

---

*Phase: 02-backend-real-push-sync*
*Context gathered: 2026-08-29*
