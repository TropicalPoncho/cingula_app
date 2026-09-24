# Phase 10: Pull cerrado + Auth dual-key - Research

**Researched:** 2026-09-24
**Domain:** Backend Vercel Functions + Neon Postgres — endpoint de lectura paginada (`GET /sync/pull`), garantía de no-salto bajo concurrencia (advisory lock), auth dual-key
**Confidence:** ALTA — casi todas las decisiones de diseño ya están cerradas en 10-CONTEXT.md (D-01 a D-13); este research verifica que son ejecutables contra el código y el driver reales, y resuelve el único hueco técnico que quedaba abierto (cómo mantener una transacción "en vuelo" en el test de PULL-03).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Mecanismo del watermark (D-01, D-02, D-03) — reemplaza el margen de tiempo del research previo:**
- La garantía de PULL-03 se implementa con un **advisory lock de Postgres**, no con margen de tiempo.
- **Push** (`backend/api/sync/push.js`): la PRIMERA sentencia de `sql.transaction([...])` es `SELECT pg_advisory_xact_lock(K)` (exclusivo), antes de cualquier INSERT/UPDATE, porque `change_seq` se asigna en el trigger `BEFORE INSERT OR UPDATE` (`backend/schema.sql:129-151`).
- **Pull**: cada página corre en su propia `sql.transaction([...])`: primero `SELECT pg_advisory_xact_lock_shared(K)`, después la query de pull. En READ COMMITTED (default) la segunda sentencia toma un snapshot nuevo, posterior al lock, así que ve todo push que ya tenía seqs asignados. **No usar REPEATABLE READ/SERIALIZABLE**: el snapshot se tomaría en la primera sentencia y la garantía se rompe.
- Pushes entre sí: se serializan (un solo editor, no cuesta nada). Pulls entre sí: concurrentes. Un pull espera como mucho lo que dura un push en curso.
- **Por qué se descartó el watermark del research** (`MAX(change_seq) WHERE updated_at <= now() - 2s`): `updated_at` lo pone el **cliente** en el upsert (`to_timestamp($n)` del payload, `outbox.js:58-61`); solo el delete usa `now()` del servidor (`outbox.js:50`). Un backlog offline con `updated_at` de hace días pasa el filtro mientras su transacción sigue abierta → cursor avanza sobre seqs no comiteados → pérdida silenciosa y permanente.
- Alternativas descartadas: (B) columna de timestamp del servidor por trigger + margen garantizado — exige migrar las 7 tablas y agrega retraso visible. (C) `pg_current_xact_id()` por fila + `pg_snapshot_xmin` — un push de muchas filas puede tener xid viejo con seqs nuevos, el cursor por seq igual saltea; habría que paginar por xid. Más complejo.
- **Techo/riesgo (ponytail):** solo protege a quien toma el lock. Hoy el único escritor es `push.js`. Todo escritor nuevo (escritura web ADR-006, scripts de migración, SQL manual en consola Neon) tiene que tomar `pg_advisory_xact_lock(K)` o puede generar un salto. Documentar con comentario `ponytail:` junto a la constante `K`, y en el ADR.
- Registro: ADR-012 ya creado en Notion (base "Cíngula App — ADRs"). Corregir `REQUIREMENTS.md:14` (ya corregido — ver tabla de decisiones). Nota de "reemplazado" en `research/SUMMARY.md` §5, `research/ARCHITECTURE.md:33`, `research/PITFALLS.md:19` (SUMMARY.md ya tiene la nota al pie; verificar ARCHITECTURE.md y PITFALLS.md al ejecutar).
- El test de integración de PULL-03 (rama Neon dev) simula un push que queda abierto con seqs asignados y un pull concurrente, y verifica que el pull no avanza el cursor sobre esas filas. Cómo mantener la transacción abierta queda a criterio del researcher/planner — **resuelto en este research, ver "Código de referencia: test PULL-03" más abajo**.

**Forma de la respuesta del pull:**
- Ruta: **`GET /sync/pull`** (coincide con ERS y ROADMAP), archivo `backend/api/sync/pull.js`, llega por el rewrite existente `/sync/:path*` → `/api/sync/:path*`. El stub de la app usa `/sync/changes` (`lib/core/config/api_config.dart:36`): lo corrige `app` Fase 3.
- Query params: `cursor` (string, entero ≥ 0; default `0` si falta) y `limit` (default 500, máximo 1000). Inválido o fuera de rango → 400 explícito.
- Respuesta: lista plana en orden global de `change_seq`: `{ changes: [{ table, change_seq, payload }], nextCursor, hasMore }`.
  - `table` ∈ `SYNCABLE_TABLES`; `payload` trae exactamente las columnas de `TABLE_SPEC[table]`, timestamps en epoch segundos (simétrico con push).
  - `change_seq` y `nextCursor` viajan como **string** (`::text`, mismo patrón que `state.js:5`).
  - `nextCursor` = `change_seq` de la última fila devuelta; sin filas, se devuelve el `cursor` recibido.
  - Orden padres-antes-que-hijos al aplicar es responsabilidad del cliente (`rank` de `spec.js` como referencia).
- Filas borradas: fila completa con `deleted_at` seteado, sin tombstone especial.
- `entity_prev` no se expone por el pull.

**Alcance de WEB_API_KEY:**
- `WEB_API_KEY` es de **solo lectura** en este milestone: acepta `GET /sync/pull` y `GET /sync/state`, rechaza `POST /sync/push`. Vive en el navegador, barrera débil; si se filtra no puede escribir ni pisar datos del celular.
- Una `WEB_API_KEY` válida contra el push → **403 Forbidden** (distinto del 401 de key inválida/ausente).
- `timingSafeEqual` por cada clave candidata; variable ausente o vacía no da acceso por esa clave; ninguna configurada → todo rechazado (nunca abre).
- Actualizar ADR-007 en Notion con la restricción de solo lectura (una línea en "Consecuencias").

**Contrato para `app` (PULL-05):**
- Publicado en "ERS · Backend — protocolo de sync" (Notion): ruta, params y errores, forma, borradas, garantía de no-salto (sin detalles internos del lock), alcance de keys, y que el único cursor válido para pull es `0` o un `nextCursor` devuelto por un pull previo. `serverCursor` de `/sync/state` y del push es informativo: no pasa por el lock y puede estar adelante de un push en vuelo.

### Claude's Discretion
- Forma exacta de la query (UNION ALL por tabla con `WHERE change_seq > $cursor ORDER BY change_seq LIMIT $n` interno + `ORDER BY/LIMIT` externo usando los `*_change_seq_idx` existentes, o equivalente).
- Cómo construir el payload por tabla desde `TABLE_SPEC` (`json_build_object` con `extract(epoch …)`, o serialización en JS).
- Cómo calcular `hasMore` (p.ej. pedir `limit + 1` filas).
- Forma de la API de `auth.js` para distinguir "qué key matcheó" (p.ej. `requireApiKey` devuelve la clave o un rol). Valor de la constante `K` del lock.
- Mensajes de error de los 400.
- Estructura exacta del ADR y del texto del contrato en Notion.

### Deferred Ideas (OUT OF SCOPE)
- Ampliar el alcance de `WEB_API_KEY` a escritura — cuando llegue ADR-006, con su propia decisión.
- Que la escritura futura de la web y cualquier script de datos tomen el advisory lock — requisito para esas fases, registrado en el ADR (D-02).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PULL-01 | `GET /sync/pull?cursor=&limit=` devuelve todas las filas con `change_seq > cursor`, ordenadas, incluidas borradas, paginado con `hasMore` | Ver "Query de pull" y "Código de referencia" — UNION ALL sobre `TABLE_SPEC`, reutiliza índices `*_change_seq_idx` ya existentes, sin cambios de schema |
| PULL-02 | `payload` con mismo formato que push (columnas de `spec.js`, epoch); `change_seq`/`serverCursor` como string | Verificado: `TABLE_SPEC`/`upsertStatement` (`spec.js`, `outbox.js`) y patrón `::text` de `state.js:5` son directamente reutilizables |
| PULL-03 | Pull paginado nunca saltea fila por commit concurrente, con test de integración contra Neon dev | Ver "Advisory lock — verificación de correctness" y "Código de referencia: test PULL-03" (resuelve cómo mantener la transacción de push abierta durante el test, usando `Pool`/WebSocket nativo de Node 22, sin dependencia nueva) |
| PULL-04 | `state.js` incluye `recorridos` en `serverCursor`/`lastSyncAt` | Verificado: bug real, `STATE_SQL` (`state.js:4-11`) no tiene la línea `UNION ALL SELECT ... FROM recorridos`; fix de una línea |
| PULL-05 | Contrato publicado en Notion antes de cerrar la fase | Contenido exacto ya cerrado en CONTEXT D-13; ver "Contenido del contrato para Notion" |
| AUTH-01 | Backend acepta `WEB_API_KEY` además de `SYNC_API_KEY`, revocables por separado, config faltante = cerrado | Ver "Auth dual-key" — extiende `auth.js` existente sin reescribir, patrón ya probado en `auth.test.js` |
</phase_requirements>

## Summary

Esta fase tiene casi todo el diseño ya cerrado por el usuario en `10-CONTEXT.md` (D-01 a D-13): el mecanismo de la garantía anti-salto (advisory lock, no margen de tiempo), la forma exacta de la respuesta del pull, y el alcance de solo-lectura de `WEB_API_KEY`. El trabajo de este research fue verificar que esas decisiones son ejecutables contra el código real (`push.js`, `state.js`, `spec.js`, `outbox.js`, `auth.js`, `schema.sql`) y contra el driver real (`@neondatabase/serverless` ^1.1.0), y cerrar el único hueco técnico que el CONTEXT dejaba a criterio del researcher: cómo mantener una transacción de push "en vuelo" durante el test de integración de PULL-03.

Verificación clave: el driver HTTP (`neon()`, usado por `sql.transaction()` en push/state hoy) envía todas las queries de una transacción en un solo request HTTP — sirve perfecto para poner `pg_advisory_xact_lock`/`_shared` como primera sentencia de push y pull, sin cambiar el patrón ya usado. Pero para el test de PULL-03 hace falta una transacción que quede *genuinamente abierta* mientras el test dispara un pull concurrente desde otra conexión — eso el driver HTTP no lo permite (una sola request, atómica). La solución es el `Pool`/`Client` (WebSocket) del mismo paquete, con `BEGIN`/`await sleep`/`COMMIT` explícitos. Como `package.json` ya fija `engines.node >= 22`, y Node 22 trae `WebSocket` global nativo, **no hace falta instalar `ws` como dependencia nueva** — un descubrimiento importante porque evita agregar una dependencia solo para un test.

**Primary recommendation:** implementar `pull.js` reusando `TABLE_SPEC`/`upsertStatement`/patrón `::text` de `state.js` tal cual estabann, agregar el advisory lock como primera sentencia en las transacciones de push y pull existentes, y escribir el test de PULL-03 con `Pool` (WebSocket nativo Node 22, sin `ws`) para mantener el push "colgado" mientras el pull concurrente corre.

## Verificación contra código existente (no exploratorio — todo ya decidido)

### Reutilizable sin cambios
- `TABLE_SPEC` / `SYNCABLE_TABLES` / `REQUIRED` (`backend/api/_lib/spec.js`): única fuente de columnas y tipos por tabla (7 tablas, `META = { logical_version, updated_at: 'epoch', deleted_at: 'epoch' }`). El pull arma su `SELECT`/payload a partir de esto — cero listas duplicadas.
- Patrón `::text` para bigint (`state.js:5`, `COALESCE(MAX(seq), 0)::text AS cursor`): mismo patrón para `change_seq` y `nextCursor` del pull (JS `number` pierde precisión en bigint de 64 bits más allá de 2^53).
- `getSql()` (`db.js`): `neon(url)` HTTP driver; `sql.transaction([...])` ya usado en `push.js:40` con un array de `sql.query(text, params)` — el mismo patrón sirve para `[lockStatement, pullQueryStatement]` en pull.js.
- `requireApiKey`/`timingSafeEqual` (`auth.js`): base sólida a extender (no reescribir) — ya usa `timingSafeEqual` con chequeo de largo antes de comparar (auth.js:19-20), patrón correcto que hay que repetir por cada key candidata.

### Bug confirmado en `state.js`
`STATE_SQL` (`state.js:4-11`) tiene `UNION ALL` para `audios, artistas, obras, obra_artistas, paths, triggers` — **falta `recorridos`** (PULL-04 real, no hipotético). Fix: una línea `UNION ALL SELECT MAX(change_seq), MAX(updated_at) FROM recorridos`.

### Confirmación del trigger que obliga el orden del lock
`schema.sql:129-134,146-156`: `bump_change_seq()` es `BEFORE INSERT OR UPDATE` — el `change_seq` se asigna **antes del commit**, dentro de la misma transacción del push. Esto es justo lo que D-01 dice que hace necesario el lock: si el pull pudiera leer entre la asignación del seq y el commit del push, vería un hueco que después se llena con un seq menor a uno ya entregado.

## Advisory lock — verificación de correctness (Postgres, oficial)

Confirmación de por qué D-01 funciona, con la semántica real de Postgres (HIGH confidence, comportamiento documentado y estable desde hace años, no específico de una versión):

1. `pg_advisory_xact_lock(key)` toma un lock exclusivo a nivel de transacción; se libera automáticamente al COMMIT o ROLLBACK — nunca hace falta un unlock explícito, y no puede quedar "pegado" si el proceso muere (a diferencia de los locks de sesión `pg_advisory_lock`, que si se recomienda evitar acá).
2. `pg_advisory_xact_lock_shared(key)` es compatible con otros locks compartidos, pero bloquea contra el exclusivo — es la primitiva correcta para "muchos pulls concurrentes, pero ninguno mientras un push está en curso".
3. Bajo **READ COMMITTED** (nivel por defecto de Postgres, y el que usa este proyecto por no especificar otro), **cada sentencia dentro de una transacción toma su propio snapshot** en el momento en que empieza a ejecutarse — no al BEGIN de la transacción. Esto es lo que hace que D-01 funcione: la sentencia de lock y la sentencia de `SELECT` del pull son dos sentencias separadas dentro de la misma `sql.transaction([...])`; cuando el lock se obtiene (porque el push exclusivo ya liberó al comitear), la sentencia SELECT que sigue toma un snapshot *posterior* a ese commit, y por lo tanto ve todas las filas con seqs ya asignados por ese push.
4. **Confirma la advertencia explícita de D-01**: bajo REPEATABLE READ o SERIALIZABLE, el snapshot se fija en la *primera* sentencia de la transacción (el propio `BEGIN` implícito en `sql.transaction`), no en cada sentencia — así que si se usara alguno de esos niveles, el SELECT vería el mismo snapshot que existía al pedir el lock, potencialmente *antes* del commit del push que se estaba esperando, rompiendo la garantía. Confirma que la fase debe verificar (o dejar explícito en un comentario) que la conexión no cambia el nivel de aislamiento por defecto en ningún punto.

No hay caveat documentado sobre advisory locks siendo distintos entre el driver HTTP y el WebSocket de Neon — el lock es una feature de sesión/transacción de Postgres en sí, no del transporte; lo único que importa es que ambas sentencias (lock + query) viajen en la misma transacción de Postgres, lo cual `sql.transaction([...])` garantiza por diseño (una única transacción por array).

## Código de referencia: test PULL-03

**El hueco que CONTEXT dejaba abierto:** "Cómo mantener una transacción abierta en el test... queda a criterio del researcher/planner." Resuelto acá.

El driver HTTP (`neon()`) usado hoy en `push.js`/`state.js` envía **todas** las queries de `sql.transaction([...])` en un único request HTTP, atómico — no hay forma de "pausar" entre sentencias desde el lado del test. Para simular un push que "queda abierto con seqs asignados" (D-03) mientras un pull concurrente corre, hace falta una conexión de sesión real con `BEGIN`/`COMMIT` explícitos y un `await` (delay) en el medio.

`@neondatabase/serverless` expone `Pool`/`Client` (WebSocket) para exactamente este caso — "sessions / interactive transactions with multiple queries per connection" (docs oficiales, fetched 2026-09-24). En Node.js sin WebSocket nativo hace falta `neonConfig.webSocketConstructor = ws` (paquete `ws`, no instalado hoy). **Pero `backend/package.json:5` ya fija `"engines": { "node": ">=22" }`, y Node 22 trae la clase `WebSocket` global nativa** (estable desde Node 22, experimental desde 21) — confirmado por búsqueda cruzada (docs Neon + PRs de terceros que documentan el fallback). Esto significa que el test puede usar `Pool` sin agregar `ws` como dependencia nueva, simplemente no seteando `neonConfig.webSocketConstructor` (el driver usa el `WebSocket` global si existe).

Patrón para el test (`backend/api/sync/pull.test.js`, mismo `node --test` + skip-sin-`DATABASE_URL` que `push.test.js:10-11`):

```javascript
// Source: https://neon.com/docs/serverless/serverless-driver (Pool/Client, fetched 2026-09-24)
// + backend/package.json:5 (engines.node >= 22 → WebSocket global nativo, sin dependencia `ws`)
import { Pool } from '@neondatabase/serverless';

test('push abierto no es salteado por un pull concurrente', { skip }, async () => {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [LOCK_KEY]);
    // INSERT/UPDATE real que dispara bump_change_seq() y asigna change_seq,
    // pero SIN commitear todavía (transacción sigue abierta = "commit tardío" simulado).
    await client.query(/* upsertStatement equivalente, vía client.query en vez de sql.query */);

    // Pull concurrente en OTRA conexión (getSql() normal, driver HTTP), mientras el push
    // de arriba sigue sin comitear. Con pg_advisory_xact_lock_shared esperando al exclusivo,
    // esta llamada debe BLOQUEAR hasta el COMMIT de abajo, no devolver un cursor que salte la fila.
    const pullPromise = callPull({ cursor: '0', limit: 10 }); // resuelve al toolear del handler pull.js

    // Verificar (con un timeout corto) que pullPromise NO resolvió todavía —
    // si resolviera antes del COMMIT, el lock no está funcionando.

    await client.query('COMMIT');
    const result = await pullPromise;
    // Assert: la fila del push recién comiteado SÍ aparece en `result.changes`.
  } finally {
    client.release();
    await pool.end();
  }
});
```

**Notas de implementación para el planner:**
- `client.query(...)` del `Pool` no es la misma API que `sql.query(...)` del driver HTTP — los parámetros `$1, $2...` sí son compatibles (node-postgres estándar), pero conviene extraer `upsertStatement` de forma que devuelva `{text, params}` reusable por ambos drivers (hoy `upsertStatement(sql, item)` en `outbox.js:42-67` recibe `sql` solo para invocar `sql.query(...)` inline — revisar si conviene separar la construcción del SQL de la ejecución, o simplemente reconstruir el `INSERT`/`UPDATE` a mano en el test, dado que es un solo caso).
- El test necesita verificar el bloqueo real (que el pull no resuelve antes del COMMIT), no solo el resultado final — de lo contrario un bug donde el lock no se toma en abslate pasaría el test igual si el timing coincide por casualidad. Usar `Promise.race` con un timeout corto, o un flag que se marca justo antes del `COMMIT` y se assertea que `pullPromise` seguía pendiente en ese punto.
- No agregar `ws` a `package.json` a menos que se confirme en la práctica que el `WebSocket` global de Node 22 no alcanza (p.ej. si el runner de test corre en un Node <22 pese al `engines` declarado) — verificar con `node --version` en el entorno de test antes de asumir.

## Query de pull (discreción de Claude, con verificación de índices)

`schema.sql:118-124` ya tiene `CREATE INDEX ... ON <tabla> (change_seq)` para las 7 tablas — no hace falta ningún índice nuevo. Patrón UNION ALL sugerido (equivalente al que ya usa `state.js`, extendido con filtro y límite):

```sql
-- Source: patrón propio, derivado de state.js:4-11 (UNION ALL ya validado en producción)
-- por-tabla: WHERE change_seq > $cursor ORDER BY change_seq LIMIT $limit
-- luego UNION ALL de las 7 y un ORDER BY/LIMIT externo para el orden global correcto
-- (evita traer más de $limit filas por tabla incluso si una tabla concentra todos los cambios)
```
El armado exacto (json_build_object en SQL vs. serialización en JS a partir de `TABLE_SPEC`) queda a discreción del planner — ambos caminos son válidos; JS es más fácil de mantener en sync con `spec.js` sin duplicar los `epoch`/`extract` en SQL.

## Auth dual-key

Extensión directa de `auth.js` (no reescritura): hoy `requireApiKey` sólo conoce `SYNC_API_KEY` (auth.js:11). Para AUTH-01 + D-09/D-10/D-11:
- Cada request de pull/state debe poder matchear contra `SYNC_API_KEY` **o** `WEB_API_KEY`, con `timingSafeEqual` independiente por candidata (nunca comparar contra un valor concatenado o un "OR" de comparaciones no-constant-time).
- El caller necesita saber **cuál** matcheó, para el 403 de D-10 en push (`WEB_API_KEY` válida pero usada contra push → 403, no 401). Opción de discreción: que `requireApiKey` devuelva `null | { role: 'sync' | 'web' } | ERROR_STRING`, o separar en `matchApiKey(request)` que devuelve el rol y una función `requireRole(role, allowed)` fina encima. Mantener el patrón de "config faltante = cerrado" (`auth.js:12`) para cada variable independientemente — si `WEB_API_KEY` no está seteada, ninguna request con esa key pasa, incluso si por accidente coincidiera con un string vacío enviado.
- Test pattern ya establecido (`auth.test.js`): `withApiKey` helper que setea/restaura `process.env.*` — replicar para `WEB_API_KEY` sin tocar la estructura del archivo de test existente.

## Contenido del contrato para Notion (PULL-05)

Ya cerrado en CONTEXT D-13 — no es investigación, es una lista de qué debe quedar escrito en "ERS · Backend — protocolo de sync": ruta, params/errores, forma de la respuesta, tratamiento de borradas, la garantía de no-salto (sin exponer el mecanismo interno del lock), el alcance de las dos keys, y la regla de que el único cursor válido es `0` o un `nextCursor` devuelto por un pull anterior (nunca construir un cursor a mano, y `serverCursor` de `/sync/state`/push es solo informativo).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `@neondatabase/serverless` | push/pull/state (driver HTTP + Pool) | ✓ (en `package.json`) | ^1.1.0 | — |
| Node.js ≥ 22 (WebSocket global) | Test de PULL-03 (`Pool`) | Declarado en `engines`, no verificado en el entorno de ejecución real | — | Instalar `ws` + `neonConfig.webSocketConstructor` si el runner corre Node <22 pese al `engines` |
| Rama Neon dev con `DATABASE_URL` | Todo test de integración (push, pull, PULL-03) | Depende del entorno donde corra CI/dev — patrón ya usado (`skip` si falta `DATABASE_URL`, `push.test.js:10-11`) | — | El test se saltea (no falla) sin `DATABASE_URL`, patrón ya establecido — mantenerlo para `pull.test.js` |

**Missing dependencies with no fallback:** ninguno bloqueante — todo lo que hace falta ya está instalado o es nativo de la versión de Node ya requerida.

**Missing dependencies with fallback:** `ws` (solo si el runner real no tiene Node 22+; fallback ya documentado arriba).

## Common Pitfalls

### Pitfall 1: usar el nivel de aislamiento equivocado en la transacción de pull
**Qué sale mal:** si en algún punto se configura `sql.transaction([...], { isolationLevel: 'RepeatableRead' })` o similar (Neon HTTP driver lo permite como segundo argumento), el snapshot se fija en la primera sentencia (el lock), no en la del SELECT — el pull podría no ver filas recién comiteadas por el push que esperó, rompiendo PULL-03 en producción de forma silenciosa (nunca falla un test que no simule el timing exacto).
**Cómo evitarlo:** dejar explícito (código + comentario) que la transacción de pull usa READ COMMITTED (default, no tocar), y que el test PULL-03 es la única red de seguridad real contra una regresión de este tipo.

### Pitfall 2: lock exclusivo tomado después de alguna escritura en push.js
**Qué sale mal:** D-01 exige que `pg_advisory_xact_lock` sea la PRIMERA sentencia del array de `sql.transaction([...])` en push. Si un refactor futuro reordena el array (p.ej. agregando una validación con `sql.query` antes por comodidad), el lock deja de proteger la asignación de `change_seq` que ya pudo haber ocurrido en un INSERT/UPDATE anterior dentro del mismo array.
**Cómo evitarlo:** comentario `ponytail:` justo en la construcción del array de statements marcando que el orden es parte de la garantía, no un detalle estético.

### Pitfall 3: constante `K` del lock compartida sin coordinación entre push y pull
**Qué sale mal:** `pg_advisory_xact_lock`/`_shared` toman un `bigint` (o dos `int`) como key — si push y pull usan constantes distintas, no hay contención real entre ellos y la garantía no existe aunque el código "parezca" usar el patrón correcto.
**Cómo evitarlo:** exportar la constante desde un único módulo (p.ej. `_lib/lock.js` o agregarla a `spec.js`) e importarla en ambos handlers — nunca un literal numérico repetido en dos archivos.

### Pitfall 4: test de PULL-03 que no prueba el bloqueo, solo el resultado final
Ver nota en "Código de referencia: test PULL-03" — un test que solo verifica que la fila aparece al final, sin verificar que el pull esperó, puede pasar por casualidad de timing incluso si el lock nunca se toma (p.ej. si la query del pull tarda naturalmente más que el push).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `node --test` (nativo Node.js, sin librería externa) |
| Config file | ninguno — `backend/package.json` script `"test": "node --test"` |
| Quick run command | `node --test backend/api/sync/pull.test.js` (sin `DATABASE_URL`: valida solo casos 400/auth, sin DB) |
| Full suite command | `DATABASE_URL=<neon-dev-branch> node --test backend/api/**/*.test.js` (o `npm test` con `DATABASE_URL` seteada) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PULL-01 | Pull devuelve todas las filas paginadas, orden por `change_seq`, incluidas borradas | integration | `DATABASE_URL=... node --test backend/api/sync/pull.test.js` | ❌ Wave 0 |
| PULL-02 | Payload/timestamps/cursor con mismo formato que push | integration (mismo archivo) | ídem | ❌ Wave 0 |
| PULL-03 | Push abierto no es salteado por pull concurrente (advisory lock) | integration (Pool + concurrencia) | ídem, test específico dentro de `pull.test.js` | ❌ Wave 0 |
| PULL-04 | `state.js` incluye `recorridos` | integration | `DATABASE_URL=... node --test backend/api/sync/state.test.js` (o agregar caso a `push.test.js`, que ya testea `currentState`) | ❌ Wave 0 (no existe `state.test.js` separado hoy — `push.test.js:102-106` ya cubre `currentState` parcialmente) |
| PULL-05 | Contrato publicado en Notion | manual-only | — (no es código; verificación humana/skill `gestion-notion-rama`) | N/A |
| AUTH-01 | Dual-key, config faltante = cerrado, 403 en push con `WEB_API_KEY` | unit + integration | `node --test backend/api/_lib/auth.test.js` (extender) + caso 403 en `push.test.js` | Parcial — `auth.test.js` existe y cubre `SYNC_API_KEY`; extender para `WEB_API_KEY` y el rol |

### Sampling Rate
- **Per task commit:** `node --test backend/api/_lib/auth.test.js` y los casos sin DB de `pull.test.js`/`push.test.js` (rápidos, sin red)
- **Per wave merge:** suite completa contra la rama Neon dev (`DATABASE_URL` seteada), incluido el test de concurrencia de PULL-03
- **Phase gate:** full suite verde antes de `/gsd:verify-work`, más verificación manual de PULL-05 (contrato en Notion)

### Wave 0 Gaps
- [ ] `backend/api/sync/pull.test.js` — cubre PULL-01, PULL-02, PULL-03 (nuevo, sigue el patrón `push.test.js`: casos sin DB primero con `skip` condicional, luego bloque `{ skip }` contra Neon dev)
- [ ] Caso nuevo en `backend/api/_lib/auth.test.js` — cubre AUTH-01 (dual-key, config faltante = cerrado, distinguir rol)
- [ ] Caso nuevo en `backend/api/sync/push.test.js` — cubre D-10 (403 con `WEB_API_KEY` válida)
- [ ] Caso nuevo en `backend/api/sync/state.js`/test — cubre PULL-04 (agregar `recorridos` al `UNION ALL` y a la aserción existente en `push.test.js:102-106`)
- [ ] Ninguna infraestructura de test nueva hace falta (framework, fixtures) — todo el patrón (`skip` sin `DATABASE_URL`, `t.after` para limpieza, `applySchema`) ya existe y se reutiliza tal cual

## Sources

### Primary (HIGH confidence)
- Código del repo leído directamente: `backend/api/sync/push.js`, `backend/api/sync/state.js`, `backend/api/_lib/spec.js`, `backend/api/_lib/auth.js`, `backend/api/_lib/outbox.js`, `backend/api/_lib/db.js`, `backend/api/_lib/schema_loader.js`, `backend/schema.sql`, `backend/vercel.json`, `backend/package.json`, `backend/api/sync/push.test.js`, `backend/api/_lib/auth.test.js`
- `.planning/workstreams/web/phases/10-pull-cerrado-auth-dual-key/10-CONTEXT.md` — decisiones D-01 a D-13, ya cerradas por el usuario
- `.planning/workstreams/web/REQUIREMENTS.md`, `.planning/PROJECT.md` (ADR-004, ADR-007, ADR-012), `.planning/workstreams/web/ROADMAP.md` §Phase 10
- https://neon.com/docs/serverless/serverless-driver — confirmado: `sql.transaction()` HTTP = una sola request atómica; `Pool`/`Client` (WebSocket) para sesiones interactivas; en Node necesita `neonConfig.webSocketConstructor` salvo que exista `WebSocket` global (Node ≥22) — fetched 2026-09-24
- Comportamiento de `pg_advisory_xact_lock`/`_shared` y snapshots por-sentencia en READ COMMITTED vs. por-transacción en REPEATABLE READ/SERIALIZABLE — semántica estable y documentada de Postgres, conocimiento verificado (no específico de versión, no cambia entre releases recientes)

### Secondary (MEDIUM confidence)
- WebSearch "@neondatabase/serverless Pool Node.js native WebSocket global without ws package 2026" — confirma que Node ≥22 trae `WebSocket` global nativo y que el driver lo usa automáticamente si no se setea `neonConfig.webSocketConstructor`; cruzado con la doc oficial de Neon (arriba) y con `backend/package.json:5` (`engines.node >= 22`)

### Tertiary (LOW confidence)
- Ninguno usado sin verificación en este research — todo lo crítico (mecanismo de lock, driver, versión de Node) fue verificado contra código real o docs oficiales fetched directamente.

## Metadata

**Confidence breakdown:**
- Standard stack: ALTA — ningún paquete nuevo, todo ya instalado (`@neondatabase/serverless`) o nativo de Node (`WebSocket` en ≥22)
- Architecture: ALTA — diseño de query, lock y respuesta ya decididos por el usuario y verificados contra schema/código real
- Pitfalls: ALTA — derivados de la semántica documentada de Postgres (aislamiento, orden de sentencias) y de patrones de test ya existentes en el repo (no especulativos)

**Research date:** 2026-09-24
**Valid until:** 30 días (dominio estable: Postgres/advisory locks no cambia, `@neondatabase/serverless` en major 1.x; revalidar si se actualiza a un major nuevo del driver o si Vercel cambia el runtime de Node)
