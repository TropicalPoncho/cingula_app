import { apiKeyRole, AUTH_ERROR } from '../_lib/auth.js';
import { getSql, SYNC_LOCK_KEY } from '../_lib/db.js';
import { TABLE_SPEC, SYNCABLE_TABLES } from '../_lib/spec.js';

const DEFAULT_LIMIT = 500;
const MAX_LIMIT = 1000;
const MAX_BIGINT = 9223372036854775807n;
const CURSOR_ERROR = 'cursor must be an integer >= 0';
const LIMIT_ERROR = `limit must be an integer between 1 and ${MAX_LIMIT}`;

// Payload = exactamente las columnas del spec (D-06). 'epoch' sale en segundos enteros, simétrico
// con el push (PULL-02). La versión anterior no se expone (D-08). Borradas = fila completa (D-07).
const field = (c, type) =>
  type === 'epoch' ? `'${c}', floor(extract(epoch from "${c}"))::bigint` : `'${c}', "${c}"`;
const selectTable = (t) =>
  `(SELECT '${t}' AS "table", change_seq, json_build_object(` +
  Object.entries(TABLE_SPEC[t].columns).map(([c, type]) => field(c, type)).join(', ') +
  `) AS payload FROM "${t}" WHERE change_seq > $1::bigint ORDER BY change_seq LIMIT $2)`;
// LIMIT interno por tabla (usa <tabla>_change_seq_idx) + ORDER BY/LIMIT externo = orden global.
const PULL_SQL =
  `SELECT "table", change_seq::text AS change_seq, payload FROM (` +
  SYNCABLE_TABLES.map(selectTable).join(' UNION ALL ') +
  `) u ORDER BY u.change_seq LIMIT $2`;

function parseQuery(query = {}) {
  const { cursor = '0', limit = String(DEFAULT_LIMIT) } = query;
  if (typeof cursor !== 'string' || !/^\d+$/.test(cursor) || BigInt(cursor) > MAX_BIGINT) {
    return { error: CURSOR_ERROR };
  }
  if (typeof limit !== 'string' || !/^\d+$/.test(limit) || Number(limit) < 1 || Number(limit) > MAX_LIMIT) {
    return { error: LIMIT_ERROR };
  }
  return { cursor: BigInt(cursor).toString(), limit: Number(limit) };
}

export default async function handler(request, response) {
  if (request.method !== 'GET') return response.status(405).json({ error: 'method not allowed' });
  if (!apiKeyRole(request)) return response.status(401).json({ error: AUTH_ERROR }); // D-09: ambos roles leen
  const parsed = parseQuery(request.query);
  if (parsed.error) return response.status(400).json({ error: parsed.error });
  const { cursor, limit } = parsed;

  const sql = getSql();
  // ponytail: la garantía de PULL-03 (D-01) depende de READ COMMITTED: la query toma su snapshot
  // DESPUÉS de obtener el lock compartido, o sea después del commit de cualquier push que lo tenía.
  // Con RepeatableRead/Serializable el snapshot se fijaría en la primera sentencia y se rompe.
  const [, rows] = await sql.transaction(
    [
      sql.query('SELECT pg_advisory_xact_lock_shared($1)', [SYNC_LOCK_KEY]),
      sql.query(PULL_SQL, [cursor, limit + 1]), // limit + 1 filas -> hasMore sin un COUNT aparte
    ],
    { isolationLevel: 'ReadCommitted' },
  );
  const changes = rows.slice(0, limit);
  return response.status(200).json({
    changes,
    nextCursor: changes.length > 0 ? changes.at(-1).change_seq : cursor,
    hasMore: rows.length > limit,
  });
}
