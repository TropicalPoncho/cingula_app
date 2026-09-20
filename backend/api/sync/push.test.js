import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { getSql } from '../_lib/db.js';
import { upsertStatement } from '../_lib/outbox.js';
import { applySchema } from '../_lib/schema_loader.js';
import { currentState } from './state.js';
import push from './push.js';

// Los casos con DB se saltean (no fallan) sin DATABASE_URL: correr contra una rama dev de Neon.
const skip = process.env.DATABASE_URL ? false : 'requires DATABASE_URL (Neon dev branch)';

process.env.SYNC_API_KEY ||= 'test-key';

async function callPush(body) {
  let status;
  let json;
  const response = { status(s) { status = s; return this; }, json(j) { json = j; return this; } };
  await push({ method: 'POST', headers: { authorization: `Bearer ${process.env.SYNC_API_KEY}` }, body }, response);
  return { status, json };
}

const audioItem = (uuid, version, extra = {}) => ({
  id: 1,
  table_name: 'audios',
  record_uuid: uuid,
  op: 'update',
  payload: { uuid, title: 't', logical_version: version, updated_at: 1700000000 + version, ...extra },
});

test('sin schema_version 2 el push se rechaza con 400', async () => {
  for (const schema_version of [undefined, 1]) {
    const r = await callPush({ schema_version, outbox: [audioItem(randomUUID(), 1)] });
    assert.equal(r.status, 400);
    assert.equal(r.json.error, 'schema_version 2 required');
  }
});

test('tabla vieja fuera del whitelist -> 400 aun con schema_version 2', async () => {
  const item = { ...audioItem(randomUUID(), 1), table_name: 'geo_paths' };
  const r = await callPush({ schema_version: 2, outbox: [item] });
  assert.equal(r.status, 400);
});

test('push tipado contra Neon', { skip }, async (t) => {
  const sql = getSql();
  await applySchema(sql);
  const created = { audios: [], obras: [], paths: [], triggers: [] };
  t.after(async () => {
    // hijos primero
    for (const table of ['triggers', 'paths', 'obras', 'audios']) {
      for (const u of created[table]) {
        await sql.query(`DELETE FROM ${table} WHERE uuid = $1`, [u]);
        await sql.query('DELETE FROM entity_prev WHERE record_uuid = $1', [u]);
      }
    }
  });
  const seqOf = async (uuid) => (await sql.query('SELECT change_seq FROM audios WHERE uuid = $1', [uuid]))[0]?.change_seq;
  const prevs = async (uuid) => sql.query('SELECT version FROM entity_prev WHERE record_uuid = $1', [uuid]);
  const apply = (items) => sql.transaction(items.map((i) => upsertStatement(sql, i)));

  const a = randomUUID();
  created.audios.push(a);

  await t.test('insert, re-push idempotente y ventana de 1 version anterior', async () => {
    await apply([audioItem(a, 1)]);
    const s1 = await seqOf(a);
    assert.ok(Number(s1) > 0);
    await apply([audioItem(a, 1)]);
    assert.equal(await seqOf(a), s1);
    assert.equal((await prevs(a)).length, 0);
    await apply([audioItem(a, 2)]);
    assert.ok(Number(await seqOf(a)) > Number(s1));
    await apply([audioItem(a, 3)]);
    const p = await prevs(a);
    assert.equal(p.length, 1);
    assert.equal(p[0].version, 2);
  });

  await t.test('hijo antes que padre se aplica (FK diferidas)', async () => {
    const obra = randomUUID(), path = randomUUID(), trig = randomUUID();
    created.obras.push(obra); created.paths.push(path); created.triggers.push(trig);
    const base = { logical_version: 1, updated_at: 1700000000 };
    await apply([
      { id: 1, table_name: 'triggers', record_uuid: trig, op: 'insert',
        payload: { uuid: trig, path_uuid: path, name: 'x', latitude: 1, longitude: 2, radius_meters: 3, ...base } },
      { id: 2, table_name: 'paths', record_uuid: path, op: 'insert',
        payload: { uuid: path, obra_uuid: obra, kind: 'route', name: 'p', ...base } },
      { id: 3, table_name: 'obras', record_uuid: obra, op: 'insert',
        payload: { uuid: obra, name: 'o', visibility: 'draft', ...base } },
    ]);
    const rows = await sql.query('SELECT 1 FROM triggers WHERE uuid = $1', [trig]);
    assert.equal(rows.length, 1);
  });

  await t.test('delete deja tombstone y la fila sigue existiendo', async () => {
    await apply([{ id: 9, table_name: 'audios', record_uuid: a, op: 'delete', payload: { logical_version: 4 } }]);
    const rows = await sql.query('SELECT deleted_at FROM audios WHERE uuid = $1', [a]);
    assert.notEqual(rows[0].deleted_at, null);
  });

  await t.test('state: serverCursor numerico', async () => {
    const s = await currentState(sql);
    assert.match(s.serverCursor, /^\d+$/);
    assert.notEqual(s.lastSyncAt, null);
  });
});
