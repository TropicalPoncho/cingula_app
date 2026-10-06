import { describe, it, expect } from 'vitest';
import { TABLE_SPEC } from '../../api/_lib/spec.js';
import { USED_COLUMNS, emptyTables, applyRows } from './model.js';
import { makeRows, ID, SENSITIVE } from '../test/fixtures.js';

describe('contrato con el servidor (reemplaza el tipado, D-19)', () => {
  it('USED_COLUMNS ⊆ TABLE_SPEC y cubre las 7 tablas', () => {
    expect(Object.keys(USED_COLUMNS).sort()).toEqual(Object.keys(TABLE_SPEC).sort());
    for (const [t, cols] of Object.entries(USED_COLUMNS)) {
      for (const c of cols) expect(Object.keys(TABLE_SPEC[t].columns), `${t}.${c}`).toContain(c);
    }
  });

  it('las columnas sensibles no están en la lista blanca (storage_key sólo deriva has_file)', () => {
    const used = Object.entries(USED_COLUMNS).flatMap(([t, cs]) => cs.map((c) => `${t}.${c}`));
    for (const s of SENSITIVE) {
      const hits = used.filter((u) => u.endsWith(`.${s}`));
      expect(hits).toEqual(s === 'storage_key' ? ['audios.storage_key'] : []);
    }
  });

  it('las filas sintéticas traen TODAS las columnas del spec', () => {
    for (const r of makeRows()) {
      expect(Object.keys(r.payload).sort()).toEqual(Object.keys(TABLE_SPEC[r.table].columns).sort());
    }
  });
});

describe('applyRows', () => {
  const rows = makeRows();
  const out = applyRows(emptyTables(), rows);

  it('ninguna fila resultante trae columnas sensibles ni deleted_at', () => {
    for (const m of Object.values(out.tables)) {
      for (const r of m.values()) {
        for (const c of [...SENSITIVE, 'deleted_at']) expect(r, c).not.toHaveProperty(c);
      }
    }
  });

  it('audios exponen sólo has_file (booleano), nunca el texto de la clave', () => {
    expect(out.tables.audios.get(ID.auFinal).has_file).toBe(true);
    expect(out.tables.audios.get(ID.auNoFile).has_file).toBe(false);
    expect(JSON.stringify([...out.tables.audios.values()])).not.toContain('secreto');
  });

  it('borradas descartadas y contadas', () => {
    const deleted = rows.filter((r) => r.payload.deleted_at != null);
    expect(out.discarded).toBe(deleted.length);
    expect(out.tables.obras.has(ID.obD)).toBe(false);
    expect(out.tables.triggers.has(ID.trgDeleted)).toBe(false);
    expect(out.read).toBe(rows.length);
  });

  it('la última versión gana y una borrada posterior saca la fila', () => {
    const v2 = { table: 'obras', change_seq: '999', payload: { ...rows.find((r) => r.payload.uuid === ID.obA).payload, name: 'Renombrada' } };
    const del = { table: 'obras', change_seq: '1000', payload: { ...v2.payload, deleted_at: 5 } };
    expect(applyRows(out.tables, [v2]).tables.obras.get(ID.obA).name).toBe('Renombrada');
    expect(applyRows(out.tables, [v2, del]).tables.obras.has(ID.obA)).toBe(false);
  });

  it('no muta la entrada e ignora tablas desconocidas', () => {
    const before = emptyTables();
    const res = applyRows(before, [...rows, { table: 'otra', change_seq: '1', payload: { uuid: 'x' } }]);
    expect(before.obras.size).toBe(0);
    expect(res.tables).not.toHaveProperty('otra');
    expect(res.tables.obras.size).toBe(3);
  });
});
