import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useStore, load, refresh, retryNow, resetStore } from './store.js';
import { makeRows, makePages, pageAfter, ID } from '../test/fixtures.js';

beforeEach(() => {
  resetStore(); // módulo con estado: cada test arranca limpio
  sessionStorage.setItem('cingula.key', 'K');
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

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

describe('store: reintento automático', () => {
  it('3 reintentos cada 30 s y después queda en error sin agendar más', async () => {
    vi.useFakeTimers();
    const f = vi.fn(async () => fail(500));
    vi.stubGlobal('fetch', f);
    const { result } = renderHook(() => useStore());
    await act(() => load());
    expect(f).toHaveBeenCalledTimes(1);
    expect(result.current.retry).toMatchObject({ attempt: 1 });

    for (const n of [2, 3, 4]) {
      await act(() => vi.advanceTimersByTimeAsync(29_999));
      expect(f).toHaveBeenCalledTimes(n - 1); // todavía no
      await act(() => vi.advanceTimersByTimeAsync(1));
      expect(f).toHaveBeenCalledTimes(n);
    }
    expect(result.current.retry).toBeNull();
    await act(() => vi.advanceTimersByTimeAsync(5 * 60_000));
    expect(f).toHaveBeenCalledTimes(4); // 1 inicial + exactamente 3 reintentos
    expect(result.current.errors.map((e) => e.retry)).toEqual([undefined, 1, 2, 3]);
  });

  it('un éxito (o el reintento manual) cancela el reintento pendiente', async () => {
    vi.useFakeTimers();
    const pages = makePages(makeRows(), 1000);
    let bad = true;
    const f = vi.fn(async () => (bad ? fail(503) : ok(pages[0])));
    vi.stubGlobal('fetch', f);
    const { result } = renderHook(() => useStore());
    await act(() => load());
    expect(result.current.retry).not.toBeNull();
    bad = false;
    await act(() => retryNow());
    expect(result.current.status).toBe('ready');
    expect(result.current.retry).toBeNull();
    expect(result.current.errors).toEqual([]);
    await act(() => vi.advanceTimersByTimeAsync(120_000));
    expect(f).toHaveBeenCalledTimes(2); // el timer agendado no corrió
  });

  it('resetStore cancela el reintento pendiente', async () => {
    vi.useFakeTimers();
    const f = vi.fn(async () => fail(500));
    vi.stubGlobal('fetch', f);
    await act(() => load());
    resetStore();
    await act(() => vi.advanceTimersByTimeAsync(120_000));
    expect(f).toHaveBeenCalledTimes(1);
  });
});

describe('store: refresco incremental y conexión', () => {
  const edited = (rows) => {
    const last = BigInt(rows.at(-1).change_seq);
    const a = rows.find((r) => r.payload.uuid === ID.obA);
    const b = rows.find((r) => r.payload.uuid === ID.obB);
    return [
      { ...a, change_seq: String(last + 1n), payload: { ...a.payload, name: 'Obra Aurora (editada)' } },
      { ...b, change_seq: String(last + 2n), payload: { ...b.payload, deleted_at: 1_700_000_999 } },
    ];
  };

  it('refresh() pide desde el cursor guardado: una edición reemplaza, un borrado desaparece', async () => {
    const rows = makeRows();
    const f = vi.fn(async (url) => ok(pageAfter(rows, new URL(url, 'http://x').searchParams.get('cursor'), 1000)));
    vi.stubGlobal('fetch', f);
    const { result } = renderHook(() => useStore());
    await act(() => load());
    const cursor0 = result.current.cursor;
    expect(result.current.tables.obras.has(ID.obB)).toBe(true);

    rows.push(...edited(rows));
    await act(() => refresh());
    expect(f.mock.calls.at(-1)[0]).toContain(`cursor=${cursor0}`);
    expect(result.current.tables.obras.get(ID.obA).name).toBe('Obra Aurora (editada)');
    expect(result.current.tables.obras.has(ID.obB)).toBe(false);
    expect(BigInt(result.current.cursor)).toBeGreaterThan(BigInt(cursor0));
    expect(result.current.read).toBe(2);
    expect(result.current.discarded).toBe(1);
  });

  it('el cursor nunca retrocede aunque el servidor devuelva uno menor', async () => {
    const pages = makePages(makeRows(), 1000);
    const f = vi.fn()
      .mockResolvedValueOnce(ok(pages[0]))
      .mockResolvedValueOnce(ok({ changes: [], nextCursor: '1', hasMore: false }));
    vi.stubGlobal('fetch', f);
    const { result } = renderHook(() => useStore());
    await act(() => load());
    const cursor0 = result.current.cursor;
    await act(() => refresh());
    expect(result.current.status).toBe('ready');
    expect(result.current.cursor).toBe(cursor0);
  });

  it('un refresco fallido no toca las tablas y rotula el error con datos previos', async () => {
    const pages = makePages(makeRows(), 1000);
    const f = vi.fn().mockResolvedValueOnce(ok(pages[0])).mockResolvedValue(fail(500));
    vi.stubGlobal('fetch', f);
    const { result } = renderHook(() => useStore());
    await act(() => load());
    const { tables, cursor, lastPullAt } = result.current;
    await act(() => refresh());
    expect(result.current).toMatchObject({ status: 'error', tables, cursor, lastPullAt });
  });

  it('online/offline siguen a navigator.onLine', () => {
    const { result } = renderHook(() => useStore());
    act(() => { window.dispatchEvent(new Event('offline')); });
    expect(result.current.online).toBe(false);
    act(() => { window.dispatchEvent(new Event('online')); });
    expect(result.current.online).toBe(true);
  });
});
