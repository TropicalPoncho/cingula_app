# Requirements: Cíngula App — Sync bidireccional, background real y descarga por región

**Defined:** 2026-08-08
**Core Value:** Que la app siga siendo confiable en el bolsillo del usuario mientras se construye la infraestructura de sync — ningún cambio de este milestone puede arriesgar los datos que ya existen en el celular.

## v1 Requirements

Requirements para este milestone. Cada uno mapea a fases del roadmap.

### Data Integrity (DATA)

- [x] **DATA-01**: La app nunca borra/recrea la base de datos local sin respaldo previo, ni siquiera ante fallo de apertura
- [x] **DATA-02**: Las acciones destructivas de la UI de debug (recrear DB, importar DB) piden confirmación explícita antes de ejecutarse

### Sync (SYNC)

- [ ] **SYNC-01**: Un backend real implementa el contrato de outbox ya existente en el celular (push), reemplazando el `SyncApiStub`
- [ ] **SYNC-02**: El push es idempotente — el servidor dedupe por `uuid` + `logical_version`, con ack por fila individual
- [ ] **SYNC-03**: El push reintenta con backoff exponencial + jitter, distinguiendo errores transitorios (reintentar) de terminales (no reintentar)
- [ ] **SYNC-04**: El pull sync se invoca de verdad — sync es bidireccional, no solo push; reemplaza fila local con la última versión del servidor
- [ ] **SYNC-05**: En el primer sync de un celular con datos preexistentes, el push drena por completo antes de correr el primer pull (evita que un pull temprano sobrescriba datos locales aún no subidos)
- [ ] **SYNC-06**: El backend guarda el estado actual + 1 versión anterior por entidad, sin historial ilimitado
- [ ] **SYNC-07**: El backend nuevo exige autenticación mínima (API key/bearer token), aunque sea de un solo usuario
- [ ] **SYNC-08**: El usuario puede ver el estado real de sync (cantidad de pendientes en el outbox + timestamp del último sync exitoso), sin indicadores falsos de "todo sincronizado"

### Geofencing (GEO)

- [ ] **GEO-01**: La detección de entrada/salida de Región usa geofencing nativo del SO (Android GeofencingClient / iOS CLLocationManager) en vez de polling continuo en foreground service
- [ ] **GEO-02**: Dentro de una región activa, el polling fino se mantiene para la precisión de triggers de radio chico
- [ ] **GEO-03**: En iOS, nunca se monitorean más de ~19 regiones/triggers simultáneos — ventana deslizante que rota el set activo según la posición del usuario
- [ ] **GEO-04**: La detección de triggers tiene debounce/histéresis para evitar disparos falsos por ruido GPS en el borde del radio

### Audio (AUDIO)

- [ ] **AUDIO-01**: El audio del geotrigger más cercano se precarga en el reproductor antes de que el usuario entre a su radio

### Download por región (DOWNLOAD)

- [ ] **DOWNLOAD-01**: El audio de las obras de una región se descarga (o se marca para descarga) al entrar a esa región con señal suficiente
- [ ] **DOWNLOAD-02**: Las descargas son resumibles y atómicas (archivo temporal + rename), nunca dejan un archivo a medio escribir marcado como disponible
- [ ] **DOWNLOAD-03**: Las descargas pendientes se reintentan oportunísticamente cuando vuelve la señal, no solo una vez al entrar a la región
- [ ] **DOWNLOAD-04**: El contenido descargado se invalida y vuelve a descargar cuando cambia `logical_version` en el servidor

### Dashboard (UI)

- [ ] **UI-01**: Un toggle en runtime (no flavors de Flutter) alterna entre el dashboard de usuario final y el panel de debug

## v2 Requirements

Reconocidos pero diferidos, no forman parte del roadmap de este milestone.

### Geofencing

- **GEO-V2-01**: Preload predictivo de múltiples triggers (no solo el más cercano) a lo largo de un camino
- **GEO-V2-02**: Radio de trigger adaptativo según precisión GPS en vivo

### Download

- **DOWNLOAD-V2-01**: Gestión de cuota de almacenamiento / auto-eviction de audio descargado viejo
- **DOWNLOAD-V2-02**: Preferencia de descarga solo por Wi-Fi

## Out of Scope

| Feature | Reason |
|---------|--------|
| Interfaz web de edición de obras (RF-02) | Deferido a un milestone siguiente, una vez que la infraestructura de sync esté sólida y probada |
| Multi-usuario / apertura pública (v1 del ERS) | v0 sigue siendo de un solo editor |
| Resolución de conflictos multi-editor (CRDT, 3-way merge, OT) | No hay problema de concurrencia que resolver con un solo editor; last-write-wins del servidor es la elección correcta, no un compromiso |
| Historial de versiones ilimitado en el servidor | Decidido explícitamente: actual + 1 anterior alcanza para un solo editor, evita explotar almacenamiento |
| Creación de obras nuevas desde la web (RF-05) | Depende de que exista la web de edición, fuera de alcance |
| Sync en tiempo real / push por websocket | No hay contraparte viva (web editor) contra la cual sincronizar en vivo todavía |
| Flavors de Flutter para separar debug/usuario | Sobre-ingeniería para v0 de un solo usuario que cumple ambos roles; toggle runtime alcanza |
| Elegir stack de backend definitivo ahora | Se arranca con algo local para desarrollo; se resuelve durante research/planning de la fase de sync (candidatos: Neon+Vercel recomendado por research, VPS propio, Supabase) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DATA-01 | Phase 1 | Complete |
| DATA-02 | Phase 1 | Complete |
| UI-01 | Phase 1 | Pending |
| SYNC-01 | Phase 2 | Pending |
| SYNC-02 | Phase 2 | Pending |
| SYNC-03 | Phase 2 | Pending |
| SYNC-06 | Phase 2 | Pending |
| SYNC-07 | Phase 2 | Pending |
| SYNC-08 | Phase 2 | Pending |
| SYNC-04 | Phase 3 | Pending |
| SYNC-05 | Phase 3 | Pending |
| GEO-01 | Phase 4 | Pending |
| GEO-02 | Phase 4 | Pending |
| GEO-03 | Phase 4 | Pending |
| GEO-04 | Phase 4 | Pending |
| AUDIO-01 | Phase 5 | Pending |
| DOWNLOAD-01 | Phase 5 | Pending |
| DOWNLOAD-02 | Phase 5 | Pending |
| DOWNLOAD-03 | Phase 5 | Pending |
| DOWNLOAD-04 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20 ✓
- Unmapped: 0

---
*Requirements defined: 2026-08-08*
*Last updated: 2026-08-08 after roadmap creation (5 phases, 100% coverage)*
