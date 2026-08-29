import { requireApiKey, AUTH_ERROR } from '../_lib/auth.js';
import { getSql } from '../_lib/db.js';

export default async function handler(request, response) {
  if (requireApiKey(request)) {
    return response.status(401).json({ error: AUTH_ERROR });
  }
  const sql = getSql();
  const rows = await sql`SELECT MAX(current_updated_at) AS last FROM synced_entities`;
  const last = rows[0]?.last ? new Date(rows[0].last).toISOString() : null;
  return response.status(200).json({ serverCursor: last, lastSyncAt: last });
}
