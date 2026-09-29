import test from 'node:test';
import assert from 'node:assert/strict';
import { extractVersion, validateOutboxItem, upsertStatement } from './outbox.js';

const U = '8f14e45f-ceea-467a-9f4b-1c2d3e4f5a6b';
const P = '11111111-1111-4111-8111-111111111111';

test('extractVersion devuelve la version entera, null sin payload, sin coercion', () => {
  assert.equal(extractVersion({ payload: { logical_version: 3 } }), 3);
  assert.equal(extractVersion({ payload: null }), null);
  assert.equal(extractVersion({ payload: { logical_version: '3' } }), null);
});

const validItem = {
  id: 12,
  table_name: 'triggers',
  record_uuid: U,
  op: 'update',
  payload: {
    uuid: U, path_uuid: P, name: 't', latitude: 1, longitude: 2, radius_meters: 5,
    position: 0, logical_version: 2, updated_at: 1700000000,
  },
};

test('validateOutboxItem devuelve null para un item bien formado', () => {
  assert.equal(validateOutboxItem(validItem), null);
});

test('validateOutboxItem rechaza tablas viejas y fuera de whitelist', () => {
  for (const t of ['geo_paths', 'users', 'x"; DROP TABLE audios; --']) {
    assert.notEqual(validateOutboxItem({ ...validItem, table_name: t }), null);
  }
});

test('validateOutboxItem rechaza columna desconocida', () => {
  const item = { ...validItem, payload: { ...validItem.payload, evil: 1 } };
  assert.equal(validateOutboxItem(item), 'unknown column: evil');
});

test('validateOutboxItem exige logical_version >= 1, id entero, uuid y op validos', () => {
  assert.notEqual(validateOutboxItem({ ...validItem, payload: {} }), null);
  assert.notEqual(validateOutboxItem({ ...validItem, payload: { ...validItem.payload, logical_version: 0 } }), null);
  assert.notEqual(validateOutboxItem({ ...validItem, id: 'x' }), null);
  assert.notEqual(validateOutboxItem({ ...validItem, record_uuid: '' }), null);
  assert.notEqual(validateOutboxItem({ ...validItem, op: 'upsert' }), null);
});

test('validateOutboxItem: insert de triggers sin path_uuid falla', () => {
  const { path_uuid, ...payload } = validItem.payload;
  assert.match(validateOutboxItem({ ...validItem, op: 'insert', payload }), /path_uuid/);
});

test('validateOutboxItem: payload.uuid debe coincidir con record_uuid', () => {
  const item = { ...validItem, payload: { ...validItem.payload, uuid: P } };
  assert.notEqual(validateOutboxItem(item), null);
});

test('validateOutboxItem: delete solo exige version', () => {
  const item = { ...validItem, op: 'delete', payload: { logical_version: 3 } };
  assert.equal(validateOutboxItem(item), null);
});

const fakeSql = { query: (text, params) => ({ text, params }) };

test('upsertStatement update: ON CONFLICT con guarda de version y epoch', () => {
  const { text, params } = upsertStatement(fakeSql, validItem);
  assert.match(text, /ON CONFLICT \("uuid"\) DO UPDATE/);
  assert.match(text, /WHERE "triggers"\."logical_version" < EXCLUDED\."logical_version"/);
  assert.match(text, /to_timestamp\(\$\d+\)/);
  assert.match(text, /"position"/);
  assert.equal(params.length, Object.keys(validItem.payload).length);
});

test('upsertStatement delete: UPDATE con tombstone, no INSERT', () => {
  const { text, params } = upsertStatement(fakeSql, { ...validItem, op: 'delete', payload: { logical_version: 3 } });
  assert.match(text, /^UPDATE "triggers" SET deleted_at = now\(\)/);
  assert.doesNotMatch(text, /INSERT/);
  assert.deepEqual(params, [U, 3]);
});
