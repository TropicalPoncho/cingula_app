import { requireApiKey, AUTH_ERROR } from '../_lib/auth.js';
import { getSql } from '../_lib/db.js';

const STATE_SQL = `
  SELECT COALESCE(MAX(seq), 0)::text AS cursor, MAX(upd) AS last FROM (
    SELECT MAX(change_seq) seq, MAX(updated_at) upd FROM audios
    UNION ALL SELECT MAX(change_seq), MAX(updated_at) FROM artistas
    UNION ALL SELECT MAX(change_seq), MAX(updated_at) FROM obras
    UNION ALL SELECT MAX(change_seq), MAX(updated_at) FROM obra_artistas
    UNION ALL SELECT MAX(change_seq), MAX(updated_at) FROM paths
    UNION ALL SELECT MAX(change_seq), MAX(updated_at) FROM triggers) s`;

export async function currentState(sql) {
  const rows = await sql.query(STATE_SQL);
  const { cursor, last } = rows[0];
  return { serverCursor: cursor, lastSyncAt: last ? new Date(last).toISOString() : null };
}

export async function currentCursor(sql) {
  return (await currentState(sql)).serverCursor;
}

export default async function handler(request, response) {
  if (requireApiKey(request)) {
    return response.status(401).json({ error: AUTH_ERROR });
  }
  return response.status(200).json(await currentState(getSql()));
}
