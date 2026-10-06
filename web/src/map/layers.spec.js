import { describe, it, expect } from 'vitest';
import L from 'leaflet';
import { emptyTables, applyRows, buildModel } from '../data/model.js';
import { corridorPx } from '../data/geometry.js';
import { makeRows, ID, HTML_NAME } from '../test/fixtures.js';
import { buildLayers, styleFor, applySelection, coverBounds, targetBounds } from './layers.js';

// Modelo de las fixtures; `tweak` edita las filas antes de armarlo (p. ej. darle cobertura a la obra C).
function modelOf(tweak) {
  const rows = makeRows();
  tweak?.(rows);
  return buildModel(applyRows(emptyTables(), rows).tables);
}
const withCoverOnC = (rows) => {
  const a = rows.find((r) => r.payload.uuid === ID.obA).payload;
  const c = rows.find((r) => r.payload.uuid === ID.obC).payload;
  for (const k of Object.keys(a)) if (k.startsWith('cover_')) c[k] = a[k];
};
const noop = () => {};
const build = (model, obras, extra = {}) => buildLayers(L, model, { obras, onSelect: noop, ...extra });
const layersOf = (b, g) => b.groups[g].getLayers();
const obra = (m, id) => m.byId.obra.get(id);
const size = (index) => [...index.values()].reduce((n, ls) => n + ls.length, 0);

describe('etiquetas de obra (T-12-25)', () => {
  it('una por obra con cobertura, con el nombre como textContent', () => {
    const m = modelOf();
    const b = build(m, m.obras);
    expect(layersOf(b, 'labels')).toHaveLength(2); // A y B; C sin cobertura; D borrada
    const names = layersOf(b, 'labels').map((l) => l.options.icon.createIcon().textContent).sort();
    expect(names).toEqual(['Obra Aurora', m.obras.find((o) => o.uuid === ID.obB).name].sort());
  });

  it('un nombre con HTML se ve como texto y no crea ningún img', () => {
    const m = modelOf(withCoverOnC);
    const b = build(m, [obra(m, ID.obC)]);
    const icon = layersOf(b, 'labels')[0].options.icon.createIcon();
    expect(icon.textContent).toBe(HTML_NAME);
    expect(icon.querySelector('img')).toBeNull();
    expect(icon.children).toHaveLength(1); // sólo el span
  });
});

describe('path de 32 triggers con 1 hueco', () => {
  const m = modelOf();
  const b = build(m, [obra(m, ID.obA)], { zoom: 16 });

  it('2 polilíneas de corredor (una por tramo), 1 hueco', () => {
    expect(layersOf(b, 'corridor')).toHaveLength(2);
    expect(layersOf(b, 'gaps')).toHaveLength(1);
    const gap = layersOf(b, 'gaps')[0];
    expect(gap.options.dashArray).toBe('4 4');
    expect(gap.options.interactive).toBe(false);
  });

  it('1 línea visible (no interactiva, 1,5 px) + 1 línea de clic transparente de 16 px', () => {
    const lines = layersOf(b, 'lines');
    expect(lines).toHaveLength(2);
    const vis = lines.find((l) => l.options.weight === 1.5);
    const hit = lines.find((l) => l.options.weight === 16);
    expect(vis.options.interactive).toBe(false);
    expect(hit.options.opacity).toBe(0);
    expect(hit.options.interactive).not.toBe(false);
    expect(hit.getLatLngs()).toHaveLength(32);
  });

  it('ancho del corredor = corridorPx(mediana, lat, zoom), y rescale lo recalcula', () => {
    const [first] = layersOf(b, 'corridor');
    expect(first.options.weight).toBeCloseTo(corridorPx(12, first.options.cgLat, 16), 6);
    b.rescale(18);
    for (const c of layersOf(b, 'corridor')) expect(c.options.weight).toBeCloseTo(corridorPx(12, c.options.cgLat, 18), 6);
    expect(layersOf(b, 'corridor')[0].options.weight).toBeGreaterThan(corridorPx(12, first.options.cgLat, 16));
  });
});

describe('datos feos', () => {
  it('path con 0 triggers: no produce capas', () => {
    const m = modelOf(withCoverOnC); // la ruta C no tiene triggers
    const b = build(m, [obra(m, ID.obC)]);
    for (const g of ['corridor', 'lines', 'gaps', 'portals']) expect(layersOf(b, g)).toHaveLength(0);
    expect(b.index.has(`path:${ID.pathC}`)).toBe(false);
  });

  it('path con 1 trigger: sólo el círculo en metros', () => {
    const m = modelOf();
    const p = m.byId.path.get(ID.pathB);
    p.triggers = p.triggers.slice(0, 1);
    p.gaps = [];
    const b = build(m, [obra(m, ID.obB)]);
    expect(layersOf(b, 'corridor')).toHaveLength(0);
    expect(layersOf(b, 'gaps')).toHaveLength(0);
    const [c] = layersOf(b, 'lines');
    expect(layersOf(b, 'lines')).toHaveLength(1);
    expect(c).toBeInstanceOf(L.Circle);
    expect(c.getRadius()).toBe(12);
  });

  it('portal sin trigger: no se dibuja', () => {
    const m = modelOf();
    m.byId.path.get(ID.portalA).trigger = null;
    const b = build(m, [obra(m, ID.obA)]);
    expect(layersOf(b, 'portals')).toHaveLength(0);
  });
});

describe('portal', () => {
  it('1 círculo en metros no interactivo + 1 marcador divIcon de 44 px', () => {
    const m = modelOf();
    const b = build(m, [obra(m, ID.obA)]);
    const ls = layersOf(b, 'portals');
    const circles = ls.filter((l) => l instanceof L.Circle);
    const markers = ls.filter((l) => l instanceof L.Marker);
    expect(circles).toHaveLength(1);
    expect(circles[0].getRadius()).toBe(15);
    expect(circles[0].options.interactive).toBe(false);
    expect(markers).toHaveLength(1);
    expect(markers[0].options.icon.options.iconSize).toEqual([44, 44]);
    expect(markers[0].options.keyboard).toBe(true);
  });
});

describe('styleFor', () => {
  it('valores de la UI-SPEC por estado', () => {
    expect(styleFor('cover', 'normal')).toMatchObject({ weight: 1.25, dashArray: '6 5', fillOpacity: 0.04 });
    expect(styleFor('cover', 'related')).toMatchObject({ weight: 1.75, fillOpacity: 0.08 });
    expect(styleFor('cover', 'selected')).toMatchObject({ weight: 2.5, fillOpacity: 0.14 });
    expect(styleFor('line', 'normal')).toMatchObject({ weight: 1.5 });
    expect(styleFor('line', 'highlighted')).toMatchObject({ weight: 3, color: '#a8c6e7' });
    expect(styleFor('corridor', 'normal').color).toBe('rgba(87,140,203,.28)');
    expect(styleFor('corridor', 'highlighted').color).toBe('rgba(168,198,231,.42)');
    expect(styleFor('corridor', 'normal')).not.toHaveProperty('weight'); // lo manda rescale
    expect(styleFor('portal', 'normal')).toMatchObject({ weight: 2.5, fillOpacity: 0.16 });
    expect(styleFor('portal', 'selected')).toMatchObject({ weight: 3.5, fillOpacity: 0.35 });
    expect(styleFor('dot', 'selected').radius).toBe(5);
  });
});

describe('applySelection', () => {
  const m = modelOf();
  const b = build(m, m.obras);
  const rectOf = (id) => b.index.get(`obra:${id}`)[0];
  const lineOf = (id) => b.index.get(`path:${id}`).find((l) => l.options.cgKind === 'line');

  it('cambia estilos sin crear ni quitar capas', () => {
    const before = size(b.index);
    const total = Object.values(b.groups).reduce((n, g) => n + g.getLayers().length, 0);
    applySelection(b.index, `obra:${ID.obA}`, m);
    expect(rectOf(ID.obA).options.weight).toBe(2.5);
    expect(rectOf(ID.obB).options.weight).toBe(1.25);
    applySelection(b.index, `trigger:${ID.trA(3)}`, m);
    expect(size(b.index)).toBe(before);
    expect(Object.values(b.groups).reduce((n, g) => n + g.getLayers().length, 0)).toBe(total);
  });

  it('trigger elegido: su path se resalta y su obra queda relacionada', () => {
    applySelection(b.index, `trigger:${ID.trA(3)}`, m);
    expect(lineOf(ID.pathA).options.weight).toBe(3);
    expect(lineOf(ID.pathB).options.weight).toBe(1.5);
    expect(rectOf(ID.obA).options.weight).toBe(1.75);
    expect(rectOf(ID.obB).options.weight).toBe(1.25);
  });

  it('recorrido elegido: relaciona sus obras; portal elegido: trazo 3,5 y punto 5 px', () => {
    applySelection(b.index, `recorrido:${ID.rec1}`, m);
    expect(rectOf(ID.obA).options.weight).toBe(1.75);
    expect(rectOf(ID.obB).options.weight).toBe(1.75);
    applySelection(b.index, `portal:${ID.portalA}`, m);
    const [circle, dot] = b.index.get(`portal:${ID.portalA}`);
    expect(circle.options.weight).toBe(3.5);
    expect(dot.getRadius()).toBe(5);
    applySelection(b.index, null, m);
    expect(circle.options.weight).toBe(2.5);
    expect(dot.getRadius()).toBe(3.5);
    expect(rectOf(ID.obA).options.weight).toBe(1.25);
  });
});

describe('encuadre', () => {
  const m = modelOf();
  it('la unión de coberturas se amplía por el mayor radio de los triggers (H4)', () => {
    const o = obra(m, ID.obA);
    const b = coverBounds(L, [o]);
    expect(b.getSouth()).toBeLessThan(o.cover.minLat);
    expect(b.getEast()).toBeGreaterThan(o.cover.maxLon);
  });
  it('sin coberturas no hay bounds; un sel inexistente tampoco', () => {
    expect(coverBounds(L, [obra(m, ID.obC)])).toBeNull();
    expect(targetBounds(L, m, 'obra:no-existe')).toBeNull();
    expect(targetBounds(L, m, null)).toBeNull();
    expect(targetBounds(L, m, `path:${ID.pathA}`).isValid()).toBe(true);
  });
});
