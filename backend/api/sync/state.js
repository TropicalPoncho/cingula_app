import { apiKeyRole, AUTH_ERROR } from '../_lib/auth.js';
import { getSql } from '../_lib/db.js';
import { SYNCABLE_TABLES } from '../_lib/spec.js';

// serverCursor es informativo (D-13): no pasa por el advisory lock y puede estar por delante de
// un push en vuelo. El único cursor válido para pull es 0 o un nextCursor devuelto por un pull.
export const STATE_SQL = `
  SELECT COALESCE(MAX(seq), 0)::text AS cursor, MAX(upd) AS last FROM (
    ${SYNCABLE_TABLES.map((t) => `SELECT MAX(change_seq) seq, MAX(updated_at) upd FROM "${t}"`).join('\n    UNION ALL ')}) s`;

export async function currentState(sql) {
  const rows = await sql.query(STATE_SQL);
  const { cursor, last } = rows[0];
  return { serverCursor: cursor, lastSyncAt: last ? new Date(last).toISOString() : null };
}

export async function currentCursor(sql) {
  return (await currentState(sql)).serverCursor;
}

export default async function handler(request, response) {
  // D-09: ambos roles (sync y web) leen state.
  if (!apiKeyRole(request)) {
    return response.status(401).json({ error: AUTH_ERROR });
  }
  return response.status(200).json(await currentState(getSql()));
}
