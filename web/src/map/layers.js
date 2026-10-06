// Capas del mapa (UI-SPEC "Capas y reglas de dibujo"). Leaflet entra por parámetro (`L`): este módulo
// no lo importa, así el spec lo ejerce sin montar un mapa. Nunca se arma HTML con datos del servidor.

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

// Devuelve los grupos por capa y un índice sel -> capas con estilo propio (para applySelection).
export function buildLayers(L, model, { obras, onSelect }) {
  const groups = Object.fromEntries(['cover', 'labels'].map((g) => [g, L.layerGroup()]));
  const index = new Map();
  const reg = (sel, layer) => (index.has(sel) ? index.get(sel).push(layer) : index.set(sel, [layer]));

  for (const o of obras) {
    if (!o.cover) continue; // sin cobertura no se dibuja (R2)
    const sel = `obra:${o.uuid}`;
    const rect = L.rectangle([[o.cover.minLat, o.cover.minLon], [o.cover.maxLat, o.cover.maxLon]], {
      pane: 'cover', className: 'cg-cover', cgKind: 'cover', ...styleFor('cover', 'normal'),
    });
    makeInteractive(rect, { label: `Obra ${o.name}`, onSelect: () => onSelect(sel) });
    groups.cover.addLayer(rect);
    reg(sel, rect);
  }
  return { groups, index };
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
