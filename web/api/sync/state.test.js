import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { getSql } from '../_lib/db.js';
import { upsertStatement } from '../_lib/outbox.js';
import { applySchema } from '../_lib/schema_loader.js';
import { SYNCABLE_TABLES } from '../_lib/spec.js';
import { STATE_SQL, currentState } from './state.js';

const skip = process.env.DATABASE_URL ? false : 'requires DATABASE_URL (Neon dev branch)';

test('STATE_SQL cuenta cada tabla del spec (PULL-04)', () => {
  for (const t of SYNCABLE_TABLES) assert.ok(STATE_SQL.includes(`"${t}"`), t);
});

test('lastSyncAt viene de recorridos, la tabla que faltaba', { skip }, async (t) => {
  const sql = getSql();
  await applySchema(sql);
  const u = randomUUID();
  t.after(async () => {
    await sql.query('DELETE FROM recorridos WHERE uuid = $1', [u]);
    await sql.query('DELETE FROM entity_prev WHERE record_uuid = $1', [u]);
  });

  await sql.transaction([
    upsertStatement(sql, {
      id: 1,
      table_name: 'recorridos',
      record_uuid: u,
      op: 'insert',
      payload: { uuid: u, name: 'state-test', logical_version: 1, updated_at: 4102444800 },
    }),
  ]);
  const seq = (await sql.query('SELECT change_seq FROM recorridos WHERE uuid = $1', [u]))[0].change_seq;

  const s = await currentState(sql);
  assert.equal(s.lastSyncAt, '2100-01-01T00:00:00.000Z');
  assert.ok(BigInt(s.serverCursor) >= BigInt(seq));
});
