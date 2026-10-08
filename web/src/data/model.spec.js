import { describe, it, expect } from 'vitest';
import { TABLE_SPEC } from '../../api/_lib/spec.js';
import { USED_COLUMNS, emptyTables, applyRows, buildModel } from './model.js';
import { makeRows, ID, SENSITIVE, HTML_NAME } from '../test/fixtures.js';

describe('contrato con el servidor (reemplaza el tipado, D-19)', () => {
  it('USED_COLUMNS ⊆ TABLE_SPEC y cubre las 7 tablas', () => {
    expect(Object.keys(USED_COLUMNS).sort()).toEqual(Object.keys(TABLE_SPEC).sort());
    for (const [t, cols] of Object.entries(USED_COLUMNS)) {
      for (const c of cols) expect(Object.keys(TABLE_SPEC[t].columns), `${t}.${c}`).toContain(c);
    }
  });

  it('la lista blanca de obras son 4 columnas, sin la caja del servidor (D-20)', () => {
    expect(USED_COLUMNS.obras).toEqual(['uuid', 'name', 'recorrido_uuid', 'visibility']);
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

describe('buildModel', () => {
  const { tables } = applyRows(emptyTables(), makeRows());
  const m = buildModel(tables);
  const { obra, path, trigger, recorrido } = m.byId;

  it('obra borrada y sus hijos huérfanos no aparecen (cascada, WEB-08)', () => {
    expect(obra.has(ID.obD)).toBe(false);
    expect(path.has(ID.pathD)).toBe(false);
    expect(trigger.has(ID.trgOrphan)).toBe(false);
    expect(m.orphans).toEqual({ paths: 1, triggers: 1, obra_artistas: 1 });
  });

  it('el trigger borrado no aparece y el obra_artistas borrado no da crédito', () => {
    expect(trigger.has(ID.trgDeleted)).toBe(false);
    expect(obra.get(ID.obB).artistas.map((a) => a.name)).toEqual(['Bruno Mayo']);
    expect(obra.get(ID.obB).routes[0].triggers).toHaveLength(3);
  });

  it('un path con audio inexistente tiene audio null; los existentes se resuelven', () => {
    expect(path.get(ID.pathC).audio).toBeNull();
    expect(path.get(ID.pathB).audio.has_file).toBe(false);
    expect(path.get(ID.pathB).grabacion.kind).toBe('grabacion');
    expect(path.get(ID.pathA).audio).toMatchObject({ title: 'Audio final', has_file: true, duration_seconds: 75 });
  });

  it('triggers ordenados por (position, uuid), numerados por índice en la lista filtrada (H5)', () => {
    const ts = path.get(ID.pathA).triggers;
    expect(ts.map((t) => t.uuid)).toEqual(Array.from({ length: 32 }, (_, i) => ID.trA(i)));
    expect(ts.map((t) => t.index)).toEqual(Array.from({ length: 32 }, (_, i) => i));
    expect(ts[11].index).toBe(11); // su `position` es 10: el índice no sale de position + 1
    expect(ts[0]).not.toHaveProperty('name'); // sin nombre (D-16/R4)
    expect(ts[0].path).toBe(path.get(ID.pathA));
  });

  it('huecos: la ruta A tiene exactamente un salto de ~40 m entre los índices 15 y 16', () => {
    const { gaps, medianRadius, spacing } = path.get(ID.pathA);
    expect(gaps).toHaveLength(1);
    expect(gaps[0]).toMatchObject({ from: 15, to: 16 });
    expect(gaps[0].meters).toBeCloseTo(40, 0);
    expect(medianRadius).toBe(12);
    expect(spacing).toBeCloseTo(10, 0);
    expect(path.get(ID.pathB).gaps).toEqual([]);
  });

  it('el portal expone su primer trigger y la descripción de ese trigger', () => {
    const p = path.get(ID.portalA);
    expect(p.kind).toBe('portal');
    expect(p.trigger.uuid).toBe(ID.trgPortal);
    expect(p.description).toBe('Descripción del portal.');
    expect(obra.get(ID.obA).portals).toEqual([p]);
  });

  it('obra C: sin recorrido, sin cobertura, 0 triggers; el HTML llega como texto', () => {
    const c = obra.get(ID.obC);
    expect(c.recorrido).toBeNull();
    expect(c.outline).toBeNull();
    expect(c.routes[0].triggers).toEqual([]);
    expect(c.name).toBe(HTML_NAME);
    for (const k of ['cover', 'maxRadius']) expect(obra.get(ID.obA)).not.toHaveProperty(k);
  });

  it('outline (D-20): A = 3 anillos (2 tramos + portal), B = 1, C = null', () => {
    const o = (id) => obra.get(id).outline;
    expect(o(ID.obA).polygons).toHaveLength(3);
    expect(o(ID.obB).polygons).toHaveLength(1);
    expect(o(ID.obC)).toBeNull();
    const b = o(ID.obA).bounds;
    expect(b.minLat).toBeLessThan(b.maxLat);
    expect(b.minLon).toBeLessThan(b.maxLon);
  });

  it('créditos del recorrido 1 = unión sin duplicados, ordenada, de los artistas de A y B; cada artista conoce sus obras', () => {
    const r1 = recorrido.get(ID.rec1);
    expect(r1.obras.map((o) => o.uuid)).toEqual([ID.obA, ID.obB].sort((a, b) => obra.get(a).name.localeCompare(obra.get(b).name, 'es')));
    expect(r1.artistas.map((a) => a.name)).toEqual(['Ana Lúcar', 'Bruno Mayo']);
    expect(m.byId.artista.get(ID.arB).obras.map((o) => o.uuid).sort()).toEqual([ID.obA, ID.obB]);
    expect(recorrido.get(ID.rec2).artistas).toEqual([]);
  });

  it('conteos de la leyenda: 3 obras, 3 paths route, 35 triggers de rutas, 1 portal', () => {
    expect(m.counts).toEqual({ obras: 3, paths: 3, triggers: 35, portales: 1 });
  });

  it('listas ordenadas por nombre (es) y sin columnas sensibles', () => {
    expect(m.artistas.map((a) => a.name)).toEqual(['Ana Lúcar', 'Bruno Mayo']);
    expect(m.recorridos.map((r) => r.name)).toEqual(['Recorrido Norte', 'Recorrido Sur']);
    for (const a of m.artistas) for (const s of SENSITIVE) expect(a).not.toHaveProperty(s);
  });

  it('recorrido_uuid desconocido -> sin recorrido; enum fuera del CHECK se conserva crudo', () => {
    const rows = makeRows().map((r) =>
      r.payload.uuid === ID.obA ? { ...r, payload: { ...r.payload, recorrido_uuid: 'no-existe', visibility: 'otra' } } : r,
    );
    const mm = buildModel(applyRows(emptyTables(), rows).tables);
    expect(mm.byId.obra.get(ID.obA).recorrido).toBeNull();
    expect(mm.byId.obra.get(ID.obA).visibility).toBe('otra');
  });

  it('tablas vacías -> modelo vacío', () => {
    expect(buildModel(emptyTables()).counts).toEqual({ obras: 0, paths: 0, triggers: 0, portales: 0 });
  });
});
