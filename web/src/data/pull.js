// Cliente único de pull (ADR-004): lo usan la SPA y el script de medición (Node 22+).
// Sin dependencias. El cursor viaja siempre como string: bigint de Postgres, nunca Number() (R12).
export class HttpError extends Error {
  constructor(status, body, page, cursor) {
    super(`HTTP ${status}`);
    this.status = status;
    this.body = body;
    this.page = page;
    this.cursor = cursor;
  }
}

export async function pullAll({ base = '', key, cursor = '0', limit = 1000, signal, onPage }) {
  const rows = [];
  for (let page = 1; ; page++) {
    const t0 = Date.now();
    const res = await fetch(`${base}/sync/pull?cursor=${cursor}&limit=${limit}`, {
      headers: { Authorization: `Bearer ${key}` },
      cache: 'no-store',
      signal,
    });
    const text = await res.text().catch(() => '');
    if (!res.ok) throw new HttpError(res.status, text, page, cursor);
    const { changes, nextCursor, hasMore } = JSON.parse(text);
    for (const c of changes) rows.push(c);
    onPage?.({ page, rows: rows.length, cursor: nextCursor, bytes: text.length, ms: Date.now() - t0 });
    if (!hasMore) return { rows, cursor: nextCursor };
    // Anti-bucle: hasMore con cursor que no avanza = bug del servidor; no reintentar eternamente.
    if (nextCursor === cursor) throw new Error(`pull no avanza (cursor ${cursor})`);
    cursor = nextCursor;
  }
}
