import test from 'node:test';
import assert from 'node:assert/strict';
import { apiKeyRole } from './auth.js';

function withEnv(vars, fn) {
  const originals = {};
  for (const key of Object.keys(vars)) {
    originals[key] = process.env[key];
    if (vars[key] === undefined) delete process.env[key];
    else process.env[key] = vars[key];
  }
  try {
    return fn();
  } finally {
    for (const key of Object.keys(vars)) {
      if (originals[key] === undefined) delete process.env[key];
      else process.env[key] = originals[key];
    }
  }
}

test('sin header authorization devuelve null', () => {
  withEnv({ SYNC_API_KEY: 'right', WEB_API_KEY: undefined }, () => {
    assert.equal(apiKeyRole({ headers: {} }), null);
  });
});

test('key incorrecta devuelve null', () => {
  withEnv({ SYNC_API_KEY: 'right', WEB_API_KEY: undefined }, () => {
    assert.equal(
      apiKeyRole({ headers: { authorization: 'Bearer wrong' } }),
      null,
    );
  });
});

test('SYNC_API_KEY correcta devuelve sync', () => {
  withEnv({ SYNC_API_KEY: 'right', WEB_API_KEY: undefined }, () => {
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer right' } }), 'sync');
  });
});

test('prefijo Bearer case-insensitive', () => {
  withEnv({ SYNC_API_KEY: 'right', WEB_API_KEY: undefined }, () => {
    assert.equal(apiKeyRole({ headers: { authorization: 'bearer right' } }), 'sync');
  });
});

test('sin prefijo Bearer igual valida el token', () => {
  withEnv({ SYNC_API_KEY: 'right', WEB_API_KEY: undefined }, () => {
    assert.equal(apiKeyRole({ headers: { authorization: 'right' } }), 'sync');
  });
});

test('SYNC_API_KEY vacío rechaza cualquier request por esa clave', () => {
  withEnv({ SYNC_API_KEY: '', WEB_API_KEY: undefined }, () => {
    assert.equal(
      apiKeyRole({ headers: { authorization: 'Bearer anything' } }),
      null,
    );
  });
});

test('SYNC_API_KEY no seteado rechaza cualquier request por esa clave', () => {
  withEnv({ SYNC_API_KEY: undefined, WEB_API_KEY: undefined }, () => {
    assert.equal(
      apiKeyRole({ headers: { authorization: 'Bearer anything' } }),
      null,
    );
  });
});

test('key de largo distinto no lanza excepción', () => {
  withEnv({ SYNC_API_KEY: 'a-much-longer-expected-key-value', WEB_API_KEY: undefined }, () => {
    assert.doesNotThrow(() => {
      apiKeyRole({ headers: { authorization: 'Bearer short' } });
    });
    assert.equal(
      apiKeyRole({ headers: { authorization: 'Bearer short' } }),
      null,
    );
  });
});

test('WEB_API_KEY correcta devuelve web; key desconocida sigue null', () => {
  withEnv({ SYNC_API_KEY: 's', WEB_API_KEY: 'w' }, () => {
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer s' } }), 'sync');
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer w' } }), 'web');
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer x' } }), null);
  });
});

test('SYNC_API_KEY vacío o no seteado nunca da sync, pero WEB_API_KEY sigue dando web', () => {
  withEnv({ SYNC_API_KEY: '', WEB_API_KEY: 'w' }, () => {
    assert.notEqual(apiKeyRole({ headers: { authorization: 'Bearer anything' } }), 'sync');
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer w' } }), 'web');
  });
  withEnv({ SYNC_API_KEY: undefined, WEB_API_KEY: 'w' }, () => {
    assert.notEqual(apiKeyRole({ headers: { authorization: 'Bearer anything' } }), 'sync');
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer w' } }), 'web');
  });
});

test('WEB_API_KEY vacío o no seteado nunca da web, pero SYNC_API_KEY sigue dando sync', () => {
  withEnv({ SYNC_API_KEY: 's', WEB_API_KEY: '' }, () => {
    assert.notEqual(apiKeyRole({ headers: { authorization: 'Bearer anything' } }), 'web');
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer s' } }), 'sync');
  });
  withEnv({ SYNC_API_KEY: 's', WEB_API_KEY: undefined }, () => {
    assert.notEqual(apiKeyRole({ headers: { authorization: 'Bearer anything' } }), 'web');
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer s' } }), 'sync');
  });
});

test('las dos vacías o no seteadas: header vacío nunca matchea', () => {
  withEnv({ SYNC_API_KEY: '', WEB_API_KEY: '' }, () => {
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer ' } }), null);
  });
  withEnv({ SYNC_API_KEY: undefined, WEB_API_KEY: undefined }, () => {
    assert.equal(apiKeyRole({ headers: { authorization: 'Bearer ' } }), null);
  });
});
