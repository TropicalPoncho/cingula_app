import { requireApiKey, AUTH_ERROR } from '../_lib/auth.js';
import { getSql } from '../_lib/db.js';
import { validateOutboxItem, upsertStatement } from '../_lib/outbox.js';

export default async function handler(request, response) {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'method not allowed' });
  }
  if (requireApiKey(request)) {
    return response.status(401).json({ error: AUTH_ERROR });
  }

  const receivedAt = new Date().toISOString();
  const outbox = request.body?.outbox;

  if (!Array.isArray(outbox) || outbox.length === 0) {
    return response.status(200).json({ ackedIds: [], serverCursor: null, receivedAt });
  }

  // Validar TODO antes de tocar la DB: sql.transaction() es todo-o-nada, así que una fila
  // malformada abortaría el batch entero de forma silenciosa. Preferimos un 400 explícito
  // que nombra qué ids fallaron (ver 02-RESEARCH.md > Pitfall 4).
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
  await sql.transaction(outbox.map((item) => upsertStatement(sql, item)));

  return response.status(200).json({
    ackedIds: outbox.map((item) => item.id),
    serverCursor: receivedAt,
    receivedAt,
  });
}
