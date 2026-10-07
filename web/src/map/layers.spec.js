import { describe, it, expect, vi } from 'vitest';
import L from 'leaflet';
import { emptyTables, applyRows, buildModel } from '../data/model.js';
import { corridorPx } from '../data/geometry.js';
import { makeRows, ID, HTML_NAME } from '../test/fixtures.js';
import {
  buildLayers, styleFor, applySelection, coverBounds, targetBounds, syncCircles, clearCircles, CIRCLES_MIN_ZOOM, CIRCLES_MAX,
} from './layers.js';

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

describe('modo Círculos (R6, R9)', () => {
  const m = modelOf();
  const trig = (i) => m.byId.trigger.get(ID.trA(i));
  // Bounds con altura (los triggers de A están sobre una misma latitud) que cubren los triggers 0..15.
  const half = L.latLngBounds([trig(0).latitude - 0.001, trig(0).longitude], [trig(0).latitude + 0.001, trig(15).longitude]);
  const everything = L.latLngBounds([-43, -72], [-41, -71]);
  const fresh = (onSelect = noop, obras = m.obras) => {
    const b = buildLayers(L, m, { obras, onSelect });
    const sync = (o) => syncCircles(b.circles, { L, paths: b.paths, bounds: everything, ...o });
    return { b, sync, byUuid: b.circles.byUuid };
  };

  it('valores medidos en 12-03', () => {
    expect(CIRCLES_MIN_ZOOM).toBe(16);
    expect(CIRCLES_MAX).toBe(600);
  });

  it('con bounds sobre la mitad del path agrega sólo los de adentro (ampliados 20 %) y círculos en metros', () => {
    const { b, sync, byUuid } = fresh(noop, [obra(m, ID.obA)]);
    const { added } = sync({ bounds: half, sel: null });
    const padded = half.pad(0.2);
    expect(added).toContain(ID.trA(0));
    expect(added).not.toContain(ID.trA(31));
    expect(added.length).toBeGreaterThan(10);
    expect(added.length).toBeLessThan(32);
    for (const u of added) expect(padded.contains([m.byId.trigger.get(u).latitude, m.byId.trigger.get(u).longitude])).toBe(true);
    expect(byUuid.get(ID.trA(0)).getRadius()).toBe(12);
    expect(b.circles.group.getLayers()).toHaveLength(added.length);
  });

  it('nunca quita el seleccionado ni el enfocado aunque salgan de los bounds', () => {
    const { sync, byUuid } = fresh(noop, [obra(m, ID.obA)]);
    sync({ sel: null }); // los 32
    expect(byUuid.size).toBe(32);
    const { removed } = sync({ bounds: half, sel: `trigger:${ID.trA(31)}`, focusedUuid: ID.trA(30) });
    expect(removed).not.toContain(ID.trA(31));
    expect(removed).not.toContain(ID.trA(30));
    expect(removed).toContain(ID.trA(29));
    expect(byUuid.has(ID.trA(31))).toBe(true);
    expect(byUuid.has(ID.trA(30))).toBe(true);
    expect(byUuid.get(ID.trA(31)).options.weight).toBe(2.5); // sólo setStyle: la selección no reconstruye
    expect(byUuid.get(ID.trA(31)).getRadius()).toBe(12);
  });

  it('más visibles que el tope: sólo los del path resaltado o seleccionado (T-12-29)', () => {
    const { sync, byUuid } = fresh();
    sync({ max: 10, sel: `path:${ID.pathB}` });
    expect([...byUuid.keys()].sort()).toEqual([ID.trB(0), ID.trB(1), ID.trB(2)]);
    sync({ max: 10, sel: `trigger:${ID.trA(3)}` });
    expect(byUuid.size).toBe(32);
    expect([...byUuid.keys()].every((u) => u.startsWith('trg-A-'))).toBe(true);
    sync({ max: 10, sel: null }); // nada resaltado: ninguno
    expect(byUuid.size).toBe(0);
  });

  it('roving tabindex: un tab stop por path (el seleccionado o el primero), role=button y aria-label', () => {
    const { sync, byUuid } = fresh();
    sync({ sel: null });
    const tabs = (prefix) => [...byUuid].filter(([u]) => u.startsWith(prefix)).map(([u, c]) => [u, c.options.cgTab]);
    expect(tabs('trg-A-').filter(([, t]) => t === 0)).toEqual([[ID.trA(0), 0]]);
    expect(tabs('trg-B-').filter(([, t]) => t === 0)).toEqual([[ID.trB(0), 0]]);
    sync({ sel: `trigger:${ID.trA(5)}` });
    expect(tabs('trg-A-').filter(([, t]) => t === 0)).toEqual([[ID.trA(5), 0]]);
    expect(tabs('trg-A-').filter(([, t]) => t === -1)).toHaveLength(31);
    expect(tabs('trg-B-').filter(([, t]) => t === 0)).toHaveLength(1);

    const c = byUuid.get(ID.trA(5));
    const el = document.createElement('div'); // jsdom no trae renderer SVG: nodo simulado
    c.getElement = () => el;
    c.fire('add');
    expect(el.getAttribute('role')).toBe('button');
    expect(el.getAttribute('aria-label')).toBe('Trigger 6 de 32, radio 12 m');
    expect(el.getAttribute('tabindex')).toBe('0');
  });

  it('flechas: derecha/abajo = siguiente, izquierda/arriba = anterior; en los extremos nada; Enter selecciona', () => {
    const picks = [];
    const { b, sync, byUuid } = fresh((s) => picks.push(s));
    sync({ sel: null });
    const key = (u, k) => {
      const preventDefault = vi.fn();
      byUuid.get(u).fire('keydown', { originalEvent: { key: k, preventDefault } });
      return preventDefault;
    };
    expect(key(ID.trA(5), 'ArrowRight')).toHaveBeenCalled();
    expect(picks.at(-1)).toBe(`trigger:${ID.trA(6)}`);
    expect(b.circles.pendingFocus).toBe(ID.trA(6));
    key(ID.trA(5), 'ArrowDown');
    expect(picks.at(-1)).toBe(`trigger:${ID.trA(6)}`);
    key(ID.trA(5), 'ArrowLeft');
    expect(picks.at(-1)).toBe(`trigger:${ID.trA(4)}`);
    key(ID.trA(5), 'ArrowUp');
    expect(picks.at(-1)).toBe(`trigger:${ID.trA(4)}`);
    const n = picks.length;
    key(ID.trA(0), 'ArrowLeft');
    key(ID.trA(31), 'ArrowRight');
    key(ID.trA(5), 'a');
    expect(picks).toHaveLength(n);
    key(ID.trA(5), 'Enter');
    expect(picks.at(-1)).toBe(`trigger:${ID.trA(5)}`);
  });

  it('el siguiente sync enfoca el trigger pendiente y lo limpia', () => {
    const { b, sync, byUuid } = fresh();
    sync({ sel: null });
    const focus = vi.fn();
    byUuid.get(ID.trA(6)).getElement = () => ({ setAttribute() {}, focus });
    b.circles.pendingFocus = ID.trA(6);
    sync({ sel: `trigger:${ID.trA(6)}` });
    expect(focus).toHaveBeenCalledTimes(1);
    expect(b.circles.pendingFocus).toBeNull();
  });

  it('fuera de modo/zoom se limpia todo', () => {
    const { b, sync, byUuid } = fresh();
    sync({ sel: null });
    clearCircles(b.circles);
    expect(byUuid.size).toBe(0);
    expect(b.circles.group.getLayers()).toHaveLength(0);
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

describe('modo mini (mini-mapa de Obras)', () => {
  it('mismas capas que el mapa grande pero ninguna interactiva ni con área de clic, y el índice de selección se conserva', () => {
    const m = modelOf();
    const big = build(m, [obra(m, ID.obA)]);
    const mini = build(m, [obra(m, ID.obA)], { mini: true });
    const all = (b) => Object.values(b.groups).flatMap((g) => g.getLayers());
    expect(all(mini).some((l) => l.options.cgKind === 'cover' && l.options.interactive !== false)).toBe(false);
    expect(layersOf(mini, 'portals').filter((l) => l.options.icon?.options.className === 'portal-hit')).toHaveLength(0);
    expect(layersOf(big, 'portals').filter((l) => l.options.icon?.options.className === 'portal-hit')).toHaveLength(1);
    expect(layersOf(mini, 'lines').filter((l) => l.options.weight === 16)).toHaveLength(0); // sin área de clic de 16 px
    expect(size(mini.index)).toBe(size(big.index));
  });
});
