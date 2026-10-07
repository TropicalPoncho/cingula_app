// Capas del mapa (UI-SPEC "Capas y reglas de dibujo"). Leaflet entra por parámetro (`L`): este módulo
// no lo importa, así el spec lo ejerce sin montar un mapa. Nunca se arma HTML con datos del servidor.
import { runs, corridorPx } from '../data/geometry.js';
import { meters } from '../app/format.js';

// Tokens del DS como literales: Leaflet los escribe en atributos SVG, donde var() no es fiable.
const C = { text: '#f4f1f7', mint: '#8ae2c8', azure: '#578ccb', azureSoft: '#a8c6e7', ambar: '#ffbc00', grey: '#9c96ab' };

// Modo Círculos (R6, D-17). Valores medidos con datos reales en 12-03 (OI-02, UI-SPEC "Escalado de Círculos"):
// mediana de radio 12 m -> 12 m / (0,563 m/px a z16 en el ecuador) = 6,8 px >= 6 px (z15 daría 3,4 px), por eso z16;
// p95 de triggers por obra = 26 y máx 35, así que 600 nunca actúa con datos reales: es sólo defensa (T-12-29).
export const CIRCLES_MIN_ZOOM = 16;
export const CIRCLES_MAX = 600;

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
  trigger: {
    normal: { color: C.azure, weight: 1, opacity: 1, fillColor: C.azure, fillOpacity: 0.1 },
    highlighted: { color: C.azure, weight: 1, opacity: 1, fillColor: C.azure, fillOpacity: 0.2 },
    selected: { color: C.text, weight: 2.5, opacity: 1, fillColor: C.azure, fillOpacity: 0.5 },
  },
};
STYLES.corridor.selected = STYLES.corridor.highlighted;
STYLES.line.selected = hi;

// state: 'normal' | 'related' | 'selected' | 'highlighted'; lo que una capa no distingue cae en `normal`.
export const styleFor = (kind, state) => STYLES[kind][state] ?? STYLES[kind].normal;

// Foco y Enter/Espacio sobre capas vectoriales (R9, Pitfall 8): Leaflet 1.9 no convierte Enter en click.
// `setAttribute` y nada de HTML: el label lleva nombres del servidor. El tabindex sale de `options.cgTab`
// (0 por defecto; los triggers lo mueven con roving tabindex) para que sobreviva a recrear el nodo.
function makeInteractive(layer, { label, onSelect }) {
  const apply = () => {
    const el = layer.getElement?.();
    if (!el) return;
    el.setAttribute('tabindex', String(layer.options.cgTab ?? 0));
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
// `mini` (mini-mapa de la página Obras): mismas capas pero ninguna interactiva ni focuseable.
export function buildLayers(L, model, { obras, onSelect, zoom = 16, mini = false }) {
  const groups = Object.fromEntries(['cover', 'labels', 'corridor', 'lines', 'gaps', 'circles', 'portals'].map((g) => [g, L.layerGroup()]));
  const index = new Map();
  const routes = []; // paths dibujables: syncCircles los recorre
  const circles = { group: groups.circles, byUuid: new Map(), onSelect, pendingFocus: null };
  const reg = (sel, layer) => (index.has(sel) ? index.get(sel).push(layer) : index.set(sel, [layer]));
  const pick = (sel) => () => onSelect(sel);
  const wire = mini ? () => {} : makeInteractive;

  for (const o of obras) {
    if (!o.cover) continue; // sin cobertura no se dibuja nada de la obra (R2)
    const osel = `obra:${o.uuid}`;
    const rect = L.rectangle([[o.cover.minLat, o.cover.minLon], [o.cover.maxLat, o.cover.maxLon]], {
      pane: 'cover', className: 'cg-cover', cgKind: 'cover', interactive: !mini, ...styleFor('cover', 'normal'),
    });
    wire(rect, { label: `Obra ${o.name}`, onSelect: pick(osel) });
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
      routes.push(p);
      if (ts.length === 1) { // un solo trigger: sólo el círculo
        const c = L.circle(ll(ts[0]), {
          radius: ts[0].radius_meters, pane: 'line', cgKind: 'line', fillColor: C.azure, fillOpacity: 0.1, interactive: !mini, ...styleFor('line', 'normal'),
        });
        wire(c, { label, onSelect: pick(psel) });
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
      if (!mini) {
        // Área de clic de 16 px: la línea visible no es interactiva.
        const hit = L.polyline(pts, { pane: 'line', weight: 16, opacity: 0 });
        makeInteractive(hit, { label, onSelect: pick(psel) });
        groups.lines.addLayer(hit);
      }
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
      groups.portals.addLayer(circle).addLayer(dot);
      if (!mini) {
        const hit = L.marker(ll(t), { icon: L.divIcon({ html: '', className: 'portal-hit', iconSize: [44, 44] }), keyboard: true });
        makeInteractive(hit, { label: `Portal ${p.name}, radio ${meters(t.radius_meters)}`, onSelect: pick(sel) });
        groups.portals.addLayer(hit);
      }
      reg(sel, circle);
      reg(sel, dot);
    }
  }

  const rescale = (z) => groups.corridor.eachLayer((l) => l.setStyle({ weight: corridorPx(l.options.cgRadius, l.options.cgLat, z) }));
  return { groups, index, rescale, circles, paths: routes };
}

const ARROWS = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 };

// Círculos de trigger (modo Círculos): diff por uuid contra los bounds del mapa ampliados 20 %. Nunca quita el
// trigger seleccionado ni el enfocado (Pitfall 7: el foco sobrevive); sólo setStyle/tabindex sobre los que quedan.
// Sobre `max` se dibujan sólo los del path resaltado/seleccionado. Un tab stop por path (roving, R9).
// ponytail: si el path activo solo ya supera `max`, se dibuja entero; con datos reales (máx 35) no ocurre.
export function syncCircles(state, { L, paths, bounds, sel, focusedUuid, max = CIRCLES_MAX }) {
  const { byUuid, group } = state;
  focusedUuid ??= [...byUuid].find(([, c]) => c.getElement?.() && c.getElement() === document.activeElement)?.[0];
  const byId = new Map(paths.flatMap((p) => p.triggers).map((t) => [t.uuid, t]));
  const [type, id] = sel?.split(/:(.*)/s) ?? [];
  const selTrig = type === 'trigger' && byId.has(id) ? id : null;
  const activePath = type === 'path' ? id : selTrig ? byId.get(selTrig).path.uuid : null;

  const box = bounds.pad(0.2);
  let want = [...byId.values()].filter((t) => box.contains([t.latitude, t.longitude]));
  if (want.length > max) want = want.filter((t) => t.path.uuid === activePath);
  const keep = new Set(want.map((t) => t.uuid));
  for (const u of [selTrig, focusedUuid]) if (byId.has(u)) keep.add(u);

  const removed = [];
  const added = [];
  for (const [u, c] of byUuid) {
    if (keep.has(u)) continue;
    group.removeLayer(c);
    byUuid.delete(u);
    removed.push(u);
  }
  for (const u of keep) {
    if (byUuid.has(u)) continue;
    const t = byId.get(u);
    const c = L.circle([t.latitude, t.longitude], { radius: t.radius_meters, pane: 'circles', cgKind: 'trigger', cgPath: t.path.uuid, cgTab: -1 });
    const pick = () => state.onSelect(`trigger:${u}`);
    makeInteractive(c, { label: `Trigger ${t.index + 1} de ${t.path.triggers.length}, radio ${meters(t.radius_meters)}`, onSelect: pick });
    c.on('keydown', (e) => {
      const step = ARROWS[e.originalEvent.key];
      if (!step) return;
      e.originalEvent.preventDefault(); // sin esto la flecha scrollea la página
      const next = t.path.triggers[t.index + step];
      if (!next) return; // extremos: nada
      state.pendingFocus = next.uuid; // el nodo del siguiente puede no existir todavía: se enfoca al terminar el próximo sync
      state.onSelect(`trigger:${next.uuid}`);
    });
    group.addLayer(c);
    byUuid.set(u, c);
    added.push(u);
  }

  // Roving tabindex: por path, el seleccionado o, si no, el de menor `index`.
  const stop = new Map();
  for (const u of byUuid.keys()) {
    const t = byId.get(u);
    const best = stop.get(t.path.uuid);
    if (!best || u === selTrig || (best !== selTrig && t.index < byId.get(best).index)) stop.set(t.path.uuid, u);
  }
  for (const [u, c] of byUuid) {
    const t = byId.get(u);
    c.options.cgTab = stop.get(t.path.uuid) === u ? 0 : -1;
    c.getElement?.()?.setAttribute('tabindex', String(c.options.cgTab));
    c.setStyle(styleFor('trigger', u === selTrig ? 'selected' : t.path.uuid === activePath ? 'highlighted' : 'normal'));
  }

  if (state.pendingFocus) {
    byUuid.get(state.pendingFocus)?.getElement?.()?.focus();
    state.pendingFocus = null;
  }
  return { added, removed };
}

export function clearCircles(state) {
  state.group.clearLayers();
  state.byUuid.clear();
  state.pendingFocus = null;
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
const CAPA_OF = { cover: 'cobertura', labels: 'cobertura', corridor: 'paths', lines: 'paths', gaps: 'paths', circles: 'paths', portals: 'portales' };

// `circulos` = modo Círculos con zoom suficiente: el corredor se oculta y entran los círculos (línea, huecos y portales siguen).
export function syncGroups(map, groups, capas, circulos = false) {
  for (const [name, g] of Object.entries(groups)) {
    const on = capas[CAPA_OF[name]] && (name === 'corridor' ? !circulos : name === 'circles' ? circulos : true);
    if (on) map.addLayer(g);
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
