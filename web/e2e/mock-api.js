// Mocks de red para todos los E2E: ninguna request sale a un servidor real.
import { makeRows, pageAfter } from '../src/test/fixtures.js';

export const KEY = 'clave-buena';

// `limit` es el tamaño de página del mock (el cliente siempre pide 1000); `failPage` = número de
// request de /sync/pull (1-based) que responde `failStatus`.
export async function mockApi(page, { rows = makeRows(), limit = 1000, failPage, failStatus = 500, stateStatus = 200 } = {}) {
  let n = 0;
  await page.route('**/sync/state', (route) =>
    stateStatus === 200
      ? route.fulfill({ json: { serverCursor: rows.at(-1)?.change_seq ?? '0', lastSyncAt: null } })
      : route.fulfill({ status: stateStatus, json: { error: 'invalid or missing API key' } }),
  );
  await page.route('**/sync/pull**', (route) => {
    n++;
    if (n === failPage) return route.fulfill({ status: failStatus, json: { error: 'mock failure' } });
    const cursor = new URL(route.request().url()).searchParams.get('cursor') ?? '0';
    return route.fulfill({ json: pageAfter(rows, cursor, limit) });
  });
}

// Entra "ya logueado": precarga la clave antes de que corra cualquier script de la página.
export const loginAs = (page, key = KEY) =>
  page.addInitScript((k) => sessionStorage.setItem('cingula.key', k), key);
