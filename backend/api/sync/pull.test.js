import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { getSql } from '../_lib/db.js';
import { upsertStatement } from '../_lib/outbox.js';
import { applySchema } from '../_lib/schema_loader.js';
import { TABLE_SPEC, SYNCABLE_TABLES } from '../_lib/spec.js';
import { currentCursor } from './state.js';
import pull from './pull.js';

// Los casos con DB se saltean (no fallan) sin DATABASE_URL: correr contra una rama dev de Neon.
const skip = process.env.DATABASE_URL ? false : 'requires DATABASE_URL (Neon dev branch)';

process.env.SYNC_API_KEY ||= 'test-key';

async function callPull(query, key = process.env.SYNC_API_KEY, method = 'GET') {
  let status;
  let json;
  const response = { status(s) { status = s; return this; }, json(j) { json = j; return this; } };
  await pull({ method, headers: key ? { authorization: `Bearer ${key}` } : {}, query }, response);
  return { status, json };
}

test('POST -> 405', async () => {
  const r = await callPull({}, process.env.SYNC_API_KEY, 'POST');
  assert.equal(r.status, 405);
  assert.equal(r.json.error, 'method not allowed');
});

test('GET sin authorization -> 401', async () => {
  const r = await callPull({}, null);
  assert.equal(r.status, 401);
  assert.equal(r.json.error, 'invalid or missing API key');
});

test('cursor invalido -> 400', async () => {
  for (const cursor of ['-1', 'abc', '1.5', '9223372036854775808', ['1', '2']]) {
    const r = await callPull({ cursor });
    assert.equal(r.status, 400, `cursor=${cursor}`);
    assert.equal(r.json.error, 'cursor must be an integer >= 0');
  }
});

test('limit invalido -> 400', async () => {
  for (const limit of ['0', '1001', 'x', '']) {
    const r = await callPull({ limit });
    assert.equal(r.status, 400, `limit=${limit}`);
    assert.equal(r.json.error, 'limit must be an integer between 1 and 1000');
  }
});

test('PULL-01/02: pagina desde un cursor, orden global, borradas incluidas, payload del spec', { skip }, async (t) => {
  const sql = getSql();
  await applySchema(sql);
  const r = randomUUID();
  const a = randomUUID();
  const b = randomUUID();
  t.after(async () => {
    for (const u of [r, a, b]) {
      await sql.query('DELETE FROM entity_prev WHERE record_uuid = $1', [u]);
    }
    await sql.query('DELETE FROM recorridos WHERE uuid = $1', [r]);
    await sql.query('DELETE FROM audios WHERE uuid = $1', [a]);
    await sql.query('DELETE FROM audios WHERE uuid = $1', [b]);
  });

  const before = await currentCursor(sql);
  await sql.transaction([
    upsertStatement(sql, {
      id: 1, table_name: 'recorridos', record_uuid: r, op: 'insert',
      payload: { uuid: r, name: 'pull-test', logical_version: 1, updated_at: 1700000000 },
    }),
    upsertStatement(sql, {
      id: 2, table_name: 'audios', record_uuid: a, op: 'insert',
      payload: { uuid: a, title: 't', logical_version: 1, updated_at: 1700000000 },
    }),
    upsertStatement(sql, {
      id: 3, table_name: 'audios', record_uuid: b, op: 'insert',
      payload: { uuid: b, title: 't', logical_version: 1, updated_at: 1700000000 },
    }),
  ]);
  await sql.transaction([
    upsertStatement(sql, {
      id: 4, table_name: 'audios', record_uuid: b, op: 'delete',
      payload: { logical_version: 2 },
    }),
  ]);

  let cursor = before;
  const changes = [];
  let last;
  do {
    last = await callPull({ cursor, limit: '1' });
    assert.equal(last.status, 200);
    changes.push(...last.json.changes);
    cursor = last.json.nextCursor;
  } while (last.json.hasMore);

  const seeded = changes.filter((c) => [r, a, b].includes(c.payload.uuid));
  const seqs = seeded.map((c) => BigInt(c.change_seq));
  for (let i = 1; i < seqs.length; i++) assert.ok(seqs[i] > seqs[i - 1], 'change_seq no es estrictamente creciente');
  for (const c of seeded) assert.ok(SYNCABLE_TABLES.includes(c.table));

  const seenUuids = seeded.map((c) => c.payload.uuid);
  assert.equal(seenUuids.filter((u) => u === r).length, 1);
  assert.equal(seenUuids.filter((u) => u === a).length, 1);
  assert.equal(seenUuids.filter((u) => u === b).length, 1);

  const bRow = seeded.find((c) => c.payload.uuid === b);
  assert.notEqual(bRow.payload.deleted_at, null);

  for (const c of changes) {
    assert.equal(typeof c.change_seq, 'string');
  }
  assert.equal(typeof last.json.nextCursor, 'string');

  const rRow = seeded.find((c) => c.payload.uuid === r);
  assert.deepEqual(
    Object.keys(rRow.payload).sort(),
    Object.keys(TABLE_SPEC[rRow.table].columns).sort(),
  );
  assert.equal(rRow.payload.name, 'pull-test');
  assert.equal(rRow.payload.logical_version, 1);
  assert.equal(rRow.payload.updated_at, 1700000000);

  const again = await callPull({ cursor: last.json.nextCursor, limit: '1000' });
  assert.equal(again.status, 200);
  assert.equal(again.json.hasMore, false);
  if (again.json.changes.length === 0) {
    assert.equal(again.json.nextCursor, last.json.nextCursor);
  }
});

test('PULL-01: WEB_API_KEY de solo lectura puede leer pull', { skip }, async (t) => {
  const sql = getSql();
  await applySchema(sql);
  const original = process.env.WEB_API_KEY;
  process.env.WEB_API_KEY = 'web-test-key';
  t.after(() => {
    if (original === undefined) delete process.env.WEB_API_KEY;
    else process.env.WEB_API_KEY = original;
  });
  const r = await callPull({ cursor: '0', limit: '1' }, 'web-test-key');
  assert.equal(r.status, 200);
});
