import test from 'node:test';
import assert from 'node:assert/strict';
import { requireApiKey, AUTH_ERROR } from './auth.js';

function withApiKey(value, fn) {
  const original = process.env.SYNC_API_KEY;
  process.env.SYNC_API_KEY = value;
  try {
    return fn();
  } finally {
    if (original === undefined) delete process.env.SYNC_API_KEY;
    else process.env.SYNC_API_KEY = original;
  }
}

test('sin header authorization devuelve error', () => {
  withApiKey('right', () => {
    assert.equal(requireApiKey({ headers: {} }), AUTH_ERROR);
  });
});

test('key incorrecta devuelve error', () => {
  withApiKey('right', () => {
    assert.equal(
      requireApiKey({ headers: { authorization: 'Bearer wrong' } }),
      AUTH_ERROR,
    );
  });
});

test('key correcta devuelve null', () => {
  withApiKey('right', () => {
    assert.equal(requireApiKey({ headers: { authorization: 'Bearer right' } }), null);
  });
});

test('prefijo Bearer case-insensitive', () => {
  withApiKey('right', () => {
    assert.equal(requireApiKey({ headers: { authorization: 'bearer right' } }), null);
  });
});

test('sin prefijo Bearer igual valida el token', () => {
  withApiKey('right', () => {
    assert.equal(requireApiKey({ headers: { authorization: 'right' } }), null);
  });
});

test('SYNC_API_KEY vacío rechaza cualquier request', () => {
  withApiKey('', () => {
    assert.equal(
      requireApiKey({ headers: { authorization: 'Bearer anything' } }),
      AUTH_ERROR,
    );
  });
});

test('SYNC_API_KEY no seteado rechaza cualquier request', () => {
  const original = process.env.SYNC_API_KEY;
  delete process.env.SYNC_API_KEY;
  try {
    assert.equal(
      requireApiKey({ headers: { authorization: 'Bearer anything' } }),
      AUTH_ERROR,
    );
  } finally {
    if (original !== undefined) process.env.SYNC_API_KEY = original;
  }
});

test('key de largo distinto no lanza excepción', () => {
  withApiKey('a-much-longer-expected-key-value', () => {
    assert.doesNotThrow(() => {
      requireApiKey({ headers: { authorization: 'Bearer short' } });
    });
    assert.equal(
      requireApiKey({ headers: { authorization: 'Bearer short' } }),
      AUTH_ERROR,
    );
  });
});
