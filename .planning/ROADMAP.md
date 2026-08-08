# Roadmap: Cíngula App — Sync bidireccional, background real y descarga por región

## Overview

Este milestone blinda primero la integridad de datos ya en el celular (porque cada fase siguiente toca la DB con más frecuencia), después construye un backend real con sync push-then-pull sobre el outbox ya existente, reemplaza el polling continuo por geofencing nativo híbrido (región nativa + trigger fino), y por último cierra el círculo con precarga de audio y descarga de contenido por región — apoyándose en el pull sync para tener `remote_url` real. El toggle runtime debug/usuario, al ser pequeño y ortogonal, se resuelve junto con el hardening de datos en la Fase 1 porque ambos tocan el mismo panel de debug.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Blindaje de Datos y Separación Debug/Usuario** - La app nunca pierde datos existentes al fallar la apertura de la DB, las acciones destructivas de debug piden confirmación, y un toggle runtime separa dashboard de usuario final del panel de debug.
- [ ] **Phase 2: Backend Real + Push Sync** - Cada escritura local llega a un backend real vía el outbox existente, con push idempotente, reintentos con backoff, autenticación mínima y estado de sync honesto y visible.
- [ ] **Phase 3: Sync Bidireccional (Pull)** - Cambios hechos fuera del celular llegan de vuelta vía pull, sin arriesgar nunca datos locales aún no subidos en el primer sync.
- [ ] **Phase 4: Reemplazo de Geofencing Híbrido** - Detección de región vía geofencing nativo del SO en vez de polling continuo, manteniendo precisión de triggers de radio chico y respetando el límite de 20 regiones de iOS.
- [ ] **Phase 5: Precarga de Audio + Descarga por Región** - El audio del trigger más cercano se precarga antes del disparo, y el contenido de una región se descarga por adelantado de forma resumible y siempre actualizada.

## Phase Details

### Phase 1: Blindaje de Datos y Separación Debug/Usuario
**Goal**: La app nunca destruye datos existentes en el celular ante un fallo, las acciones destructivas del panel de debug requieren confirmación explícita, y un toggle en runtime separa el dashboard de usuario final del panel de debug.
**Depends on**: Nothing (first phase)
**Requirements**: DATA-01, DATA-02, UI-01
**Success Criteria** (what must be TRUE):
  1. Ante un fallo forzado de apertura de la base de datos (ej. archivo corrupto), la app genera un backup con timestamp antes de cualquier fallback destructivo — nunca borra/recrea sin respaldo previo.
  2. No existe ninguna acción de "recrear DB" ni "importar DB" en el panel de debug ni en el API de `AppDatabase` — se eliminan por completo en vez de protegerse con confirmación (D-03/D-04 del 01-CONTEXT.md, que reemplaza la redacción original de este criterio).
  3. Un toggle en runtime alterna entre el dashboard de usuario final y el panel de debug sin necesidad de rebuild/flavor, y el estado del toggle persiste entre reinicios de la app.
  4. Ninguna ruta destructiva sobre la base de datos queda alcanzable desde la UI, en ninguno de los dos modos del toggle.
**Plans**: 4 plans
Plans:
- [x] 01-01-PLAN.md — Recuperación rename-not-delete de la BD + eliminación de las acciones destructivas de debug (DATA-01, DATA-02)
- [x] 01-02-PLAN.md — Piezas del toggle: AppModeConfig (persistencia), HiddenTapGesture (5 taps), UserModeView (estética de usuario final) (UI-01)
- [x] 01-03-PLAN.md — Cableado en HomePage: rama debug/usuario, gesto oculto y banner de recuperación (UI-01, DATA-01)
- [ ] 01-04-PLAN.md — Auditoría ponytail + QA manual en dispositivo (DATA-01, DATA-02, UI-01)
**UI hint**: yes
**Ponytail audit**: Requerido como parte del checklist de esta fase (y de todas las siguientes) antes de marcarla completa — revisar el código nuevo en busca de sobre-ingeniería y simplificar antes del cierre (ver PROJECT.md Constraints).

### Phase 2: Backend Real + Push Sync
**Goal**: Cada escritura local (audio_assets, geo_triggers, geo_paths, regions) llega de forma confiable a un backend real a través del outbox ya existente, con estado de sync visible y honesto.
**Depends on**: Phase 1
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-06, SYNC-07, SYNC-08
**Success Criteria** (what must be TRUE):
  1. Crear o editar un geo_trigger (u otra entidad sincronizada) estando online hace que aparezca en el estado guardado del backend (verificable por API/DB) sin disparar sync manualmente.
  2. Matar la app en medio de un push y reabrirla no genera filas duplicadas en el backend — reintentar el push del mismo uuid+logical_version es un no-op.
  3. Escribir estando offline encola los cambios en el outbox; al recuperar conectividad, los pendientes se envían con reintento y backoff (fallas de red no pierden escrituras ni cuelgan el loop de sync).
  4. Pedidos al backend sin API key/bearer token válido son rechazados.
  5. La interfaz existente muestra la cantidad real de pendientes en el outbox y el timestamp del último sync exitoso — nunca indica "todo sincronizado" cuando hay escrituras sin pushear.
  6. Después de varios pushes sobre la misma entidad, el backend conserva solo el estado actual más una versión anterior (verificable inspeccionando el storage del backend).
**Plans**: TBD
**Ponytail audit**: Requerido como parte del checklist de esta fase antes de marcarla completa — revisar el código nuevo en busca de sobre-ingeniería y simplificar antes del cierre (ver PROJECT.md Constraints).

### Phase 3: Sync Bidireccional (Pull)
**Goal**: El celular puede recibir cambios hechos fuera de él vía pull, sin que un pull temprano arriesgue nunca datos locales todavía no subidos.
**Depends on**: Phase 2
**Requirements**: SYNC-04, SYNC-05
**Success Criteria** (what must be TRUE):
  1. Un cambio hecho directamente en el backend (simulando una edición externa) se refleja en el celular tras el siguiente ciclo de sync, sin que el usuario reimporte nada manualmente.
  2. Sembrar un celular nuevo con datos locales preexistentes y conectarlo por primera vez a un backend vacío hace que el push drene por completo antes de que corra el primer pull — ninguna fila local se pierde ni se sobrescribe silenciosamente.
  3. Una fila local con cambios pendientes en el outbox no es sobrescrita por un pull entrante de esa misma fila hasta que el cambio local se haya pusheado.
**Plans**: TBD
**Ponytail audit**: Requerido como parte del checklist de esta fase antes de marcarla completa — revisar el código nuevo en busca de sobre-ingeniería y simplificar antes del cierre (ver PROJECT.md Constraints).

### Phase 4: Reemplazo de Geofencing Híbrido
**Goal**: La detección de entrada/salida de región usa geofencing nativo del SO (no polling continuo en foreground), mientras la precisión de triggers de radio chico dentro de una región activa y el límite de 20 regiones de iOS quedan resueltos.
**Depends on**: Phase 1
**Requirements**: GEO-01, GEO-02, GEO-03, GEO-04
**Success Criteria** (what must be TRUE):
  1. Matar el proceso de la app y forzar su cierre, y luego entrar (física o simuladamente) a una región, igual dispara un evento de entrada a región — el SO despierta la app sin necesidad de un foreground service de polling corriendo.
  2. Dentro de una región activa, el polling fino sigue detectando triggers de radio chico (~12m) de forma confiable, sin regresión de precisión respecto a hoy.
  3. Con 25+ regiones/triggers sembrados y movimiento simulado entre ellos, nunca se registran más de ~19 simultáneamente en CLLocationManager (verificable vía contador/log de debug, sin crashear).
  4. Cruzar repetidamente el borde de un trigger (ruido GPS) no dispara entradas/salidas falsas en rápida sucesión — el debounce/histéresis las filtra.
**Plans**: TBD
**Ponytail audit**: Requerido como parte del checklist de esta fase antes de marcarla completa — revisar el código nuevo en busca de sobre-ingeniería y simplificar antes del cierre (ver PROJECT.md Constraints).

### Phase 5: Precarga de Audio + Descarga por Región
**Goal**: El audio del trigger más cercano está listo para reproducirse al instante al llegar, y el contenido de una región se descarga por adelantado para que la reproducción nunca dependa de conectividad en el punto exacto del trigger.
**Depends on**: Phase 1, Phase 3
**Requirements**: AUDIO-01, DOWNLOAD-01, DOWNLOAD-02, DOWNLOAD-03, DOWNLOAD-04
**Success Criteria** (what must be TRUE):
  1. Al acercarse al radio de un geotrigger, el audio ya está cargado en el reproductor (sin latencia de `setFilePath()`) en el momento exacto de la entrada.
  2. Entrar a una región con señal suficiente descarga automáticamente el contenido de audio de esa región (o lo marca claramente para descarga) sin acción del usuario.
  3. Matar la app o perder conectividad en medio de una descarga y reabrir/reconectar más tarde resume la descarga sin dejar nunca un archivo a medio escribir marcado como disponible.
  4. Una descarga que falló estando offline se reintenta automáticamente al volver la señal, sin necesidad de volver a entrar a la región.
  5. Cuando el `logical_version` de una entidad cambia en el backend (vía sync), el audio ya descargado para esa entidad se invalida y se vuelve a descargar, nunca queda obsoleto en silencio.
**Plans**: TBD
**Ponytail audit**: Requerido como parte del checklist de esta fase antes de marcarla completa — revisar el código nuevo en busca de sobre-ingeniería y simplificar antes del cierre (ver PROJECT.md Constraints).

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

Nota de dependencias: la Fase 4 depende solo de la Fase 1 (es arquitectónicamente independiente de sync) y podría ejecutarse en paralelo con las Fases 2-3 si se decide correrlas como streams separados; se numera después de la 3 siguiendo el orden de build sugerido por research (riesgo de dispositivo real aislado de backend work), no por una dependencia de datos dura.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Blindaje de Datos y Separación Debug/Usuario | 0/4 | Planned | - |
| 2. Backend Real + Push Sync | 0/TBD | Not started | - |
| 3. Sync Bidireccional (Pull) | 0/TBD | Not started | - |
| 4. Reemplazo de Geofencing Híbrido | 0/TBD | Not started | - |
| 5. Precarga de Audio + Descarga por Región | 0/TBD | Not started | - |
