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
export const visOf = (v) => (Object.hasOwn(VIS, v ?? '') ? VIS[v] : { label: v ?? '—', mono: true, dot: 'var(--ink-200)' });

const NO_COVER = 'Sin cobertura todavía';
const NO_COVER_NOTE = 'La obra no tiene triggers, así que no hay dónde dibujarla.';
const COVER_HINT = 'Ancho × alto del contorno: incluye el radio de los triggers.';

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

// Cobertura = ancho × alto de los bounds del contorno (D-20; ya incluyen el radio de los triggers), en metros.
function coverage(o) {
  if (!o.outline) return null;
  const { minLat, maxLat, minLon, maxLon } = o.outline.bounds;
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

const BASE = { lists: [], back: null, description: null, audio: null, strip: null, table: null, note: null, neighbors: null };

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

const TRIGGER_NOTE =
  'Los triggers sólo marcan el camino: no tienen nombre ni sonido propio. El sonido del path suena mientras el celular esté dentro de alguno.';
const PORTAL_OFFSET_HINT = 'La app todavía ignora el offset de los portales: siempre arranca en 0.';
const NO_GAPS = 'Los triggers se solapan de punta a punta: el path no tiene huecos.';

function recorridoView(r) {
  const paths = r.obras.flatMap((o) => o.routes);
  return {
    ...BASE,
    type: 'recorrido',
    typeLabel: 'RECORRIDO',
    title: r.name,
    subtitle: 'Créditos calculados: unión de los artistas de sus obras.',
    crumbs: [{ label: r.name, sel: null }],
    facts: [
      { label: 'Obras', value: String(r.obras.length) },
      { label: 'Paths', value: String(paths.length) },
      { label: 'Portales', value: String(r.obras.reduce((n, o) => n + o.portals.length, 0)) },
      { label: 'Triggers', value: String(paths.reduce((n, p) => n + p.triggers.length, 0)) },
      r.artistas.length ? { label: 'Créditos', links: artistLinks(r.artistas) } : { label: 'Créditos', value: '—' },
    ],
    description: r.description || null,
    lists: present([
      rows('Obras', r.obras.map((o) => ({
        label: o.name,
        sub: `${visOf(o.visibility).label} · ${plural(o.routes.length, 'path', 'paths')}`,
        sel: sel('obra', o),
      }))),
    ]),
  };
}

function audioCard(label, a, noneText) {
  if (!a) return { label, state: 'none', title: null, description: null, kind: null, duration: null, emptyText: noneText };
  return {
    label,
    state: a.has_file ? 'file' : 'nofile',
    title: a.title,
    description: a.description,
    kind: a.kind,
    duration: a.duration_seconds > 0 ? mmss(a.duration_seconds) : null,
    // 'Sin archivo todavía' (título del bloque) es copy fijo de 12-06; acá va su cuerpo (STOR-04).
    emptyText: a.has_file ? null : 'El audio está registrado, pero su archivo todavía no existe en el servidor.',
  };
}

const where = (o, origin) => (origin === 'pageObras' || !o.recorrido ? o.name : `${o.name} · ${o.recorrido.name}`);

// Tira de cobertura: un cuadro por trigger y uno extra donde hay hueco (los huecos vienen del modelo).
function stripOf(p) {
  const n = p.triggers.length;
  if (!n) return null;
  const at = new Map(p.gaps.map((g) => [g.from, g]));
  const texts = p.gaps
    .slice(0, 3)
    .map((g) => `Hueco de ≈ ${Math.round(g.meters)} m entre el trigger ${pad3(g.from + 1)} y el ${pad3(g.to + 1)}`);
  const more = p.gaps.length > 3 ? ` +${p.gaps.length - 3} más` : '';
  return {
    cells: p.triggers.flatMap((_, i) => (at.has(i) ? [{ gap: false }, { gap: true, meters: Math.round(at.get(i).meters) }] : [{ gap: false }])),
    ariaLabel: `${plural(n, 'trigger', 'triggers')}, ${plural(p.gaps.length, 'hueco', 'huecos')}`,
    note: n < 2 ? null : p.gaps.length ? `${texts.join('. ')}.${more}` : NO_GAPS,
  };
}

function pathView(p, origin) {
  const o = p.obra;
  const n = p.triggers.length;
  const triggersFact = !n
    ? '0'
    : [String(n), `radio ${m(p.medianRadius)}`, n > 1 && `cada ≈ ${Math.round(p.spacing)} m`].filter(Boolean).join(' · ');
  return {
    ...BASE,
    type: 'path',
    typeLabel: 'PATH',
    title: p.name,
    subtitle: where(o, origin),
    crumbs: crumbs(origin, o, link(p.name)),
    back: { label: o.name, sel: sel('obra', o) },
    facts: [
      { label: 'Obra', links: [link(o.name, sel('obra', o))] },
      { label: 'Tipo', value: p.kind, mono: true },
      { label: 'Tolerancia', value: p.tolerance_meters == null ? '—' : m(p.tolerance_meters), mono: true },
      { label: 'Grabación de origen', value: p.grabacion?.title ?? '—' },
      { label: 'Triggers', value: triggersFact },
      p.gaps.length
        ? { label: 'Huecos', value: plural(p.gaps.length, 'hueco', 'huecos'), dot: 'var(--c-ambar)' }
        : { label: 'Huecos', value: 'Ninguno', dot: 'var(--c-mint)' },
    ],
    // R1: los portales cuelgan de la obra, nunca "del path".
    lists: present([rows('Portales de la obra', o.portals.map(portalRow))]),
    audio: audioCard('Audio del path', p.audio, 'Este path no tiene audio asignado.'),
    strip: stripOf(p),
    table: o.portals.length
      ? {
          title: 'Portales de la obra',
          rows: o.portals.map((q, i) => ({
            n: i + 1,
            name: q.name,
            sel: sel('portal', q),
            radius: q.trigger ? m(q.trigger.radius_meters) : '—',
            offset: q.trigger ? off(q.trigger.offset_ms) : '—',
            pos: q.trigger ? latlon(q.trigger.latitude, q.trigger.longitude) : '—',
          })),
        }
      : null,
  };
}

function portalView(p, origin) {
  const o = p.obra;
  const t = p.trigger; // un portal sin trigger se lista, pero no tiene posición, radio ni offset
  return {
    ...BASE,
    type: 'portal',
    typeLabel: 'PORTAL',
    title: p.name,
    subtitle: where(o, origin),
    crumbs: crumbs(origin, o, link(p.name)),
    back: { label: o.name, sel: sel('obra', o) },
    facts: [
      { label: 'Obra', links: [link(o.name, sel('obra', o))] },
      ...(t
        ? [
            { label: 'Posición', value: latlon(t.latitude, t.longitude), mono: true },
            { label: 'Radio', value: m(t.radius_meters) },
            { label: 'Offset', value: off(t.offset_ms), mono: true, title: PORTAL_OFFSET_HINT },
          ]
        : []),
    ],
    description: p.description || null,
    lists: present([rows('Otros portales de la obra', o.portals.filter((q) => q !== p).map(portalRow))]),
    audio: audioCard('Audio del portal', p.audio, 'Este portal no tiene audio asignado.'),
  };
}

function triggerView(t, origin) {
  const p = t.path;
  const o = p.obra;
  const n = p.triggers.length;
  const title = `Trigger ${pad3(t.index + 1)}`;
  const near = (other, label) =>
    other
      ? { label: `${label} · trigger ${pad3(other.index + 1)}`, sub: `a ${Math.round(haversineM(t, other))} m`, sel: sel('trigger', other) }
      : null;
  const prev = near(p.triggers[t.index - 1], 'Anterior');
  const next = near(p.triggers[t.index + 1], 'Siguiente');
  return {
    ...BASE,
    type: 'trigger',
    typeLabel: 'TRIGGER',
    title, // anónimo (R4): ni `name` ni `description` de la fila se muestran
    subtitle: `${p.name} · ${o.name}`,
    crumbs: crumbs(origin, o, link(p.name, sel('path', p)), link(title)),
    back: { label: p.name, sel: sel('path', p) },
    facts: [
      { label: 'Path', links: [link(p.name, sel('path', p))] },
      { label: 'Posición', value: latlon(t.latitude, t.longitude), mono: true },
      { label: 'Radio', value: m(t.radius_meters) },
      { label: 'Orden', value: `${t.index + 1} de ${n}` },
      { label: 'Offset en el audio', value: off(t.offset_ms), mono: true },
    ],
    note: TRIGGER_NOTE,
    neighbors: prev || next ? { prev, next } : null,
  };
}

const BUILDERS = { recorrido: recorridoView, obra: obraView, path: pathView, portal: portalView, trigger: triggerView };

export function buildView(model, selStr, origin = 'map') {
  const p = parseSel(model, selStr);
  if (!p) return null;
  if (p.stale) return { stale: true };
  return BUILDERS[p.type](p.entity, origin);
}
