import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { makeRows, makePages } from '../src/test/fixtures.js';

const SCRIPT = fileURLToPath(new URL('./measure-pull.mjs', import.meta.url));
const PAGE = 30; // el servidor de prueba ignora `limit` y sirve páginas de 30: ejercita la paginación
const rows = makeRows();
const pages = makePages(rows, PAGE);

let server;
let base;
before(async () => {
  server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    if (url.pathname !== '/sync/pull') { res.writeHead(404).end(); return; }
    if (req.headers.authorization !== 'Bearer test') {
      res.writeHead(401, { 'content-type': 'application/json' }).end('{"error":"unauthorized"}');
      return;
    }
    const cursor = url.searchParams.get('cursor');
    const page = pages.find((p, i) => (i === 0 ? cursor === '0' : pages[i - 1].nextCursor === cursor));
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(page));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

function run(env) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [SCRIPT, base], { env: { ...process.env, WEB_API_KEY: '', ...env } });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

test('con clave correcta imprime agregados paginados', async () => {
  const { code, stdout, stderr } = await run({ WEB_API_KEY: 'test' });
  assert.equal(code, 0, stderr);
  assert.match(stdout, new RegExp(`^paginas: ${pages.length}$`, 'm'));
  assert.ok(pages.length > 1);
  const gaps = Number(/^huecos_total: (\d+)$/m.exec(stdout)?.[1]);
  assert.ok(gaps >= 1, stdout);
  assert.match(stdout, /^triggers_por_path_route_max_p50_p95: /m);
  assert.match(stdout, /^audios_usados_por_mas_de_un_path: 1$/m); // auFinal en ruta y portal de la obra A
  assert.match(stdout, /^paths_con_position_repetida: 1$/m);
});

test('la salida no contiene uuids ni nombres de las fixtures (T-12-13)', async () => {
  const { stdout } = await run({ WEB_API_KEY: 'test' });
  assert.doesNotMatch(stdout, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
  const secrets = new Set();
  for (const { payload } of rows) {
    for (const k of ['uuid', 'name', 'title', 'description', 'bio']) {
      if (typeof payload[k] === 'string' && payload[k].length >= 4) secrets.add(payload[k]);
    }
  }
  assert.ok(secrets.size > 20);
  for (const s of secrets) assert.ok(!stdout.includes(s), `filtró "${s}"`);
});

test('sin WEB_API_KEY sale con 2 y uso en stderr', async () => {
  const { code, stderr, stdout } = await run({});
  assert.equal(code, 2);
  assert.match(stderr, /Uso:/);
  assert.equal(stdout, '');
});

test('clave incorrecta sale distinto de 0 con el 401 en stderr, sin imprimir la clave', async () => {
  const { code, stderr, stdout } = await run({ WEB_API_KEY: 'clave-mala-123' });
  assert.notEqual(code, 0);
  assert.match(stderr, /401/);
  assert.ok(!stderr.includes('clave-mala-123') && !stdout.includes('clave-mala-123'));
});
