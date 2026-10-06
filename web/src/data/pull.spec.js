import { describe, it, expect, vi, afterEach } from 'vitest';
import { pullAll, HttpError } from './pull.js';

const res = (status, body) => ({ ok: status >= 200 && status < 300, status, text: async () => JSON.stringify(body) });
afterEach(() => vi.unstubAllGlobals());

describe('pullAll', () => {
  it('recorre las páginas, manda Authorization y devuelve todas las filas con el último cursor', async () => {
    const f = vi.fn()
      .mockResolvedValueOnce(res(200, { changes: [{ table: 'obras', change_seq: '1', payload: {} }], nextCursor: '1', hasMore: true }))
      .mockResolvedValueOnce(res(200, { changes: [{ table: 'obras', change_seq: '2', payload: {} }], nextCursor: '2', hasMore: false }));
    vi.stubGlobal('fetch', f);
    const pages = [];
    const out = await pullAll({ key: 'K', onPage: (p) => pages.push(p) });
    expect(out.rows).toHaveLength(2);
    expect(out.cursor).toBe('2');
    expect(f.mock.calls[0][0]).toBe('/sync/pull?cursor=0&limit=1000');
    expect(f.mock.calls[0][1].headers.Authorization).toBe('Bearer K');
    expect(pages.map((p) => [p.page, p.rows, p.cursor])).toEqual([[1, 1, '1'], [2, 2, '2']]);
  });

  it('el cursor 2^53+1 llega intacto a la URL siguiente (R12)', async () => {
    const big = '9007199254740993';
    const f = vi.fn()
      .mockResolvedValueOnce(res(200, { changes: [], nextCursor: big, hasMore: true }))
      .mockResolvedValueOnce(res(200, { changes: [], nextCursor: big + '5', hasMore: false }));
    vi.stubGlobal('fetch', f);
    await pullAll({ key: 'K' });
    expect(f.mock.calls[1][0]).toContain(`cursor=${big}&`);
  });

  it('anti-bucle: hasMore con cursor que no avanza lanza error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res(200, { changes: [], nextCursor: '0', hasMore: true })));
    await expect(pullAll({ key: 'K' })).rejects.toThrow(/no avanza/);
  });

  it('401 -> HttpError con status, página y cursor', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res(401, { error: 'x' })));
    const e = await pullAll({ key: 'K' }).catch((x) => x);
    expect(e).toBeInstanceOf(HttpError);
    expect(e.status).toBe(401);
    expect([e.page, e.cursor]).toEqual([1, '0']);
  });
});
