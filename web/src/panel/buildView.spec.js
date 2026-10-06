import { describe, it, expect } from 'vitest';
import { applyRows, buildModel, emptyTables } from '../data/model.js';
import { makeRows, ID, LONG_NAME, HTML_NAME } from '../test/fixtures.js';
import { buildView, parseSel } from './buildView.js';

const rows = makeRows();
const build = (r = rows) => buildModel(applyRows(emptyTables(), r).tables);
const model = build();
const fact = (v, label) => v.facts.find((f) => f.label === label);
const list = (v, title) => v.lists.find((l) => l.title === title);

describe('parseSel', () => {
  it('null si no hay selección', () => {
    expect(parseSel(model, null)).toBeNull();
    expect(parseSel(model, '')).toBeNull();
  });

  it('tipo fuera de los 5, id mal formado, inexistente o borrado -> stale (T-12-21)', () => {
    for (const s of [
      'foo:obra-A', 'obra', 'obra:', 'obra:<img src=x>', `obra:${'a'.repeat(65)}`, 'obra:no-existe',
      `obra:${ID.obD}`, // borrada
      'constructor:x', '__proto__:x', `path:${ID.portalA}`, `portal:${ID.pathA}`, // tipo que no coincide con kind
      `trigger:${ID.trgPortal}`, // trigger de un portal: no es un trigger de ruta
    ]) {
      expect(parseSel(model, s), s).toEqual({ stale: true });
    }
  });

  it('una selección válida trae la entidad del modelo', () => {
    const p = parseSel(model, `obra:${ID.obA}`);
    expect(p).toMatchObject({ type: 'obra', uuid: ID.obA });
    expect(p.entity).toBe(model.byId.obra.get(ID.obA));
  });
});

describe('buildView obra', () => {
  const v = buildView(model, `obra:${ID.obA}`);

  it('cabecera: etiqueta, título y subtítulo con el recorrido', () => {
    expect(v).toMatchObject({ type: 'obra', typeLabel: 'OBRA', title: 'Obra Aurora', subtitle: 'Recorrido Norte', back: null });
  });

  it('facts: visibilidad con punto, recorrido enlazado, artistas con enlace, cobertura y conteos', () => {
    expect(fact(v, 'Visibilidad')).toMatchObject({ value: 'Pública', dot: 'var(--c-mint)' });
    expect(fact(v, 'Recorrido').links).toEqual([{ label: 'Recorrido Norte', sel: `recorrido:${ID.rec1}` }]);
    expect(fact(v, 'Artistas').links).toEqual([
      { label: 'Ana Lúcar', href: `/artistas/${ID.arA}` },
      { label: 'Bruno Mayo', href: `/artistas/${ID.arB}` },
    ]);
    expect(fact(v, 'Cobertura').value).toMatch(/^\d+ × \d+ m$/);
    expect(fact(v, 'Cobertura').title).toBe('Extensión entre los centros de los triggers (no incluye el radio).');
    expect(fact(v, 'Paths').value).toBe('1');
    expect(fact(v, 'Portales').value).toBe('1');
    expect(v.note).toBeNull();
  });

  it('listas: Paths y Portales con su subtítulo', () => {
    expect(list(v, 'Paths').rows).toEqual([{ label: 'Ruta A', sub: 'route · 32 triggers · 1 hueco', sel: `path:${ID.pathA}` }]);
    expect(list(v, 'Portales').rows).toEqual([
      { label: 'Portal A', sub: 'radio 15 m · +0 ms · con archivo', sel: `portal:${ID.portalA}` },
    ]);
  });

  it('breadcrumb: Recorrido / Obra; el último es el actual (sel null)', () => {
    expect(v.crumbs).toEqual([
      { label: 'Recorrido Norte', sel: `recorrido:${ID.rec1}` },
      { label: 'Obra Aurora', sel: null },
    ]);
  });

  it('pageObras antepone Obras y omite el recorrido', () => {
    expect(buildView(model, `obra:${ID.obA}`, 'pageObras').crumbs).toEqual([
      { label: 'Obras', sel: null, href: '/obras' },
      { label: 'Obra Aurora', sel: null },
    ]);
  });

  it('obra sin recorrido y sin cobertura: "Sin recorrido", "Sin cobertura todavía" y su nota; el nombre con HTML queda como texto', () => {
    const c = buildView(model, `obra:${ID.obC}`);
    expect(c.title).toBe(HTML_NAME);
    expect(c.subtitle).toBe('Sin recorrido');
    expect(fact(c, 'Recorrido')).toEqual({ label: 'Recorrido', value: 'Sin recorrido' });
    expect(fact(c, 'Cobertura')).toEqual({ label: 'Cobertura', value: 'Sin cobertura todavía' });
    expect(c.note).toBe('La obra no tiene triggers, así que no hay dónde dibujarla.');
    expect(c.crumbs).toEqual([{ label: HTML_NAME, sel: null }]);
    expect(fact(c, 'Visibilidad')).toMatchObject({ value: 'Privada', dot: 'var(--ink-200)' });
    expect(list(c, 'Portales')).toBeUndefined(); // lista vacía: se omite
  });

  it('visibilidad fuera del CHECK: valor crudo en mono, nunca oculto (OI-04)', () => {
    const odd = makeRows().map((r) => (r.payload.uuid === ID.obA ? { ...r, payload: { ...r.payload, visibility: 'archivada' } } : r));
    const f = fact(buildView(build(odd), `obra:${ID.obA}`), 'Visibilidad');
    expect(f).toMatchObject({ value: 'archivada', mono: true });
  });

  it('nombre largo: el título llega entero (el recorte es del CSS)', () => {
    expect(buildView(model, `obra:${ID.obB}`).title).toBe(LONG_NAME);
  });

  it('selección inexistente -> { stale: true }; sin selección -> null', () => {
    expect(buildView(model, 'obra:no-existe')).toEqual({ stale: true });
    expect(buildView(model, null)).toBeNull();
  });
});

describe('buildView recorrido', () => {
  const v = buildView(model, `recorrido:${ID.rec1}`);

  it('recorrido: etiqueta, título y breadcrumb sólo con el actual', () => {
    expect(v).toMatchObject({ type: 'recorrido', typeLabel: 'RECORRIDO', title: 'Recorrido Norte', back: null });
    expect(v.crumbs).toEqual([{ label: 'Recorrido Norte', sel: null }]);
  });

  it('recorrido: conteos de sus obras y créditos = artistas únicos con enlace a cada uno (WEB-02)', () => {
    expect(v.facts.map((f) => [f.label, f.value])).toEqual([
      ['Obras', '2'], ['Paths', '2'], ['Portales', '1'], ['Triggers', '35'], ['Créditos', undefined],
    ]);
    expect(fact(v, 'Créditos').links).toEqual([
      { label: 'Ana Lúcar', href: `/artistas/${ID.arA}` },
      { label: 'Bruno Mayo', href: `/artistas/${ID.arB}` },
    ]);
    expect(v.description).toBe('Un recorrido de prueba.');
  });

  it('recorrido: lista de obras con visibilidad y paths', () => {
    expect(list(v, 'Obras').rows).toEqual([
      { label: 'Obra Aurora', sub: 'Pública · 1 path', sel: `obra:${ID.obA}` },
      { label: LONG_NAME, sub: 'Borrador · 1 path', sel: `obra:${ID.obB}` },
    ]);
  });

  it('recorrido vacío: sin lista, sin descripción, créditos "—", ceros', () => {
    const e = buildView(model, `recorrido:${ID.rec2}`);
    expect(e.lists).toEqual([]);
    expect(e.description).toBeNull();
    expect(fact(e, 'Créditos').value).toBe('—');
    expect(fact(e, 'Obras').value).toBe('0');
  });

  it('recorrido: pageObras omite el recorrido (sólo el actual)', () => {
    expect(buildView(model, `recorrido:${ID.rec1}`, 'pageObras').crumbs).toHaveLength(1);
  });
});

describe('buildView path', () => {
  const v = buildView(model, `path:${ID.pathA}`);

  it('path: facts de la ruta de 32 triggers con hueco', () => {
    expect(v).toMatchObject({ type: 'path', typeLabel: 'PATH', title: 'Ruta A', subtitle: 'Obra Aurora · Recorrido Norte' });
    expect(fact(v, 'Obra').links).toEqual([{ label: 'Obra Aurora', sel: `obra:${ID.obA}` }]);
    expect(fact(v, 'kind')).toMatchObject({ value: 'route', mono: true });
    expect(fact(v, 'tolerance_meters')).toMatchObject({ value: '5 m', mono: true });
    expect(fact(v, 'Grabación de origen').value).toBe('—');
    expect(fact(v, 'Triggers').value).toBe('32 · radio 12 m · cada ≈ 10 m');
    expect(fact(v, 'Huecos')).toMatchObject({ value: '1 hueco', dot: 'var(--c-ambar)' });
  });

  it('path: breadcrumb Recorrido / Obra / Path y "Volver a {Obra}"', () => {
    expect(v.crumbs.map((c) => c.label)).toEqual(['Recorrido Norte', 'Obra Aurora', 'Ruta A']);
    expect(v.crumbs.at(-1).sel).toBeNull();
    expect(v.crumbs[1].sel).toBe(`obra:${ID.obA}`);
    expect(v.back).toEqual({ label: 'Obra Aurora', sel: `obra:${ID.obA}` });
  });

  it('path: audio en sus tres estados (archivo, sin archivo, sin asignar o inexistente)', () => {
    expect(v.audio).toMatchObject({ label: 'Audio del path', state: 'file', title: 'Audio final', kind: 'final', duration: '01:15' });
    const b = buildView(model, `path:${ID.pathB}`);
    expect(b.audio).toMatchObject({ state: 'nofile', title: 'Audio sin archivo', duration: '00:30' });
    expect(b.audio.emptyText).toMatch(/todavía no existe en el servidor/);
    const c = buildView(model, `path:${ID.pathC}`); // audio_uuid apunta a un uuid que no existe
    expect(c.audio).toMatchObject({ state: 'none', emptyText: 'Este path no tiene audio asignado.' });
  });

  it('path: la tira intercala el hueco y su nota nombra los triggers', () => {
    expect(v.strip.cells).toHaveLength(33);
    expect(v.strip.cells.filter((c) => c.gap)).toEqual([{ gap: true, meters: 40 }]);
    expect(v.strip.cells[16]).toEqual({ gap: true, meters: 40 }); // entre el cuadro 15 y el 16
    expect(v.strip.ariaLabel).toBe('32 triggers, 1 hueco');
    expect(v.strip.note).toBe('Hueco de ≈ 40 m entre el trigger 016 y el 017.');
  });

  it('path: sin huecos -> "Ninguno" y la nota de solape; sin triggers -> sin tira', () => {
    const b = buildView(model, `path:${ID.pathB}`);
    expect(fact(b, 'Huecos')).toMatchObject({ value: 'Ninguno', dot: 'var(--c-mint)' });
    expect(fact(b, 'Grabación de origen').value).toBe('Grabación');
    expect(b.strip.note).toBe('Los triggers se solapan de punta a punta: el path no tiene huecos.');
    expect(b.strip.ariaLabel).toBe('3 triggers, 0 huecos');
    const c = buildView(model, `path:${ID.pathC}`);
    expect(c.strip).toBeNull();
    expect(fact(c, 'Triggers').value).toBe('0');
    expect(c.crumbs.map((x) => x.label)).toEqual([HTML_NAME, 'Ruta C']); // obra sin recorrido
  });

  it('path: más de 3 huecos recorta la nota a 3 + "+N más"', () => {
    const rs = makeRows().map((r) => {
      if (r.table !== 'triggers' || r.payload.path_uuid !== ID.pathA) return r;
      const i = Number(r.payload.uuid.slice(-2));
      return { ...r, payload: { ...r.payload, longitude: r.payload.longitude + 0.00036 * Math.floor(i / 3) } }; // ~30 m extra cada 3 triggers: muchos huecos
    });
    const w = buildView(build(rs), `path:${ID.pathA}`);
    expect(w.strip.note).toMatch(/\+\d+ más$/);
    expect(w.strip.note.match(/Hueco de/g)).toHaveLength(3);
  });

  it('path: la tabla "Portales de la obra" va por nombre con # = índice, y la lista también', () => {
    expect(v.table).toEqual({
      title: 'Portales de la obra',
      rows: [{ n: 1, name: 'Portal A', sel: `portal:${ID.portalA}`, radius: '15 m', offset: '+0 ms', pos: '-42.07950, -71.62000' }],
    });
    expect(list(v, 'Portales de la obra').rows).toHaveLength(1);
    expect(buildView(model, `path:${ID.pathB}`).table).toBeNull(); // la obra B no tiene portales
  });

  it('path: pageObras antepone Obras y omite el recorrido', () => {
    const w = buildView(model, `path:${ID.pathA}`, 'pageObras');
    expect(w.crumbs.map((c) => c.label)).toEqual(['Obras', 'Obra Aurora', 'Ruta A']);
    expect(w.subtitle).toBe('Obra Aurora');
  });
});

describe('buildView portal', () => {
  const v = buildView(model, `portal:${ID.portalA}`);

  it('portal: Obra, Posición, Radio y Offset con la ayuda de R5', () => {
    expect(v).toMatchObject({ type: 'portal', typeLabel: 'PORTAL', title: 'Portal A', description: 'Descripción del portal.' });
    expect(v.facts.map((f) => f.label)).toEqual(['Obra', 'Posición', 'Radio', 'Offset']);
    expect(fact(v, 'Posición')).toMatchObject({ value: '-42.07950, -71.62000', mono: true });
    expect(fact(v, 'Radio').value).toBe('15 m');
    expect(fact(v, 'Offset')).toMatchObject({ value: '+0 ms', mono: true, title: 'La app todavía ignora el offset de los portales: siempre arranca en 0.' });
  });

  it('portal: crumbs Recorrido / Obra / Portal, "Volver a {Obra}" y audio del portal', () => {
    expect(v.crumbs.map((c) => c.label)).toEqual(['Recorrido Norte', 'Obra Aurora', 'Portal A']);
    expect(v.back).toEqual({ label: 'Obra Aurora', sel: `obra:${ID.obA}` });
    expect(v.audio).toMatchObject({ label: 'Audio del portal', state: 'file' });
    expect(v.lists).toEqual([]); // es el único portal de la obra
  });

  it('portal: sin trigger se lista pero sin Posición/Radio/Offset; y se ve la lista de los otros', () => {
    const rs = makeRows().filter((r) => r.payload.uuid !== ID.trgPortal);
    rs.push({ table: 'paths', change_seq: '900', payload: { ...rs.find((r) => r.payload.uuid === ID.portalA).payload, uuid: 'portal-2', name: 'Zeta', audio_uuid: null } });
    const mm = build(rs);
    const a = buildView(mm, `portal:${ID.portalA}`);
    expect(a.facts.map((f) => f.label)).toEqual(['Obra']);
    expect(a.description).toBeNull();
    expect(list(a, 'Otros portales de la obra').rows).toEqual([{ label: 'Zeta', sub: 'sin archivo todavía', sel: 'portal:portal-2' }]);
    expect(buildView(mm, 'portal:portal-2').audio.state).toBe('none');
    expect(buildView(mm, 'portal:portal-2').audio.emptyText).toBe('Este portal no tiene audio asignado.');
  });

  it('portal: pageObras omite el recorrido', () => {
    expect(buildView(model, `portal:${ID.portalA}`, 'pageObras').crumbs.map((c) => c.label)).toEqual(['Obras', 'Obra Aurora', 'Portal A']);
  });
});

describe('buildView trigger', () => {
  const t7 = `trigger:${ID.trA(7)}`;
  const v = buildView(model, t7);

  it('trigger: anónimo "Trigger 008", facts y nota fija', () => {
    expect(v).toMatchObject({ type: 'trigger', typeLabel: 'TRIGGER', title: 'Trigger 008', subtitle: 'Ruta A · Obra Aurora' });
    expect(v.facts.map((f) => [f.label, f.value ?? f.links[0].label])).toEqual([
      ['Path', 'Ruta A'], ['Posición', expect.stringMatching(/^-42\.08000, -71\.6\d{4}$/)], ['Radio', '12 m'],
      ['Orden', '8 de 32'], ['Offset en el audio', '+8 400 ms'],
    ]);
    expect(v.note).toBe('Los triggers sólo marcan el camino: no tienen nombre ni sonido propio. El sonido del path suena mientras el celular esté dentro de alguno.');
  });

  it('trigger: breadcrumb de 4 niveles y "Volver a {Path}"', () => {
    expect(v.crumbs.map((c) => c.label)).toEqual(['Recorrido Norte', 'Obra Aurora', 'Ruta A', 'Trigger 008']);
    expect(v.crumbs[2].sel).toBe(`path:${ID.pathA}`);
    expect(v.back).toEqual({ label: 'Ruta A', sel: `path:${ID.pathA}` });
  });

  it('trigger: vecinos Anterior/Siguiente con distancia; en los extremos falta uno; nunca nombre ni descripción de la fila', () => {
    expect(v.neighbors.prev).toEqual({ label: 'Anterior · trigger 007', sub: 'a 10 m', sel: `trigger:${ID.trA(6)}` });
    expect(v.neighbors.next).toEqual({ label: 'Siguiente · trigger 009', sub: 'a 10 m', sel: `trigger:${ID.trA(8)}` });
    expect(buildView(model, `trigger:${ID.trA(0)}`).neighbors.prev).toBeNull();
    expect(buildView(model, `trigger:${ID.trA(31)}`).neighbors.next).toBeNull();
    // el hueco de 40 m se refleja en la distancia al vecino
    expect(buildView(model, `trigger:${ID.trA(15)}`).neighbors.next.sub).toBe('a 40 m');

    const rs = makeRows().map((r) =>
      r.payload.uuid === ID.trA(7) ? { ...r, payload: { ...r.payload, name: 'NOMBRE-DE-FILA', description: 'DESC-DE-FILA' } } : r);
    const dump = JSON.stringify(buildView(build(rs), t7));
    expect(dump).not.toContain('NOMBRE-DE-FILA');
    expect(dump).not.toContain('DESC-DE-FILA');
  });

  it('trigger: pageObras antepone Obras y omite el recorrido', () => {
    expect(buildView(model, t7, 'pageObras').crumbs.map((c) => c.label)).toEqual(['Obras', 'Obra Aurora', 'Ruta A', 'Trigger 008']);
  });

  it('trigger: un path con un solo trigger no tiene vecinos', () => {
    const rs = makeRows().filter((r) => !(r.table === 'triggers' && r.payload.path_uuid === ID.pathB && r.payload.uuid !== ID.trB(0)));
    expect(buildView(build(rs), `trigger:${ID.trB(0)}`).neighbors).toBeNull();
  });
});
