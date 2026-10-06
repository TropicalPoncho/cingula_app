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
