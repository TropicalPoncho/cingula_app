import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useStore, load, resetStore } from './store.js';
import { makeRows, makePages, ID } from '../test/fixtures.js';

beforeEach(() => {
  resetStore(); // módulo con estado: cada test arranca limpio
  sessionStorage.setItem('cingula.key', 'K');
});
afterEach(() => vi.unstubAllGlobals());

const ok = (body) => ({ ok: true, status: 200, text: async () => JSON.stringify(body) });
const fail = (status) => ({ ok: false, status, text: async () => 'boom' });

describe('store', () => {
  it('pull completo: reemplaza todo de una vez, cursor string y filas leídas', async () => {
    const rows = makeRows();
    const pages = makePages(rows, 30);
    let i = 0;
    vi.stubGlobal('fetch', vi.fn(async () => ok(pages[i++])));
    const { result } = renderHook(() => useStore());
    await act(() => load());
    expect(result.current.status).toBe('ready');
    expect(result.current.cursor).toBe(rows.at(-1).change_seq);
    expect(result.current.read).toBe(rows.length);
    expect(result.current.tables.obras.has(ID.obA)).toBe(true);
    expect(result.current.tables.obras.has(ID.obD)).toBe(false);
  });

  it('todo-o-nada: un fallo en la página 2 deja las tablas previas intactas', async () => {
    const pages = makePages(makeRows(), 30);
    let i = 0;
    vi.stubGlobal('fetch', vi.fn(async () => ok(pages[i++])));
    const { result } = renderHook(() => useStore());
    await act(() => load());
    const before = result.current.tables;

    let n = 0;
    vi.stubGlobal('fetch', vi.fn(async () => (++n === 1 ? ok(pages[0]) : fail(500))));
    await act(() => load());
    expect(result.current.status).toBe('error');
    expect(result.current.tables).toBe(before); // misma identidad: nada se pisó
    expect(result.current.errors.at(-1)).toMatchObject({ status: 500, page: 2 });
    expect(JSON.stringify(result.current.errors)).not.toContain('Bearer');
  });

  it('primer pull fallido: status error y sin datos', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => fail(503)));
    const { result } = renderHook(() => useStore());
    await act(() => load());
    expect(result.current.status).toBe('error');
    expect(result.current.lastPullAt).toBeNull();
  });

  it('401 limpia la clave, vacía el store y manda a /acceso?motivo=401', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => fail(401)));
    const { result } = renderHook(() => useStore());
    await act(() => load());
    expect(sessionStorage.getItem('cingula.key')).toBeNull();
    expect(location.pathname + location.search).toBe('/acceso?motivo=401');
    expect(result.current.status).toBe('idle');
  });

  it('salir de la web mientras hay un pull en vuelo: el resultado tardío se ignora', async () => {
    const pages = makePages(makeRows(), 1000);
    let release;
    vi.stubGlobal('fetch', vi.fn(() => new Promise((r) => (release = () => r(ok(pages[0]))))));
    const { result } = renderHook(() => useStore());
    let p;
    act(() => { p = load(); });
    act(() => resetStore());
    await act(async () => { release(); await p; });
    expect(result.current.status).toBe('idle');
    expect(result.current.tables.obras.size).toBe(0);
  });
});
