// Objeto de vista puro para los 5 tipos del panel (D-06, D-18). Sin DOM: lo consumen el panel del
// mapa y el detalle de la página Obras (D-08). Lee el modelo de 12-02; no recalcula huecos ni índices.
import { haversineM } from '../data/geometry.js';
import { plural, fms, latlon, mmss, miles } from '../app/format.js';

const TYPES = ['recorrido', 'obra', 'path', 'portal', 'trigger'];
// Forma segura de un id (V5): letras, dígitos, `_`, `.`, `-`. Cubre los uuid reales y las fixtures;
// la existencia en `model.byId` es la compuerta de verdad.
const ID_SHAPE = /^[\w.-]{1,64}$/;

// `sel` = `<tipo>:<uuid>`. null si no hay selección; `{ stale: true }` si no se puede mostrar.
// El texto de la URL nunca llega a la vista: sólo se usa para buscar en el modelo (T-12-21).
export function parseSel(model, sel) {
  if (!sel) return null;
  const i = sel.indexOf(':');
  const type = sel.slice(0, i);
  const uuid = sel.slice(i + 1);
  if (i < 0 || !TYPES.includes(type) || !ID_SHAPE.test(uuid)) return { stale: true };
  const entity = model.byId[type === 'portal' ? 'path' : type].get(uuid);
  const kind = { path: 'route', portal: 'portal' }[type];
  const ok = entity && (type === 'trigger' ? entity.path.kind === 'route' : !kind || entity.kind === kind);
  return ok ? { type, uuid, entity } : { stale: true };
}

const VIS = {
  public: { label: 'Pública', dot: 'var(--c-mint)' },
  draft: { label: 'Borrador', dot: 'var(--c-ambar)' },
  private: { label: 'Privada', dot: 'var(--ink-200)' },
};
// Un valor fuera del CHECK se muestra crudo en mono (OI-04), nunca se oculta.
const visOf = (v) => (Object.hasOwn(VIS, v ?? '') ? VIS[v] : { label: v ?? '—', mono: true, dot: 'var(--ink-200)' });

const NO_COVER = 'Sin cobertura todavía';
const NO_COVER_NOTE = 'La obra no tiene triggers, así que no hay dónde dibujarla.';
const COVER_HINT = 'Extensión entre los centros de los triggers (no incluye el radio).';

const num = (n) => String(+Number(n).toFixed(1));
const m = (n) => `${num(n)} m`;
const pad3 = (n) => String(n).padStart(3, '0');
const off = (ms) => (ms == null ? '—' : fms(ms));
const sel = (type, e) => `${type}:${e.uuid}`;
const link = (label, s) => ({ label, sel: s });
const artistLinks = (as) => as.map((a) => ({ label: a.name, href: `/artistas/${encodeURIComponent(a.uuid)}` }));
const rows = (title, rs) => ({ title, rows: rs });
const present = (ls) => ls.filter((l) => l.rows.length);

const pathRow = (p) => ({
  label: p.name,
  sub: ['route', plural(p.triggers.length, 'trigger', 'triggers'), p.gaps.length && plural(p.gaps.length, 'hueco', 'huecos')]
    .filter(Boolean)
    .join(' · '),
  sel: sel('path', p),
});
const portalRow = (p) => ({
  label: p.name,
  sub: [p.trigger && `radio ${m(p.trigger.radius_meters)}`, p.trigger && off(p.trigger.offset_ms), p.audio?.has_file ? 'con archivo' : 'sin archivo todavía']
    .filter(Boolean)
    .join(' · '),
  sel: sel('portal', p),
});

// Cobertura = caja entre los centros de los triggers (R2/H4), en metros.
function coverage(o) {
  if (!o.cover) return null;
  const { minLat, maxLat, minLon, maxLon } = o.cover;
  const lat = (minLat + maxLat) / 2;
  const w = haversineM({ latitude: lat, longitude: minLon }, { latitude: lat, longitude: maxLon });
  const h = haversineM({ latitude: minLat, longitude: minLon }, { latitude: maxLat, longitude: minLon });
  return `${miles(w)} × ${miles(h)} m`;
}

// Cadena de breadcrumb (D-12): origen mapa antepone el recorrido; origen página Obras antepone `Obras`
// y omite el recorrido. El último segmento es el actual (sel null).
function crumbs(origin, obra, ...rest) {
  const root =
    origin === 'pageObras'
      ? [{ label: 'Obras', sel: null, href: '/obras' }]
      : obra.recorrido ? [link(obra.recorrido.name, sel('recorrido', obra.recorrido))] : [];
  const chain = [...root, link(obra.name, sel('obra', obra)), ...rest];
  return chain.map((c, i) => (i === chain.length - 1 ? { ...c, sel: null } : c));
}

const BASE = { back: null, description: null, audio: null, strip: null, table: null, note: null, neighbors: null };

function obraView(o, origin) {
  const v = visOf(o.visibility);
  const cov = coverage(o);
  return {
    ...BASE,
    type: 'obra',
    typeLabel: 'OBRA',
    title: o.name,
    subtitle: o.recorrido?.name ?? 'Sin recorrido',
    crumbs: crumbs(origin, o),
    facts: [
      { label: 'Visibilidad', value: v.label, mono: v.mono, dot: v.dot },
      o.recorrido
        ? { label: 'Recorrido', links: [link(o.recorrido.name, sel('recorrido', o.recorrido))] }
        : { label: 'Recorrido', value: 'Sin recorrido' },
      o.artistas.length ? { label: 'Artistas', links: artistLinks(o.artistas) } : { label: 'Artistas', value: '—' },
      cov ? { label: 'Cobertura', value: cov, title: COVER_HINT } : { label: 'Cobertura', value: NO_COVER },
      { label: 'Paths', value: String(o.routes.length) },
      { label: 'Portales', value: String(o.portals.length) },
    ],
    lists: present([rows('Paths', o.routes.map(pathRow)), rows('Portales', o.portals.map(portalRow))]),
    note: cov ? null : NO_COVER_NOTE,
  };
}

export function buildView(model, selStr, origin = 'map') {
  const p = parseSel(model, selStr);
  if (!p) return null;
  if (p.stale) return { stale: true };
  if (p.type === 'obra') return obraView(p.entity, origin);
  return { stale: true }; // ponytail: recorrido/path/portal/trigger llegan en la Task 3
}
