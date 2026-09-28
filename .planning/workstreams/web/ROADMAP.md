# Roadmap: Cíngula — workstream `web`, milestone v1.0 (Web de gestión, lectura)

## Overview

Este milestone cierra primero el contrato de lectura que el workstream `app` necesita (pull + auth dual-key), porque desbloquea su Fase 3 y no depende de nada nuevo. Después resuelve la única pieza de infraestructura de alta incertidumbre (servir la SPA y el backend desde el mismo proyecto Vercel sin romper `/sync/push` en producción, con un spike de `vercel dev` explícito), recién entonces construye la web de solo lectura sobre una base de deploy y auth ya probada, y cierra con el storage de audio — cuya única pieza de UI (reproducir en la web) depende de que la web ya exista. `WEB_API_KEY` (backend) se resuelve junto con el pull porque es una modificación mínima al mismo `auth.js` que el pull necesita usar; la pantalla de acceso (UI) se resuelve junto con la web, no antes, porque no tiene sentido construirla sin nada detrás.

## Phases

**Phase Numbering:**
- Numeración continua sobre la que ya usa el workstream `web` (arranca en 10; `app` usa 1–5 + decimales — ver PROJECT.md → Workstreams).
- Integer phases (10, 11, 12…): planned milestone work.
- Decimal phases (10.1, 10.2…): urgent insertions (marked with INSERTED).

- [x] **Phase 10: Pull cerrado + Auth dual-key** - El backend sirve `GET /sync/pull` paginado con watermark a cualquier cliente autenticado con `SYNC_API_KEY` o `WEB_API_KEY`, y el contrato queda publicado para que `app` programe su Fase 3. (completed 2026-09-26)
- [ ] **Phase 11: Infra de deploy (mismo proyecto Vercel)** - La web y el backend conviven en un solo proyecto Vercel sin romper `/sync/push` en producción, Preview nunca toca la base de producción, y `web/` queda libre de restos de Flutter.
- [ ] **Phase 12: Web de lectura** - El usuario abre la web, se autentica con `WEB_API_KEY`, y ve todo el contenido del servidor (mapa, recorridos, obras, artistas, paths, audios, estado de sync).
- [ ] **Phase 13: Storage de audio + reproducción en la web** - Los audios tienen subida autorizada a R2 con checksum y descarga firmada, y la web reproduce cualquier audio que ya tenga archivo.

## Phase Details

### Phase 10: Pull cerrado + Auth dual-key
**Goal**: El backend puede servir a cualquier cliente autenticado (celular o web) todos los cambios del servidor vía pull paginado con watermark, con auth dual-key, dejando el contrato cerrado para que `app` programe su Fase 3.
**Depends on**: Nothing (usa schema y `spec.js` ya existentes; ninguna otra fase de este milestone la bloquea)
**Requirements**: PULL-01, PULL-02, PULL-03, PULL-04, PULL-05, AUTH-01
**Success Criteria** (what must be TRUE):
  1. Un cliente autenticado con `SYNC_API_KEY` o `WEB_API_KEY` que llama `GET /sync/pull?cursor=0&limit=N` recibe todas las filas de las 7 tablas (incluidas las borradas) ordenadas por `change_seq`, paginando con `hasMore` hasta agotar el set; `payload`, timestamps y `change_seq`/`serverCursor` respetan el mismo formato que el push (columnas de `spec.js`, epoch, strings).
  2. Una transacción de push que comitea tarde (simulada en un test de integración contra una rama Neon dev) nunca queda salteada por un pull posterior — el watermark asegura que el cursor jamás avanza más allá de lo ya asentado.
  3. `GET /sync/state` incluye `recorridos` en el cálculo de `serverCursor` y `lastSyncAt` (hoy no lo hace).
  4. Un pedido cuya key no coincide con ninguna variable de entorno configurada (o con ninguna de las dos configurada) es rechazado — nunca abre por default.
  5. El contrato de pull (formato, paginación, watermark) queda publicado en "ERS · Backend — protocolo de sync" (Notion) antes de cerrar la fase, listo para que `app` Fase 3 programe contra él.
**Plans**: 4 plans
Plans:
- [x] 10-01-PLAN.md — auth dual-key (`apiKeyRole`, 403 web en push), advisory lock exclusivo en push, `/sync/state` con recorridos (wave 1)
- [x] 10-02-PLAN.md — `GET /sync/pull` con lock compartido + test de concurrencia PULL-03 contra Neon dev (wave 2)
- [x] 10-03-PLAN.md — contrato de pull en Notion, ADR-007 solo lectura, verificación ADR-012, notas inline en research (wave 1)
- [x] 10-04-PLAN.md — auditoría ponytail + compuerta humana (suite contra Neon dev sin salteados) + cierre de VALIDATION (wave 3)
**Ponytail audit**: Requerido como último plan/tarea de esta fase, antes de la compuerta humana de cierre — revisar el código nuevo (query de pull, watermark, dual-key) en busca de sobre-ingeniería y simplificar antes de dar la fase por cerrada.
**Cross-workstream**: Desbloquea `app` Phase 3 (pull en el celular) — `app` no programa contra `/sync/pull` hasta que esta fase publique el contrato (PULL-05).

### Phase 11: Infra de deploy (mismo proyecto Vercel)
**Goal**: La web y el backend se sirven desde un mismo proyecto Vercel, `/sync/*` sigue llegando a las funciones sin cambios de comportamiento, Preview nunca usa la base de producción, y `web/` queda libre de restos de Flutter para alojar la SPA nueva.
**Depends on**: Nothing nuevo (puede ejecutarse en paralelo con la Phase 10; comparten solo `auth.js`, que ninguna de las dos fases modifica dos veces)
**Requirements**: INFRA-01, INFRA-02, INFRA-03
**Success Criteria** (what must be TRUE):
  1. Un spike de `vercel dev` (al arrancar la fase, antes de comprometerse a un mecanismo) valida cuál de los mecanismos de ruteo propuestos (shims de re-export, `functions` glob, o mover `backend/api/` a la raíz) sirve tanto `/sync/*` como el resto del sitio desde el mismo proyecto.
  2. Tras el cambio de Root Directory/`vercel.json`, `GET /sync/state` en un deploy de Preview responde JSON válido (no HTML) y el push real del celular contra producción sigue funcionando sin ningún cambio en la app — verificado como smoke test explícito antes de cualquier merge a `main`.
  3. Un deploy Preview usa la `DATABASE_URL` de una rama Neon dev — verificado inspeccionando la variable de entorno real del deploy, nunca asumido — y nunca la de producción.
  4. Los restos de Flutter Web en `web/` (`index.html`, `manifest.json`, `icons/`) fueron eliminados y la carpeta resultante queda lista para alojar el código de la SPA de la Phase 12.
**Plans**: 5 plans
Plans:
- [x] 11-01-PLAN.md — Wave 0: `smoke-preview.sh` (solo GET, 401/200 JSON) + chequeo de CI + borrado de restos de Flutter web (INFRA-03) (wave 1)
- [x] 11-02-PLAN.md — relevamiento del proyecto Vercel (humano), `check-preview-db.sh`, scopes de `DATABASE_URL` Production-only / Preview+Development = rama Neon dev (INFRA-02) (wave 1)
- [x] 11-03-PLAN.md — shims `web/api/sync/*` + `web/vercel.json`, spike `vercel dev` en proyecto descartable (d -> a; b descartado; c solo con decisión del usuario) (wave 2)
- [ ] 11-04-PLAN.md — Root Directory = `web` (humano), Preview real: smoke + INFRA-02 sobre el deploy + producción viva intacta (wave 3)
- [ ] 11-05-PLAN.md — auditoría ponytail (borra `backend/vercel.json`) + compuerta humana: celular real antes/después del merge a `main` + cierre de VALIDATION (wave 4)
**Ponytail audit**: Requerido como último plan/tarea de esta fase, antes de la compuerta humana de cierre — revisar la configuración de ruteo nueva en busca de mecanismos más complejos de lo necesario (p.ej. mover archivos que no hacía falta mover) y simplificar antes de dar la fase por cerrada.

### Phase 12: Web de lectura
**Goal**: El usuario abre la web, se autentica una vez con `WEB_API_KEY`, y ve todo el contenido del servidor (recorridos, obras, artistas, paths, audios) sobre mapa y en detalle, leyendo por el mismo protocolo de pull que usa el celular (ADR-004).
**Depends on**: Phase 10 (contrato de pull cerrado), Phase 11 (deploy funcionando y `WEB_API_KEY` aceptada por el backend)
**Requirements**: AUTH-02, WEB-01, WEB-02, WEB-03, WEB-04, WEB-05, WEB-06, WEB-07, WEB-08
**Success Criteria** (what must be TRUE):
  1. El usuario ingresa `WEB_API_KEY` una vez en una pantalla de acceso (guardada en `sessionStorage`, nunca embebida en el bundle de la web) y accede al resto de la web sin volver a tipearla en esa sesión.
  2. El usuario ve un mapa general con la cobertura, paths y triggers (círculos por `radius_meters`) de las obras, filtrable por recorrido, y puede navegar desde el mapa al detalle de cada obra.
  3. El usuario ve listado y detalle de recorridos (con créditos calculados por unión de los artistas de sus obras), artistas (con sus obras), obras (filtrables por recorrido y visibilidad, con cobertura y paths), paths (kind, audio, grabación de origen, tolerance_meters, triggers en mapa y lista ordenada por position) y audios (metadata y en qué paths se usa cada uno).
  4. El usuario ve el estado de sync de la web (cursor, momento del último pull, errores explícitos) con el mismo criterio de "estado honesto" que el celular, y ninguna vista de la web muestra filas con `deleted_at`.
**Plans**: TBD
**Ponytail audit**: Requerido como último plan/tarea de esta fase, antes de la compuerta humana de cierre — revisar el código nuevo (SPA completa) en busca de sobre-ingeniería (p.ej. estado global innecesario, capas de abstracción sin segundo consumidor) y simplificar antes de dar la fase por cerrada.
**UI hint**: yes

### Phase 13: Storage de audio + reproducción en la web
**Goal**: Los audios tienen un flujo de subida autorizada directo cliente→R2 con checksum verificado y URL de descarga firmada y temporal, y la web puede reproducir cualquier audio que ya tenga archivo en storage.
**Depends on**: Phase 10/11 (auth dual-key ya aceptada por el backend); Phase 12 (STOR-04 es una feature de la web ya construida — no tiene sentido antes de que la web exista)
**Requirements**: STOR-01, STOR-02, STOR-03, STOR-04
**Success Criteria** (what must be TRUE):
  1. Un cliente autenticado pide una URL presignada de PUT para un `storage_key` nuevo, y R2 rechaza cualquier intento de sobrescribir un objeto existente con ese `storage_key`.
  2. Una subida cuyo checksum SHA-256 declarado no coincide con el del archivo real es rechazada por el storage, no aceptada silenciosamente.
  3. Un cliente autenticado obtiene una URL de descarga firmada y temporal para un audio — los objetos en R2 no son accesibles públicamente sin esa URL.
  4. El usuario reproduce desde la web un audio que tiene archivo en storage, y ve un indicador claro (no un error genérico ni una falla silenciosa) cuando el audio listado todavía no tiene archivo.
**Plans**: TBD
**Ponytail audit**: Requerido como último plan/tarea de esta fase, antes de la compuerta humana de cierre — revisar el flujo de subida/descarga y la integración en la web en busca de sobre-ingeniería (p.ej. verificación server-side redundante, endpoints sin segundo consumidor) y simplificar antes de dar la fase por cerrada.
**Cross-workstream**: Desbloquea `app` Phase 2.2 (subida de audios desde el celular) — comparte el mismo endpoint de autorización de subida (`POST /api/storage/upload-url`).

## Progress

**Execution Order:**
Phase 10 y Phase 11 pueden ejecutarse en paralelo (no comparten archivos de negocio); Phase 12 depende de ambas; Phase 13 depende de 10/11 para auth y de 12 para su única pieza de UI (STOR-04). Orden numérico de ejecución por defecto: 10 → 11 → 12 → 13.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 10. Pull cerrado + Auth dual-key | 4/4 | Complete    | 2026-09-26 |
| 11. Infra de deploy (mismo proyecto Vercel) | 3/5 | In Progress|  |
| 12. Web de lectura | 0/TBD | Not started | - |
| 13. Storage de audio + reproducción en la web | 0/TBD | Not started | - |

## Backlog

Ninguno todavía en este workstream.
