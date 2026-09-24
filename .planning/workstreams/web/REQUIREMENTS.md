# Requirements: Cíngula — workstream `web`, v1.0 Web de gestión (lectura)

**Defined:** 2026-09-23
**Core Value:** ver desde una web todo lo que hay en el servidor, leyendo por el mismo protocolo de sync que el celular (ADR-004), sin arriesgar nunca el sync del celular que ya está en producción.
**Fuentes:** ERS v0.3 · subpáginas Backend (BE-xx) y Web — Notion. Research: `research/SUMMARY.md`.

## Decisiones tomadas al definir el milestone (2026-09-23)

| Decisión | Por qué | Alternativa descartada | Riesgo mientras no se resuelva |
|---|---|---|---|
| Milestone solo de lectura: la web no escribe | El usuario quiere primero ver lo que hay; la escritura (ADR-006 etapas 1 y 2) se ve después | Etapa 1 de escritura en este milestone | Ninguno sobre datos (la web no escribe) |
| Storage de audio en **Cloudflare R2**, objetos privados | El mismo storage recibirá el backup de todas las grabaciones de campo (2.2 de `app`); Blob Hobby da 1GB, R2 10GB + egress gratis + `If-None-Match` y checksums S3 nativos | Vercel Blob (1GB) | Cuenta Cloudflare + token nuevos; va a ADR nuevo |
| Subida por **presigned PUT** directo cliente→R2 | Sirve igual desde navegador y desde Dart, sin SDK en el cliente | `handleUpload` / client token (requiere SDK JS) | — |
| Pull no saltea filas por commits concurrentes, garantizado con **advisory lock de Postgres** (push exclusivo, pull compartido) — ver ADR nuevo y `phases/10-pull-cerrado-auth-dual-key/10-CONTEXT.md` D-01 | `change_seq` se asigna antes del commit: sin la garantía, una transacción lenta puede commitear un seq menor al cursor ya entregado y el celular la saltearía para siempre | Margen de tiempo sobre `updated_at` (research inicial) — inválido: `updated_at` lo pone el cliente, no protege | Todo escritor nuevo (escritura de la web, scripts de datos) tiene que tomar el mismo lock o puede generar un salto |
| `web/` se reusa: se borran los restos de Flutter web | ADR-005 ubica la web de gestión en `web/`; los restos no se usan (app solo Android/iOS) | Nueva carpeta `admin/` | — |
| Fases desde la 10 | Evita choque con fases 1–5 de `app` | Empezar en 1 / en 6 | — |

## v1 Requirements

### Pull (BE-01, BE-05)

- [ ] **PULL-01**: Un cliente autenticado obtiene con `GET /sync/pull?cursor=&limit=` todas las filas de las 7 tablas con `change_seq > cursor`, ordenadas por `change_seq`, incluidas las borradas, en páginas con `hasMore` (BE-01)
- [ ] **PULL-02**: El `payload` del pull tiene el mismo formato que el del push (columnas de `spec.js`, timestamps en epoch segundos); `change_seq` y `serverCursor` viajan como string
- [x] **PULL-03**: Un pull paginado nunca saltea una fila por commits concurrentes (watermark), demostrado con un test de integración contra una rama de Neon dev
- [x] **PULL-04**: `GET /sync/state` tiene en cuenta `recorridos` para `serverCursor` y `lastSyncAt` (BE-05)
- [ ] **PULL-05**: El contrato de pull queda cerrado y publicado en "ERS · Backend — protocolo de sync" (Notion), para que la Fase 3 de `app` pueda programar contra él

### Acceso (BE-03)

- [x] **AUTH-01**: El backend acepta `WEB_API_KEY` además de `SYNC_API_KEY`, cada una revocable por separado; si una variable falta, esa clave no da acceso (nunca abre) (BE-03, ADR-007)
- [ ] **AUTH-02**: El usuario ingresa `WEB_API_KEY` una vez en una pantalla de acceso; ninguna clave va dentro del bundle de la web

### Infraestructura

- [ ] **INFRA-01**: La web y el backend se sirven desde el mismo proyecto Vercel, y `/sync/*` sigue llegando a las funciones: el push del celular funciona igual en producción después del cambio
- [ ] **INFRA-02**: Los deploys Preview usan una rama de Neon dev, nunca la `DATABASE_URL` de producción (verificado, no asumido) (ADR-005)
- [ ] **INFRA-03**: Los restos de Flutter web se eliminan y `web/` contiene la web de gestión

### Web de lectura

- [ ] **WEB-01**: El usuario ve un mapa general con la cobertura de cada obra, sus paths y sus triggers (círculos de `radius_meters`), puede filtrar por recorrido y navegar desde el mapa al detalle
- [ ] **WEB-02**: El usuario ve el listado y detalle de recorridos, con sus obras y sus créditos (unión de los artistas de sus obras, calculada)
- [ ] **WEB-03**: El usuario ve el listado y detalle de artistas, con las obras en las que figuran
- [ ] **WEB-04**: El usuario ve el listado de obras (filtrable por recorrido y visibilidad) y su detalle: visibilidad, recorrido, artistas, cobertura y paths
- [ ] **WEB-05**: El usuario ve el detalle de un path: `kind`, audio que suena, grabación de origen, `tolerance_meters`, y sus triggers en un mapa y en una lista ordenada por `position` (nombre, descripción, radio, `offset_ms`)
- [ ] **WEB-06**: El usuario ve el listado de audios con su metadata (título, descripción, `kind`) y en qué paths se usa cada uno
- [ ] **WEB-07**: El usuario ve el estado de sync de la web: cursor, momento del último pull y errores explícitos (mismo criterio de "estado honesto" que el celular)
- [ ] **WEB-08**: Ninguna vista muestra filas con `deleted_at`

### Storage de audio (BE-04)

- [ ] **STOR-01**: Un cliente autenticado obtiene una URL presignada para subir un archivo directo a R2, con un `storage_key` nuevo que no puede sobrescribir un objeto existente (ADR-003)
- [ ] **STOR-02**: La subida lleva un checksum SHA-256 que el storage verifica; un archivo que no coincide se rechaza
- [ ] **STOR-03**: Un cliente autenticado obtiene una URL de descarga firmada y temporal para un audio; los objetos no son públicos
- [ ] **STOR-04**: El usuario puede reproducir desde la web un audio que tenga archivo en storage (WEB-06); si no lo tiene, la web lo indica en vez de fallar

## Future Requirements

- Escritura desde la web, etapa 1 (recorridos, artistas, créditos, alta de audios) y etapa 2 (obras, paths, triggers, asignar audio a path) — ADR-006
- `staleIds` en el push (BE-02) — solo lo necesita la escritura
- Subida resumible / multipart para `.wav` grandes en conectividad intermitente — se define junto con la 2.2 de `app` (el cliente que la necesita)
- Ver y restaurar la versión anterior (`entity_prev`, RF-04) desde la web
- Monitoreo de uso del storage contra el free tier

## Out of Scope

| Feature | Reason |
|---------|--------|
| Subida de grabaciones desde el celular | Lado cliente de la 2.2, workstream `app` |
| Aplicar el pull en el celular | Fase 3 del workstream `app` |
| Filtro de pull por biblioteca del celular (2.1 D-15) | Un solo usuario en v0 |
| Multiusuario, login real, permisos | v1 del ERS |
| Modo offline de la web | ADR-008: la web es solo online |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PULL-01 | Phase 10 | Pending |
| PULL-02 | Phase 10 | Pending |
| PULL-03 | Phase 10 | Complete |
| PULL-04 | Phase 10 | Complete |
| PULL-05 | Phase 10 | Pending |
| AUTH-01 | Phase 10 | Complete |
| INFRA-01 | Phase 11 | Pending |
| INFRA-02 | Phase 11 | Pending |
| INFRA-03 | Phase 11 | Pending |
| AUTH-02 | Phase 12 | Pending |
| WEB-01 | Phase 12 | Pending |
| WEB-02 | Phase 12 | Pending |
| WEB-03 | Phase 12 | Pending |
| WEB-04 | Phase 12 | Pending |
| WEB-05 | Phase 12 | Pending |
| WEB-06 | Phase 12 | Pending |
| WEB-07 | Phase 12 | Pending |
| WEB-08 | Phase 12 | Pending |
| STOR-01 | Phase 13 | Pending |
| STOR-02 | Phase 13 | Pending |
| STOR-03 | Phase 13 | Pending |
| STOR-04 | Phase 13 | Pending |

**Coverage:**
- v1 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-09-23*
*Roadmap created: 2026-09-23 — 4 fases (10-13), cobertura 22/22*
