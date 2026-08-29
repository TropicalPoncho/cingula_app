import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { getSql } from '../_lib/db.js';
import { upsertStatement } from '../_lib/outbox.js';

// Se saltea (no falla) sin DATABASE_URL, para que `npm test` sea verde en cualquier máquina.
// El plan 02-05 lo corre de verdad contra una branch de Neon antes de cerrar la fase.
const skip = process.env.DATABASE_URL ? false : 'requires DATABASE_URL (Neon dev branch)';

const schemaPath = fileURLToPath(new URL('../../schema.sql', import.meta.url));

function makeItem(uuid, version, overrides = {}) {
  return {
    id: 1,
    table_name: 'geo_triggers',
    record_uuid: uuid,
    op: 'update',
    payload: { uuid, logical_version: version, name: 'test' },
    ...overrides,
  };
}

async function readRow(sql, uuid) {
  const rows = await sql`
    SELECT current_version, current_payload, current_updated_at, previous_version,
           previous_payload, previous_updated_at, deleted_at, op
    FROM synced_entities WHERE record_uuid = ${uuid}
  `;
  return rows[0] ?? null;
}

test('idempotencia y versionado', { skip }, async (t) => {
  const sql = getSql();
  await sql.query(readFileSync(schemaPath, 'utf8'));

  t.after(async () => {
    await sql`DELETE FROM synced_entities WHERE record_uuid = ${uuid}`;
  });

  const uuid = randomUUID();

  await t.test('SYNC-02: reenviar el mismo item dos veces es un no-op', async () => {
    await sql.transaction([upsertStatement(sql, makeItem(uuid, 1))]);
    const first = await readRow(sql, uuid);
    assert.equal(first.current_version, 1);
    assert.equal(first.previous_version, null);

    await sql.transaction([upsertStatement(sql, makeItem(uuid, 1))]);
    const second = await readRow(sql, uuid);
    assert.equal(second.current_version, 1);
    assert.equal(
      new Date(second.current_updated_at).getTime(),
      new Date(first.current_updated_at).getTime(),
    );
  });

  await t.test('SYNC-06: ventana de 2 versiones (current + 1 previous)', async () => {
    await sql.transaction([upsertStatement(sql, makeItem(uuid, 2))]);
    await sql.transaction([upsertStatement(sql, makeItem(uuid, 3))]);
    const row = await readRow(sql, uuid);
    assert.equal(row.current_version, 3);
    assert.equal(row.previous_version, 2);
    assert.equal(row.previous_payload.logical_version, 2);
  });

  await t.test('out-of-order: una version vieja llegando tarde no retrocede el estado', async () => {
    await sql.transaction([upsertStatement(sql, makeItem(uuid, 2))]);
    const row = await readRow(sql, uuid);
    assert.equal(row.current_version, 3);
    assert.equal(row.previous_version, 2);
  });

  await t.test('delete: marca deleted_at y op=delete cuando la version avanza', async () => {
    await sql.transaction([upsertStatement(sql, makeItem(uuid, 4, { op: 'delete' }))]);
    const row = await readRow(sql, uuid);
    assert.equal(row.current_version, 4);
    assert.equal(row.op, 'delete');
    assert.notEqual(row.deleted_at, null);
  });
});
