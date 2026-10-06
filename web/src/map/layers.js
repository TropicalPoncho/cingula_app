// Capas del mapa (UI-SPEC "Capas y reglas de dibujo"). Leaflet entra por parámetro (`L`): este módulo
// no lo importa, así el spec lo ejerce sin montar un mapa. Nunca se arma HTML con datos del servidor.
import { runs, corridorPx } from '../data/geometry.js';
import { meters } from '../app/format.js';

// Tokens del DS como literales: Leaflet los escribe en atributos SVG, donde var() no es fiable.
const C = { text: '#f4f1f7', mint: '#8ae2c8', azure: '#578ccb', azureSoft: '#a8c6e7', ambar: '#ffbc00', grey: '#9c96ab' };

// zIndex de las panes propias (de abajo hacia arriba). markerPane (600) queda para etiquetas y objetivos.
export const PANES = { cover: 410, corridor: 420, line: 430, gap: 440, circles: 450, portals: 460 };

const hi = { color: C.azureSoft, weight: 3, opacity: 1 };
const STYLES = {
  cover: {
    normal: { color: C.grey, opacity: 0.75, weight: 1.25, dashArray: '6 5', fillColor: C.text, fillOpacity: 0.04 },
    related: { color: C.mint, opacity: 1, weight: 1.75, dashArray: '', fillColor: C.mint, fillOpacity: 0.08 },
    selected: { color: C.text, opacity: 1, weight: 2.5, dashArray: '', fillColor: C.mint, fillOpacity: 0.14 },
  },
  // El ancho del corredor lo manda `rescale` (metros -> px por zoom): acá sólo color.
  corridor: {
    normal: { color: 'rgba(87,140,203,.28)', opacity: 1 },
    highlighted: { color: 'rgba(168,198,231,.42)', opacity: 1 },
  },
  line: { normal: { color: C.azure, weight: 1.5, opacity: 1 }, highlighted: hi },
  portal: {
    normal: { color: C.mint, weight: 2.5, opacity: 1, fillColor: C.mint, fillOpacity: 0.16 },
    selected: { color: C.text, weight: 3.5, opacity: 1, fillColor: C.mint, fillOpacity: 0.35 },
  },
  dot: { normal: { radius: 3.5 }, selected: { radius: 5 } },
};
STYLES.corridor.selected = STYLES.corridor.highlighted;
STYLES.line.selected = hi;

// state: 'normal' | 'related' | 'selected' | 'highlighted'; lo que una capa no distingue cae en `normal`.
export const styleFor = (kind, state) => STYLES[kind][state] ?? STYLES[kind].normal;

// Foco y Enter/Espacio sobre capas vectoriales (R9, Pitfall 8): Leaflet 1.9 no convierte Enter en click.
// `setAttribute` y nada de HTML: el label lleva nombres del servidor.
function makeInteractive(layer, { label, onSelect }) {
  const apply = () => {
    const el = layer.getElement?.();
    if (!el) return;
    el.setAttribute('tabindex', '0');
    el.setAttribute('role', 'button');
    el.setAttribute('aria-label', label);
  };
  layer.on('add', apply); // al apagar/prender la capa el nodo se recrea
  layer.on('click', onSelect);
  layer.on('keydown', (e) => {
    const k = e.originalEvent.key;
    if (k === 'Enter' || k === ' ') {
      e.originalEvent.preventDefault();
      onSelect();
    }
  });
  apply();
}

const ll = (t) => [t.latitude, t.longitude];

// Devuelve los grupos por capa, un índice sel -> capas con estilo propio (para applySelection) y `rescale`
// (ancho del corredor en px según el zoom; MapView lo llama en zoomend). `zoom` sólo siembra el ancho inicial.
export function buildLayers(L, model, { obras, onSelect, zoom = 16 }) {
  const groups = Object.fromEntries(['cover', 'labels', 'corridor', 'lines', 'gaps', 'portals'].map((g) => [g, L.layerGroup()]));
  const index = new Map();
  const reg = (sel, layer) => (index.has(sel) ? index.get(sel).push(layer) : index.set(sel, [layer]));
  const pick = (sel) => () => onSelect(sel);

  for (const o of obras) {
    if (!o.cover) continue; // sin cobertura no se dibuja nada de la obra (R2)
    const osel = `obra:${o.uuid}`;
    const rect = L.rectangle([[o.cover.minLat, o.cover.minLon], [o.cover.maxLat, o.cover.maxLon]], {
      pane: 'cover', className: 'cg-cover', cgKind: 'cover', ...styleFor('cover', 'normal'),
    });
    makeInteractive(rect, { label: `Obra ${o.name}`, onSelect: pick(osel) });
    groups.cover.addLayer(rect);
    reg(osel, rect);

    // Etiqueta: nodo DOM con textContent, nunca HTML (T-12-25).
    const span = document.createElement('span');
    span.textContent = o.name;
    groups.labels.addLayer(L.marker([o.cover.lat, o.cover.lon], {
      icon: L.divIcon({ html: span, className: 'obra-label', iconSize: null }), interactive: false, keyboard: false,
    }));

    for (const p of o.routes) {
      const ts = p.triggers;
      if (!ts.length) continue; // "0 triggers": se lista en el panel, no se dibuja
      const psel = `path:${p.uuid}`;
      const label = `Path ${p.name}`;
      if (ts.length === 1) { // un solo trigger: sólo el círculo
        const c = L.circle(ll(ts[0]), {
          radius: ts[0].radius_meters, pane: 'line', cgKind: 'line', fillColor: C.azure, fillOpacity: 0.1, ...styleFor('line', 'normal'),
        });
        makeInteractive(c, { label, onSelect: pick(psel) });
        groups.lines.addLayer(c);
        reg(psel, c);
        continue;
      }
      // Corredor (D-17): un polilínea por tramo continuo; ancho = diámetro en metros (mediana de radios).
      for (const run of runs(ts, p.gaps)) {
        const pts = run.map(ll);
        const c = L.polyline(pts.length === 1 ? [pts[0], pts[0]] : pts, {
          pane: 'corridor', interactive: false, lineCap: 'round', lineJoin: 'round', cgKind: 'corridor',
          cgRadius: p.medianRadius, cgLat: run[0].latitude, weight: corridorPx(p.medianRadius, run[0].latitude, zoom),
          ...styleFor('corridor', 'normal'),
        });
        groups.corridor.addLayer(c);
        reg(psel, c);
      }
      const pts = ts.map(ll);
      const line = L.polyline(pts, { pane: 'line', interactive: false, cgKind: 'line', ...styleFor('line', 'normal') });
      groups.lines.addLayer(line);
      reg(psel, line);
      // Área de clic de 16 px: la línea visible no es interactiva.
      const hit = L.polyline(pts, { pane: 'line', weight: 16, opacity: 0 });
      makeInteractive(hit, { label, onSelect: pick(psel) });
      groups.lines.addLayer(hit);
      for (const g of p.gaps) {
        groups.gaps.addLayer(L.polyline([pts[g.from], pts[g.to]], { pane: 'gap', interactive: false, color: C.ambar, weight: 2.5, dashArray: '4 4' }));
      }
    }

    for (const p of o.portals) {
      const t = p.trigger;
      if (!t) continue; // portal sin trigger: ni se dibuja ni cuenta
      const sel = `portal:${p.uuid}`;
      const circle = L.circle(ll(t), { radius: t.radius_meters, pane: 'portals', interactive: false, cgKind: 'portal', ...styleFor('portal', 'normal') });
      const dot = L.circleMarker(ll(t), { pane: 'portals', interactive: false, cgKind: 'dot', stroke: false, fillColor: C.mint, fillOpacity: 1, ...styleFor('dot', 'normal') });
      const hit = L.marker(ll(t), { icon: L.divIcon({ html: '', className: 'portal-hit', iconSize: [44, 44] }), keyboard: true });
      makeInteractive(hit, { label: `Portal ${p.name}, radio ${meters(t.radius_meters)}`, onSelect: pick(sel) });
      groups.portals.addLayer(circle).addLayer(dot).addLayer(hit);
      reg(sel, circle);
      reg(sel, dot);
    }
  }

  const rescale = (z) => groups.corridor.eachLayer((l) => l.setStyle({ weight: corridorPx(l.options.cgRadius, l.options.cgLat, z) }));
  return { groups, index, rescale };
}

// Estilos por estado de selección sin reconstruir capas (Pitfall 7: el foco no se pierde).
// seleccionado = el sel; resaltado = path del trigger elegido; relacionado = obra del elemento elegido
// (o las obras del recorrido elegido).
export function applySelection(index, sel, model) {
  const i = sel?.indexOf(':') ?? -1;
  const type = i < 0 ? null : sel.slice(0, i);
  const id = i < 0 ? null : sel.slice(i + 1);
  const related = new Set();
  const highlighted = new Set();
  const relate = (o) => o && related.add(`obra:${o.uuid}`);
  if (type === 'recorrido') model.byId.recorrido.get(id)?.obras.forEach(relate);
  else if (type === 'path' || type === 'portal') relate(model.byId.path.get(id)?.obra);
  else if (type === 'trigger') {
    const p = model.byId.trigger.get(id)?.path;
    if (p) {
      highlighted.add(`path:${p.uuid}`);
      relate(p.obra);
    }
  }
  for (const [key, layers] of index) {
    const state = key === sel ? 'selected' : highlighted.has(key) ? 'highlighted' : related.has(key) ? 'related' : 'normal';
    for (const l of layers) l.setStyle(styleFor(l.options.cgKind, state));
  }
}

// Cada grupo pertenece a una casilla de capas; apagar una quita el grupo del mapa sin tocar el índice.
const CAPA_OF = { cover: 'cobertura', labels: 'cobertura', corridor: 'paths', lines: 'paths', gaps: 'paths', portals: 'portales' };

export function syncGroups(map, groups, capas) {
  for (const [name, g] of Object.entries(groups)) {
    if (capas[CAPA_OF[name]]) map.addLayer(g);
    else map.removeLayer(g);
  }
}

// Unión de las coberturas, ampliada por el mayor radio de trigger de cada obra (H4: el círculo sobresale del bbox).
export function coverBounds(L, obras) {
  let b = null;
  for (const o of obras) {
    if (!o.cover) continue;
    const dLat = o.maxRadius / 111320;
    const dLon = o.maxRadius / (111320 * Math.cos((o.cover.lat * Math.PI) / 180));
    const ob = L.latLngBounds([o.cover.minLat - dLat, o.cover.minLon - dLon], [o.cover.maxLat + dLat, o.cover.maxLon + dLon]);
    b = b ? b.extend(ob) : ob;
  }
  return b;
}

// Encuadre de un elemento elegido desde el panel (no desde el mapa): obra/recorrido por cobertura,
// path/portal/trigger por sus triggers. null = nada que encuadrar.
export function targetBounds(L, model, sel) {
  const i = sel?.indexOf(':') ?? -1;
  if (i < 0) return null;
  const type = sel.slice(0, i);
  const id = sel.slice(i + 1);
  if (type === 'obra') return coverBounds(L, [model.byId.obra.get(id)].filter(Boolean));
  if (type === 'recorrido') return coverBounds(L, model.byId.recorrido.get(id)?.obras ?? []);
  const ts = type === 'trigger' ? [model.byId.trigger.get(id)] : type === 'path' || type === 'portal' ? (model.byId.path.get(id)?.triggers ?? []) : [];
  const pts = ts.filter(Boolean).map((t) => [t.latitude, t.longitude]);
  return pts.length ? L.latLngBounds(pts) : null;
}
