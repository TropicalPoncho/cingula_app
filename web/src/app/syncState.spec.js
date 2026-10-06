import { describe, it, expect } from 'vitest';
import { pillState, STALE_MS } from './syncState.js';

const NOW = new Date(2026, 5, 15, 12, 0, 0).getTime();
const at = (msAgo) => NOW - msAgo;
const snap = (over) => ({
  status: 'ready', cursor: '48213', lastPullAt: at(120_000), read: 340, discarded: 2, page: 0, errors: [], retry: null, ...over,
});
const val = (v, label) => v.rows.find((r) => r.label === label)?.value;

describe('pillState: una fila de la matriz por estado', () => {
  it('Leyendo: punto ink, filas leídas, página en curso y botón deshabilitado', () => {
    const v = pillState(snap({ status: 'loading', read: 1000, page: 1 }), NOW, true);
    expect(v).toMatchObject({ tone: 'ink', alert: false, text: 'Leyendo… 1000 filas', button: { label: 'Actualizar datos', disabled: true } });
    expect(val(v, 'Estado')).toBe('Pull en curso · página 2');
  });

  it('Al día: mint, hora relativa, cursor tal cual y conteo de descartadas', () => {
    const v = pillState(snap(), NOW, true);
    expect(v).toMatchObject({ tone: 'mint', text: 'Sync al día · pull hace 2 min', cursorText: 'cursor 48213', button: { label: 'Actualizar datos', disabled: false } });
    expect(val(v, 'Último pull')).toBe('hoy 11:58:00 · hace 2 min');
    expect(val(v, 'Filas leídas')).toBe('340 · 2 con deleted_at descartadas');
    expect(val(v, 'Estado')).toBe('Sin errores');
  });

  it('Al día de otro día: fecha dd.mm.aa en vez de "hoy"', () => {
    const v = pillState(snap({ lastPullAt: new Date(2026, 5, 14, 9, 5, 7).getTime() }), NOW, true);
    expect(val(v, 'Último pull')).toBe('14.06.26 09:05:07');
  });

  it('Desactualizado: > 15 min sin error -> ámbar y texto de antigüedad', () => {
    const v = pillState(snap({ lastPullAt: at(STALE_MS + 60_000) }), NOW, true);
    expect(v).toMatchObject({ tone: 'ambar', alert: false, text: 'Datos de hace 16 min' });
    expect(val(v, 'Estado')).toBe('Hace más de 15 min que no se actualiza.');
    expect(pillState(snap({ lastPullAt: at(STALE_MS) }), NOW, true).tone).toBe('mint'); // el límite no cuenta
  });

  const e1 = { at: at(5_000), cursor: '48213', page: 2, status: 500, text: 'mock failure' };

  it('Error con datos: ámbar + alerta, conserva datos, cursor no avanzó y reintento automático', () => {
    const v = pillState(snap({ status: 'error', errors: [e1], retry: { attempt: 1, nextAt: NOW + 30_000 } }), NOW, true);
    expect(v).toMatchObject({ tone: 'ambar', alert: true, text: 'Error de pull · datos de hace 2 min', button: { label: 'Reintentar lectura', disabled: false }, note: 'Próximo reintento automático en 30 s.' });
    expect(val(v, 'Último pull OK')).toBe('hoy 11:58:00 · hace 2 min');
    expect(val(v, 'Cursor')).toBe('48213 (no avanzó)');
    expect(val(v, 'Estado')).toBe('Pull incompleto: se muestran los datos del último pull completo.');
    expect(v.errors).toEqual(['11:59:55  GET /sync/pull?cursor=48213 → 500 mock failure (página 2)']);
  });

  it('Error con datos tras agotar los reintentos: la nota pasa a "Reintentá cuando tengas conexión."', () => {
    const v = pillState(snap({ status: 'error', errors: [{ ...e1, retry: 3 }], retry: null }), NOW, true);
    expect(v.note).toBe('Reintentá cuando tengas conexión.');
    expect(v.errors[0]).toMatch(/\(página 2\) \(reintento 3 de 3\)$/);
  });

  it('Error sin datos: sin fila de último pull y sin cursor propio', () => {
    const v = pillState(snap({ status: 'error', lastPullAt: null, cursor: null, errors: [{ ...e1, cursor: null, status: null, text: 'Failed to fetch', page: 1 }] }), NOW, true);
    expect(v).toMatchObject({ tone: 'ambar', alert: true, text: 'Error de pull · sin datos', cursorText: '' });
    expect(v.rows.map((r) => r.label)).toEqual(['Cursor', 'Estado']);
    expect(v.errors[0]).toBe('11:59:55  GET /sync/pull?cursor=0 → sin respuesta Failed to fetch (página 1)');
  });

  it('Sin conexión: ink, datos viejos rotulados y botón deshabilitado', () => {
    const v = pillState(snap(), NOW, false);
    expect(v).toMatchObject({ tone: 'ink', text: 'Sin conexión · datos de hace 2 min', button: { label: 'Actualizar datos', disabled: true } });
    expect(val(v, 'Estado')).toBe('La web sólo funciona con conexión.');
  });

  it('las líneas de error nunca contienen credenciales', () => {
    const v = pillState(snap({ status: 'error', errors: [e1] }), NOW, true);
    expect(JSON.stringify(v)).not.toMatch(/Bearer|Authorization/i);
  });
});
