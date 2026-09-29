# Phase 10: Pull cerrado + Auth dual-key - Context

**Gathered:** 2026-09-23
**Status:** Ready for planning

<domain>
## Phase Boundary

El backend sirve `GET /sync/pull` paginado a cualquier cliente autenticado (celular con `SYNC_API_KEY`, web con `WEB_API_KEY`), con la garantía de que un pull nunca saltea una fila por commits concurrentes (PULL-03). `GET /sync/state` incluye `recorridos` (PULL-04). `WEB_API_KEY` se acepta con alcance de solo lectura (AUTH-01). El contrato queda publicado en Notion para que `app` Fase 3 programe contra él (PULL-05).

Fuera de esta fase: pantalla de acceso de la web (AUTH-02, Fase 12), ruteo/deploy (Fase 11), aplicar el pull en el celular (`app` Fase 3), cualquier escritura desde la web.

</domain>

<decisions>
## Implementation Decisions

### ⚠ Decisión que afecta el futuro — mecanismo del watermark (reemplaza al del research)
- **D-01:** La garantía de PULL-03 se implementa con un **advisory lock de Postgres**, NO con el margen de tiempo del research.
  - **Push** (`backend/api/sync/push.js`): la PRIMERA sentencia de la `sql.transaction([...])` es `SELECT pg_advisory_xact_lock(K)` (exclusivo). Tiene que ir antes de cualquier INSERT/UPDATE, porque `change_seq` se asigna en el trigger `BEFORE INSERT OR UPDATE` (`backend/schema.sql:129-151`).
  - **Pull**: cada página corre en su propia `sql.transaction([...])`: primero `SELECT pg_advisory_xact_lock_shared(K)` y después la query de pull. En READ COMMITTED (el default) la segunda sentencia toma un snapshot nuevo, posterior al lock, así que ve todo push que ya tenía seqs asignados. **No usar REPEATABLE READ/SERIALIZABLE**: el snapshot se tomaría en la primera sentencia y la garantía se rompe.
  - Pushes entre sí: se serializan (con un solo editor no cuesta nada). Pulls entre sí: concurrentes. Un pull espera como mucho lo que dura un push en curso.
  - **Por qué se descartó el watermark del research** (`MAX(change_seq) WHERE updated_at <= now() - 2s`, `research/SUMMARY.md:48`): `updated_at` lo pone el **cliente** en el upsert (`to_timestamp($n)` del payload, `backend/api/_lib/outbox.js:58-61`); solo el delete usa `now()` del servidor (`outbox.js:50`). Un backlog offline con `updated_at` de hace días pasa el filtro mientras su transacción sigue abierta → el cursor avanza sobre seqs no comiteados → pérdida silenciosa y permanente de esas filas en el cliente.
  - **Alternativas descartadas:** (B) columna de timestamp del servidor seteada por trigger + margen garantizado con `transaction_timeout`: exige migrar las 7 tablas en producción y agrega N segundos de retraso visible. (C) `pg_current_xact_id()` por fila + `pg_snapshot_xmin`: un push de muchas filas puede tener xid viejo con seqs nuevos, así que el cursor por seq igual saltea; habría que paginar por xid. Es lo más complejo.
  - **Techo / riesgo (ponytail):** solo protege a quien toma el lock. Hoy el único escritor es `push.js`. **Todo escritor nuevo** (escritura de la web por ADR-006, scripts de migración que escriban filas sincronizables, SQL manual en la consola de Neon) tiene que tomar `pg_advisory_xact_lock(K)` o puede generar un salto. Documentarlo en un comentario `ponytail:` junto a la constante `K`, y en el ADR (D-02).
- **D-02:** Registro de la decisión, como tarea de esta fase:
  1. **ADR nuevo en Notion** (base "Cíngula App — ADRs"): contexto (seq asignado antes del commit), decisión (advisory lock), alternativas (margen sobre `updated_at` — inválido; timestamp del servidor + margen; xid/snapshot), consecuencia/techo ("todo escritor toma el lock"), estado.
  2. **Corregir `.planning/workstreams/web/REQUIREMENTS.md:14`**: la fila "Pull con watermark (no devuelve filas más nuevas que un margen de seguridad)" y el riesgo "Margen exacto a fijar" pasan a describir el advisory lock.
  3. **Nota de "reemplazado por ADR-0xx / 10-CONTEXT D-01"** en `research/SUMMARY.md` (§5, líneas 44-48, 90, 102), `research/ARCHITECTURE.md:33` y `research/PITFALLS.md:19`, sin reescribir el research.
  - `ROADMAP.md` y PULL-03 no cambian: describen la garantía, no el mecanismo.
- **D-03:** El test de integración de PULL-03 (contra una rama Neon dev) simula un push que queda abierto con seqs asignados y un pull concurrente, y verifica que el pull no avanza el cursor sobre esas filas. Cómo mantener una transacción abierta en el test (p.ej. `Pool`/WebSocket de `@neondatabase/serverless`, ya instalado) queda a criterio del researcher/planner.

### Forma de la respuesta del pull
- **D-04:** Ruta **`GET /sync/pull`** (coincide con ERS y ROADMAP). Llega por el rewrite existente `/sync/:path*` → `/api/sync/:path*` (`backend/vercel.json`), así que el archivo es `backend/api/sync/pull.js`. El stub de la app usa `/sync/changes` (`lib/core/config/api_config.dart:36`): lo corrige `app` Fase 3, y se anota en el contrato.
- **D-05:** Query params: `cursor` (string con un entero ≥ 0; si falta = `0`) y `limit` (default **500**, máximo **1000**). Un `cursor` o `limit` inválido o fuera de rango → **400** explícito.
- **D-06:** Respuesta: **lista plana en orden global** de `change_seq`:
  `{ changes: [{ table, change_seq, payload }], nextCursor, hasMore }`
  - `table` es uno de `SYNCABLE_TABLES` (`spec.js`); `payload` trae exactamente las columnas de `TABLE_SPEC[table]`, con los timestamps en epoch segundos (simétrico con el push, PULL-02).
  - `change_seq` y `nextCursor` viajan como **string** (`::text` en SQL, mismo patrón que `state.js:5`).
  - `nextCursor` = el `change_seq` de la última fila devuelta; si no hay filas, se devuelve el `cursor` recibido.
  - El orden padres-antes-que-hijos al aplicar es responsabilidad del cliente (discreción de `app` Fase 3; `rank` de `spec.js` sirve de referencia).
- **D-07:** Filas borradas: **fila completa**, igual que cualquier otra, con `deleted_at` seteado. Sin tombstone especial. El celular aplica borrado lógico (`app` 03-CONTEXT D-05) y la web las filtra (WEB-08).
- **D-08:** `entity_prev` no se expone por el pull.

### Alcance de WEB_API_KEY
- **D-09:** `WEB_API_KEY` es de **solo lectura** en este milestone: acepta `GET /sync/pull` y `GET /sync/state`, y la rechaza `POST /sync/push`. Motivo: vive en el navegador y es una barrera débil. Si se filtra, no puede escribir ni pisar datos del celular (core value: integridad). Se amplía cuando llegue la escritura desde la web (ADR-006), con su propia decisión.
- **D-10:** Una `WEB_API_KEY` válida contra el push → **403 Forbidden** (distinto del 401 de una key inválida o ausente).
- **D-11:** Se mantiene lo ya decidido: `timingSafeEqual` por cada clave candidata; una variable ausente o vacía no da acceso por esa clave; ninguna configurada → todo rechazado (nunca abre).
- **D-12:** Actualizar ADR-007 en Notion con la restricción de solo lectura (una línea en "Consecuencias", no un ADR nuevo).

### Contrato para `app` (PULL-05)
- **D-13:** El contrato publicado en "ERS · Backend — protocolo de sync" (Notion) incluye: ruta (D-04), params y errores (D-05), forma (D-06), borradas (D-07), la garantía de no-salto (D-01, sin detalles internos del lock), alcance de keys (D-09/D-10), y **que el único cursor válido para pull es `0` o un `nextCursor` devuelto por un pull**. El `serverCursor` de `/sync/state` y del push es informativo: el `MAX(change_seq)` que devuelven no pasa por el lock y puede estar por delante de un push en vuelo.

### Claude's Discretion
- Forma exacta de la query (UNION ALL por tabla con `WHERE change_seq > $cursor ORDER BY change_seq LIMIT $n` interno + `ORDER BY/LIMIT` externo usando los `*_change_seq_idx` existentes, o equivalente). Cómo construir el payload por tabla desde `TABLE_SPEC` (p.ej. `json_build_object` con `extract(epoch …)` o serialización en JS).
- Cómo calcular `hasMore` (p.ej. pedir `limit + 1` filas).
- Forma de la API de `auth.js` para distinguir "qué key matcheó" (p.ej. `requireApiKey` devuelve la clave o un rol). Valor de la constante `K` del lock.
- Mensajes de error de los 400.
- Estructura exacta del ADR y del texto del contrato en Notion (skill `gestion-notion-rama`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap
- `.planning/workstreams/web/ROADMAP.md` §Phase 10 — goal, success criteria 1-5, ponytail audit obligatorio como último plan
- `.planning/workstreams/web/REQUIREMENTS.md` — PULL-01..05, AUTH-01; tabla de decisiones (línea 14 se corrige por D-02)
- `.planning/PROJECT.md` §ADRs y §Workstreams — ADR-004 (web = participante del sync), ADR-007 (WEB_API_KEY), contrato en "ERS · Backend — protocolo de sync"

### Research (con la corrección de D-01)
- `.planning/workstreams/web/research/SUMMARY.md` — query UNION ALL, serialización `::text`; **§5 (watermark) reemplazado por D-01**
- `.planning/workstreams/web/research/ARCHITECTURE.md` — diseño de la query de pull (línea 33 reemplazada por D-01)
- `.planning/workstreams/web/research/PITFALLS.md` — pitfalls de la query y del bigint (línea 19 reemplazada por D-01)

### Código backend existente
- `backend/api/sync/push.js` — handler de push; dónde va el `pg_advisory_xact_lock` (dentro de `sql.transaction`, línea 40) y el 403 de D-10
- `backend/api/_lib/outbox.js` — `upsertStatement`; prueba de que `updated_at` es del cliente (líneas 50, 58-61)
- `backend/api/_lib/spec.js` — `TABLE_SPEC`, `SYNCABLE_TABLES`, tipos `epoch`: fuente única para el payload del pull
- `backend/api/_lib/auth.js` — `requireApiKey`, a extender con dual-key + alcance
- `backend/api/sync/state.js` — `STATE_SQL` sin `recorridos` (PULL-04); patrón `::text`
- `backend/schema.sql` — secuencia `change_seq`, trigger `bump_change_seq` (129-151), índices `*_change_seq_idx` (118-124)
- `backend/vercel.json` — rewrite `/sync/:path*`
- `backend/api/_lib/auth.test.js`, `backend/api/sync/push.test.js` — patrón de tests (`node --test`)

### Cliente (consumidor del contrato)
- `.planning/workstreams/app/phases/03-sync-bidireccional-pull/03-CONTEXT.md` — D-03 (inserts/updates/deletes), D-05 (borrado lógico); forma del endpoint era discreción → cerrada acá
- `lib/core/config/api_config.dart:36` — stub `/sync/changes` (se corrige en `app` Fase 3)
- `lib/data/sync/sync_api.dart`, `lib/data/sync/sync_api_http.dart:70` — `pullChanges({cursor})` sin implementar

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TABLE_SPEC` / `SYNCABLE_TABLES` (`spec.js`): definen columnas y tipos por tabla → generan el SELECT del pull sin listas duplicadas; `spec.test.js` ya valida spec contra schema.
- `currentState(sql)` (`state.js`): patrón UNION ALL + `::text` para bigint; se extiende con `recorridos`.
- `getSql()` (`db.js`): driver HTTP de Neon; `sql.transaction([...])` ya se usa en push, y sirve para lock + query en el pull.
- `requireApiKey` + `timingSafeEqual` (`auth.js`): se extiende, no se reescribe.

### Established Patterns
- Identificadores SQL siempre del spec, valores siempre parametrizados (`outbox.js:38-39`).
- Comentarios `ponytail:` para simplificaciones con techo conocido (`push.js:26`, `outbox.js:48`).
- Tests con `node --test`, archivo `*.test.js` al lado del módulo.
- Config faltante = cerrado, nunca abierto (`auth.js:13`).

### Integration Points
- Nuevo `backend/api/sync/pull.js` (ruteado por `vercel.json` existente, sin cambios de ruteo — eso es Fase 11).
- `push.js`: una sentencia nueva al inicio de la transacción + el chequeo de alcance de la key.
- `state.js`: una línea de UNION ALL para `recorridos`.

</code_context>

<specifics>
## Specific Ideas

- El usuario pidió ver qué dice cada documento y pros/contras antes de decidir cómo registrar el cambio de watermark: la corrección de docs es explícita y trazable, no silenciosa (estándar de documentación de arquitectura del usuario).
- Confirmado con el usuario: el lock vive solo en el servidor; la app no cambia nada en su push.

</specifics>

<deferred>
## Deferred Ideas

- Ampliar el alcance de `WEB_API_KEY` a escritura — cuando llegue la escritura desde la web (ADR-006), con su propia decisión.
- Que la escritura futura de la web y cualquier script de datos tomen el advisory lock — requisito para esas fases, registrado en el ADR (D-02).

</deferred>

---

*Phase: 10-pull-cerrado-auth-dual-key*
*Context gathered: 2026-09-23*
