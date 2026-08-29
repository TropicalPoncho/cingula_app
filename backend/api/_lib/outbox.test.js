import test from 'node:test';
import assert from 'node:assert/strict';
import { extractVersion, validateOutboxItem } from './outbox.js';

test('extractVersion devuelve la version entera', () => {
  assert.equal(extractVersion({ payload: { logical_version: 3 } }), 3);
});

test('extractVersion devuelve null si no hay payload', () => {
  assert.equal(extractVersion({ payload: null }), null);
});

test('extractVersion no coerciona strings', () => {
  assert.equal(extractVersion({ payload: { logical_version: '3' } }), null);
});

const validItem = {
  id: 12,
  table_name: 'geo_triggers',
  record_uuid: '8f14e45f-ceea-467a-9f4b-1c2d3e4f5a6b',
  op: 'update',
  payload: { logical_version: 2 },
};

test('validateOutboxItem devuelve null para un item bien formado', () => {
  assert.equal(validateOutboxItem(validItem), null);
});

test('validateOutboxItem exige record_uuid', () => {
  const { record_uuid, ...rest } = validItem;
  assert.notEqual(validateOutboxItem(rest), null);
});

test('validateOutboxItem rechaza op invalido', () => {
  assert.notEqual(validateOutboxItem({ ...validItem, op: 'upsert' }), null);
});

test('validateOutboxItem rechaza table_name fuera de whitelist', () => {
  assert.notEqual(validateOutboxItem({ ...validItem, table_name: 'users' }), null);
});

test('validateOutboxItem exige logical_version entero >= 1', () => {
  assert.notEqual(validateOutboxItem({ ...validItem, payload: {} }), null);
  assert.notEqual(validateOutboxItem({ ...validItem, payload: { logical_version: 0 } }), null);
});

test('validateOutboxItem exige id entero', () => {
  assert.notEqual(validateOutboxItem({ ...validItem, id: 'not-an-int' }), null);
});
