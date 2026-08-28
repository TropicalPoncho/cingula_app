# Cíngula App — Sync bidireccional, background real y descarga por región

## What This Is

Cíngula App es una app Flutter de recorridos sonoros geolocalizados para espacios verdes de Lago Puelo: el usuario graba en el territorio (camino GPS + audio), y la app reproduce audio al entrar a zonas geolocalizadas (geotriggers) mientras camina. Hoy es de un solo usuario (el propio artista), corre 100% local (SQLite en el celular, sin backend), y tiene varios problemas conocidos: el audio a veces no arranca al entrar a una zona, el background gasta batería con polling continuo, no hay forma de sincronizar cambios hechos en una web de edición (todavía no existe) de vuelta al celular, y el dashboard de debug está mezclado con la experiencia de usuario final.

## Core Value

Que la app siga siendo confiable en el bolsillo del usuario mientras se construye la infraestructura de sync — ningún cambio de este milestone puede arriesgar los datos (recorridos, triggers, audio) que ya existen en el celular.

## Requirements

### Validated

- ✓ Grabación de campo (camino GPS + audio por micrófono) genera geo_paths y geo_triggers automáticamente — existente
- ✓ Reproducción de audio al entrar a una zona geolocalizada (geotrigger), con soporte de paths con offset guardado — existente
- ✓ Modelo de datos local con soporte de versionado lógico y outbox pattern (uuid, updated_at, deleted_at, logical_version, sync_outbox, sync_state) — existente, preparado pero no conectado a un backend real
- ✓ Filtrado de triggers por región activa (region_id como FK nullable en geo_triggers) — existente
- ✓ Exportar/importar base de datos local manualmente desde la UI de debug — existente
- ✓ El sistema nunca pierde datos existentes en el celular ante un fallo de apertura de la base (rename-not-delete con backup timestamped) y las acciones destructivas del panel de debug (recrear/importar BD) fueron eliminadas por completo en vez de gateadas con confirmación — Validado en Fase 1 (DATA-01, DATA-02). Confirmación humana en dispositivo real del flujo completo de recuperación quedó diferida por decisión explícita del usuario (ver `01-HUMAN-UAT.md`); la lógica está cubierta por tests automatizados.
- ✓ Separación de dashboard de usuario final vs. panel de debug mediante un toggle en runtime persistente (gesto oculto de 5 taps, sin flavors de Flutter) — Validado en Fase 1 (UI-01)

### Active

- [ ] Cada escritura local (audio_assets, geo_triggers, geo_paths, regions) se sincroniza contra un backend real vía el outbox ya existente (push)
- [ ] El celular puede recibir cambios hechos fuera de él (pull) — hoy `SyncApi.pullChanges()` existe en la interfaz pero nunca se invoca
- [ ] El servidor mantiene el estado actual + 1 versión anterior de cada entidad (no historial ilimitado); el celular siempre reemplaza con el último estado, nunca guarda historial local
- [ ] Detección de entrada/salida de Región usa geofencing nativo del SO (Android GeofencingClient / iOS CLLocationManager) en vez de polling continuo en foreground service
- [ ] Dentro de una región activa, la detección de geotriggers (radio chico) mantiene precisión vía polling fino — no se degrada por pasar a geofencing nativo a nivel región
- [ ] En iOS, el sistema nunca intenta monitorear más de ~19 regiones/triggers simultáneos (límite duro de CoreLocation es 20) — ventana deslizante que rota el set activo según posición
- [ ] El audio del geotrigger más cercano se precarga antes de que el usuario entre a su radio, para eliminar la latencia de `setFilePath()` en el momento del disparo
- [ ] El contenido (audio) de las obras de una región se descarga o marca para descarga al entrar a esa región con señal suficiente, en vez de requerir conectividad en el punto exacto de la obra

### Out of Scope

- Interfaz web de edición de obras (RF-02: reemplazar audio, ajustar geolocalización, editar metadata) — deferido a un milestone siguiente una vez que la infraestructura de sync esté sólida; este milestone construye el backend y el pipe de sync, no la UI web
- Multi-usuario / apertura pública (v1 del ERS) — v0 sigue siendo de un solo editor
- Resolución de conflictos multi-editor — no aplica con un solo editor
- Creación de obras nuevas desde la web sin grabación de campo (RF-05) — depende de que exista la web, fuera de alcance
- Elegir stack de backend definitivo ahora — se arranca con algo local para desarrollo y se resuelve durante la fase de research/planning de ese frente, con más contexto técnico (candidatos relevados: VPS propio, Postgres gestionado tipo Supabase/Neon, Vercel)

## Context

**Origen:** hay un ERS (Especificación de Requisitos del Sistema, v0.2 draft) en Notion que describe la arquitectura target de sincronización bidireccional celular↔servidor↔web con versionado. Este milestone cubre la mitad "celular + backend de sync" de ese ERS; la mitad "web de edición" queda para después.

**Auditoría de código ya hecha (en la conversación previa, no re-derivar):**
- `lib/data/datasources/local/app_database.dart`: SQLite con tablas `audio_assets`, `geo_triggers`, `geo_paths`, `regions`, `sync_outbox`, `sync_state`. `region_id` es FK nullable en `geo_triggers`. **Riesgo crítico**: si `openDatabase` falla, el código borra y recrea la DB sin backup (líneas ~38-53). `recreateForTesting()` e `importDatabase()` están conectados a botones reales en `data_browser_page.dart` sin confirmación.
- `lib/domain/usecases/monitor_user_location_usecase.dart` + `lib/core/services/geofence_background_service.dart`: hoy usan el paquete `geofence_service` (polling continuo dentro de un foreground service con `interval` fijo), no geofencing nativo real. `lib/core/background/background_poller.dart` (`BackgroundAdaptivePoller`) tiene lógica de tendencia (acercándose/alejándose) ya escrita pero está comentada en `main.dart` y no registrada en el service locator — código muerto que puede servir de referencia.
- `lib/core/services/audio_player_service.dart`: `loadPath()`/`setFilePath()` corre recién en el momento del disparo del trigger, sin precarga — causa raíz más probable del bug de reproducción no confiable.
- `lib/data/models/audio_asset_model.dart` / `audio_local_data_source.dart`: el campo `remote_url` existe en el esquema pero el insert real siempre graba `null` — no hay ninguna lógica de descarga implementada hoy. El hook de entrada a región (`onRegionChange` en `geofence_background_service.dart`) ya existe y podría disparar la descarga.
- `lib/presentation/pages/home_page_impl.dart`: `DiagnosticsPanel` está embebido incondicionalmente en la HomePage — no hay flavor, dart-define ni toggle runtime hoy.
- `lib/data/sync/`: `RunSyncUseCase` solo hace push (`pushOutboxOnce`) contra `SyncApiStub`, que simula acks sin red real. `pullChanges()` existe en la interfaz `SyncApi` pero nadie lo invoca — sync es 100% unidireccional hoy pese a que el modelo de datos ya está preparado para bidireccional.

**Research externo ya hecho (no re-derivar):**
- Android `GeofencingClient`: bajo consumo, el OS despierta la app aunque esté cerrada, pero en background chequea "cada un par de minutos" (no instantáneo). Límite: 100 geofences por app.
- iOS `CLLocationManager` region monitoring: límite duro de 20 regiones simultáneas por app — mucho más estricto que Android. Requiere ventana deslizante (patrón estándar de la industria, usado por SDKs comerciales como Radar) que registra solo las ~15-19 regiones/triggers más cercanos y rota el set.
- Plugin Flutter `native_geofence` (MIT, activamente mantenido a mediados de 2026): envuelve `GeofencingClient` + `CLLocationManager` reales, funciona con la app totalmente cerrada, persiste geofences tras reboot en Android. Candidato directo para reemplazar `geofence_service`.
- Tensión a resolver en el diseño: geofencing nativo ahorra batería pero es más lento/impreciso (debounce ~20-30s, chequeo cada par de minutos en background) — con triggers de radio chico (12m) puede fallar disparos si se usa para todo. Por eso el enfoque acordado es híbrido: nativo solo a nivel Región (radio grande), polling fino solo dentro de una región activa para los triggers.

## Constraints

- **Integridad de datos**: cero pérdida de datos ya existentes en el celular del usuario — es la restricción más alta de este milestone, por encima de cualquier otra prioridad de features.
- **Usuario único (v0)**: un solo editor/usuario en todo el sistema — no diseñar para resolución de conflictos concurrentes ni multi-dispositivo todavía (RNF-02 del ERS).
- **Costo**: solución de bajo costo mientras el proyecto no tiene financiamiento confirmado (RNF-04 del ERS) — influye en la elección de backend cuando se resuelva.
- **Conectividad intermitente**: Lago Puelo / Comarca Andina tiene zonas sin señal — el diseño de sync y de descarga por región debe tolerar conexión intermitente, no asumir conectividad constante.
- **Plataformas**: Android e iOS (Flutter) — cualquier mecanismo de background/geofencing tiene que funcionar en ambos, con las limitaciones de cada uno (iOS: 20 regiones máx.).
- **Proceso de ejecución**: cada fase de ejecución de este milestone debe incluir una auditoría con la skill `ponytail` (detectar y corregir over-engineering) como parte de su checklist, no solo al cierre del milestone — preferencia explícita del usuario.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Backend real: local/a definir durante la fase, no elegido ahora | Faltan datos de volumen/costo para decidir entre VPS propio, Postgres gestionado o Vercel; no bloquear el arranque del milestone por esto | — Pending |
| Web de edición fuera de alcance de este milestone | El usuario priorizó blindar sync + celular primero; la web depende de que el backend/API de sync exista y esté probado | ✓ Good |
| Versionado: celular reemplaza (sin historial local), servidor guarda 1 versión anterior por entidad | Evita explotar almacenamiento en el celular; alcanza para el caso de uso de un solo editor (RNF-02) | ✓ Good |
| Background híbrido: geofencing nativo a nivel Región + polling fino dentro de región activa | Resuelve la tensión batería-vs-precisión encontrada en el research; evoluciona el esquema de dos niveles que ya existía en el modelo de datos en vez de descartarlo | ✓ Good |
| Dashboard usuario/debug: toggle en runtime, no flavors de Flutter | v0 es de un solo usuario que cumple ambos roles (graba en campo y prueba la experiencia final); flavors son sobre-ingeniería hasta que haya un usuario final real no técnico (v1) | ✓ Good |
| Ponytail como parte del checklist de cada fase de ejecución | Preferencia explícita del usuario para mantener el código lo más simple posible en cada entrega, no solo al final | ✓ Good |
| Acciones destructivas de debug (recrear/importar BD): eliminadas por completo en vez de gateadas con confirmación | Reemplaza la redacción original del requirement; alineado con memoria de feedback del proyecto (no automatizar rutas destructivas, ni con confirmación) | ✓ Good |
| Confirmación humana en dispositivo real de la recuperación de BD corrupta: diferida, no bloquea el cierre de Fase 1 | El celular real del usuario es la única copia de datos de campo — no quiso arriesgarla corrompiéndola a propósito, y declinó la alternativa de probarlo en un emulador. La lógica de rename-not-delete está cubierta por tests automatizados (`db_recovery_test.dart`, verde) | ✓ Good — riesgo aceptado conscientemente, registrado en `01-HUMAN-UAT.md` |

## Current State

**Fase 1 (Blindaje de Datos y Separación Debug/Usuario) completa** (2026-08-28): recuperación no destructiva de BD, eliminación de acciones destructivas del panel de debug, y toggle runtime debug/usuario — todo validado en código y tests; un ítem de confirmación manual en dispositivo quedó diferido por decisión del usuario. Próximo: Fase 2 (Backend Real + Push Sync).

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-28 after Phase 1 completion*
