import { apiKeyRole, AUTH_ERROR, READ_ONLY_ERROR } from '../_lib/auth.js';
import { getSql, SYNC_LOCK_KEY } from '../_lib/db.js';
import { validateOutboxItem, upsertStatement } from '../_lib/outbox.js';
import { SCHEMA_VERSION } from '../_lib/spec.js';
import { currentCursor } from './state.js';

export default async function handler(request, response) {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'method not allowed' });
  }
  const role = apiKeyRole(request);
  if (!role) return response.status(401).json({ error: AUTH_ERROR });
  // D-10: una WEB_API_KEY válida no puede escribir (D-09: solo lectura en este milestone).
  if (role !== 'sync') return response.status(403).json({ error: READ_ONLY_ERROR });

  if (request.body?.schema_version !== SCHEMA_VERSION) {
    return response.status(400).json({ error: 'schema_version 2 required' });
  }

  const receivedAt = new Date().toISOString();
  const outbox = request.body?.outbox;

  if (!Array.isArray(outbox) || outbox.length === 0) {
    return response.status(200).json({ ackedIds: [], serverCursor: null, receivedAt });
  }

  // ponytail: validar TODO antes de tocar la DB. sql.transaction() es todo-o-nada, así que
  // una fila malformada abortaría el batch entero de forma silenciosa. Preferimos un 400
  // explícito que nombra qué ids fallaron (ver 02-RESEARCH.md > Pitfall 4).
  const invalid = outbox
    .map((item, index) => ({ item, index, error: validateOutboxItem(item) }))
    .filter((entry) => entry.error !== null);
  if (invalid.length > 0) {
    return response.status(400).json({
      error: invalid.map((e) => `item[${e.index}]: ${e.error}`).join('; '),
      invalidIds: invalid.map((e) => e.item?.id).filter(Number.isInteger),
    });
  }

  const sql = getSql();
  // ponytail: el orden ES la garantía (D-01): el lock exclusivo va antes de cualquier
  // INSERT/UPDATE porque bump_change_seq() asigna change_seq antes del commit. No meter
  // ninguna sentencia antes del lock.
  await sql.transaction([
    sql.query('SELECT pg_advisory_xact_lock($1)', [SYNC_LOCK_KEY]),
    ...outbox.map((item) => upsertStatement(sql, item)),
  ]);

  return response.status(200).json({
    ackedIds: outbox.map((item) => item.id),
    serverCursor: await currentCursor(sql),
    receivedAt,
  });
}
