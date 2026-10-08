// Medición de SOLO LECTURA contra /sync/pull (OI-02, 12-03). Uso:
//   WEB_API_KEY=<clave> node web/scripts/measure-pull.mjs [base-url]
// La clave sale únicamente de la variable de entorno del proceso: no se lee ningún archivo ni se imprime (T-12-14).
// La salida son agregados `clave: valor`, sin nombres, uuids ni texto libre (T-12-13).
import { env } from 'node:process';
import { pathToFileURL } from 'node:url';
import { pullAll } from '../src/data/pull.js';
import { applyRows, buildModel, emptyTables } from '../src/data/model.js';
import { median } from '../src/data/geometry.js';

// Nearest-rank sobre una lista ya ordenada.
const pct = (sorted, p) => (sorted.length ? sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)] : 0);
const dist = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return { max: s.at(-1) ?? 0, p50: median(s), p95: pct(s, 0.95) };
};
const r1 = (n) => Math.round(n * 10) / 10;

// `pages` = [{ bytes, ms }] (bytes = caracteres del cuerpo, ~bytes: el JSON es casi todo ASCII).
export function summarize({ rows, pages, model, tables }) {
  const live = {};
  const deleted = {};
  for (const { table, payload } of rows) {
    if (!(table in tables)) continue;
    (payload.deleted_at != null ? deleted : live)[table] = ((payload.deleted_at != null ? deleted : live)[table] ?? 0) + 1;
  }

  const paths = [...model.byId.path.values()];
  const routes = paths.filter((p) => p.kind === 'route');
  const portals = paths.filter((p) => p.kind === 'portal');
  const obras = [...model.byId.obra.values()];
  const radii = routes.flatMap((p) => p.triggers.map((t) => t.radius_meters));
  const sortedRadii = [...radii].sort((a, b) => a - b);

  // H5: `position` repetidas o con saltos, sobre los triggers vivos de cada path del modelo.
  const posByPath = new Map();
  for (const t of tables.triggers.values()) {
    if (model.byId.path.has(t.path_uuid)) (posByPath.get(t.path_uuid) ?? posByPath.set(t.path_uuid, []).get(t.path_uuid)).push(t.position ?? 0);
  }
  let repeated = 0;
  let jumps = 0;
  for (const ps of posByPath.values()) {
    ps.sort((a, b) => a - b);
    if (ps.some((p, i) => i && p === ps[i - 1])) repeated++;
    if (ps.some((p, i) => i && p - ps[i - 1] > 1)) jumps++;
  }

  // D-11: audio (final o grabación) referenciado por más de un path.
  const audioUse = new Map();
  for (const p of paths) for (const a of new Set([p.audio, p.grabacion])) if (a) audioUse.set(a.uuid, (audioUse.get(a.uuid) ?? 0) + 1);

  const trigsOf = (o) => [...o.routes, ...o.portals].reduce((n, p) => n + p.triggers.length, 0);
  const routeCounts = dist(routes.map((p) => p.triggers.length));
  const obraCounts = dist(obras.map(trigsOf));
  const mixed = routes.filter((p) => {
    const rs = p.triggers.map((t) => t.radius_meters);
    return rs.length > 1 && (Math.max(...rs) - Math.min(...rs)) / p.medianRadius > 0.1;
  });

  return {
    paginas: pages.length,
    bytes_total: pages.reduce((n, p) => n + p.bytes, 0),
    bytes_max_pagina: Math.max(0, ...pages.map((p) => p.bytes)),
    ms_max_pagina: Math.max(0, ...pages.map((p) => p.ms)),
    filas_vivas: live,
    filas_descartadas: deleted,
    paths_route: routes.length,
    paths_portal: portals.length,
    triggers_por_path_route_max_p50_p95: [routeCounts.max, r1(routeCounts.p50), routeCounts.p95].join(' / '),
    triggers_por_obra_max_p50_p95: [obraCounts.max, r1(obraCounts.p50), obraCounts.p95].join(' / '),
    radio_m_min_mediana_max: [sortedRadii[0] ?? 0, r1(median(sortedRadii)), sortedRadii.at(-1) ?? 0].join(' / '),
    paths_con_radios_mezclados_gt10pct: mixed.length,
    separacion_mediana_m: r1(median(routes.filter((p) => p.triggers.length > 1).map((p) => p.spacing))),
    huecos_total: routes.reduce((n, p) => n + p.gaps.length, 0),
    paths_con_huecos: routes.filter((p) => p.gaps.length).length,
    paths_con_position_repetida: repeated,
    paths_con_position_con_saltos: jumps,
    obras_con_triggers_vivos: obras.filter((o) => trigsOf(o) > 0).length,
    portales_con_mas_de_un_trigger: portals.filter((p) => p.triggers.length > 1).length,
    audios_usados_por_mas_de_un_path: [...audioUse.values()].filter((n) => n > 1).length,
    huerfanos: model.orphans,
  };
}

const fmt = (v) => (v && typeof v === 'object' ? JSON.stringify(v) : String(v));

async function main() {
  const key = env.WEB_API_KEY;
  if (!key) {
    console.error('Uso: WEB_API_KEY=<clave> node web/scripts/measure-pull.mjs [base-url]');
    process.exit(2);
  }
  const base = (process.argv[2] ?? 'https://cingula.vercel.app').replace(/\/$/, '');
  const pages = [];
  let rows;
  try {
    ({ rows } = await pullAll({ base, key, cursor: '0', onPage: ({ bytes, ms }) => pages.push({ bytes, ms }) }));
  } catch (e) {
    console.error(e.status ? `pull falló: HTTP ${e.status} (página ${e.page})` : `pull falló: ${e.message}`);
    process.exit(1);
  }
  const { tables } = applyRows(emptyTables(), rows);
  const out = summarize({ rows, pages, model: buildModel(tables), tables });
  for (const [k, v] of Object.entries(out)) console.log(`${k}: ${fmt(v)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
