// Lista blanca (H3), merge por uuid (WEB-08) y modelo derivado puro. Sin DOM, sin Leaflet.
import { findGaps, haversineM, median, medianRadius } from './geometry.js';

// Columnas que la SPA lee. share_token, owner_id, user_id, checksum y el texto de storage_key
// no se copian (storage_key sólo deriva `has_file`).
export const USED_COLUMNS = {
  recorridos: ['uuid', 'name', 'description'],
  audios: ['uuid', 'kind', 'title', 'description', 'duration_seconds', 'storage_key'],
  artistas: ['uuid', 'name', 'bio'],
  obras: [
    'uuid', 'name', 'recorrido_uuid', 'visibility', 'cover_lat', 'cover_lon',
    'cover_min_lat', 'cover_max_lat', 'cover_min_lon', 'cover_max_lon',
  ],
  obra_artistas: ['uuid', 'obra_uuid', 'artista_uuid'],
  paths: ['uuid', 'obra_uuid', 'kind', 'name', 'audio_uuid', 'grabacion_uuid', 'tolerance_meters'],
  triggers: [
    'uuid', 'path_uuid', 'position', 'description', 'latitude', 'longitude', 'radius_meters', 'offset_ms',
  ],
};

export const emptyTables = () =>
  Object.fromEntries(Object.keys(USED_COLUMNS).map((t) => [t, new Map()]));

function whitelist(table, payload) {
  const out = {};
  for (const c of USED_COLUMNS[table]) {
    if (table === 'audios' && c === 'storage_key') continue;
    out[c] = payload[c] ?? null;
  }
  if (table === 'audios') out.has_file = !!payload.storage_key;
  return out;
}

// No muta la entrada. `discarded` = filas con deleted_at (se cuentan y se sacan del mapa).
export function applyRows(tables, rows) {
  const next = Object.fromEntries(Object.entries(tables).map(([t, m]) => [t, new Map(m)]));
  let read = 0;
  let discarded = 0;
  for (const { table, payload } of rows) {
    const map = next[table];
    if (!map) continue; // tabla desconocida
    read++;
    if (payload.deleted_at != null) {
      map.delete(payload.uuid);
      discarded++;
    } else {
      map.set(payload.uuid, whitelist(table, payload));
    }
  }
  return { tables: next, read, discarded };
}

const byName = (a, b) => a.name.localeCompare(b.name, 'es');
const byPositionThenUuid = (a, b) => (a.position ?? 0) - (b.position ?? 0) || (a.uuid < b.uuid ? -1 : a.uuid > b.uuid ? 1 : 0);
const push = (m, k, v) => (m.has(k) ? m.get(k).push(v) : m.set(k, [v]));
const COVER = ['cover_lat', 'cover_lon', 'cover_min_lat', 'cover_max_lat', 'cover_min_lon', 'cover_max_lon'];

// Modelo de vista: puro, se calcula una vez por pull. Las referencias entre entidades son objetos
// (obra.recorrido, path.obra, ...): el modelo es un grafo en memoria, no se serializa.
// Filtro en cascada (WEB-08): lo que cuelga de algo ausente o borrado no existe; se cuenta en `orphans`.
export function buildModel(tables) {
  const orphans = {};
  const drop = (t) => { orphans[t] = (orphans[t] ?? 0) + 1; };

  const audios = new Map([...tables.audios].map(([k, a]) => [k, { ...a }]));
  const artistas = new Map([...tables.artistas.values()].map((a) => [a.uuid, { uuid: a.uuid, name: a.name, bio: a.bio, obras: [] }]));
  const recorridos = new Map([...tables.recorridos.values()].map((r) => [r.uuid, { uuid: r.uuid, name: r.name, description: r.description, obras: [], artistas: [] }]));

  const obras = new Map();
  for (const o of tables.obras.values()) {
    obras.set(o.uuid, {
      uuid: o.uuid,
      name: o.name,
      visibility: o.visibility, // enums fuera del CHECK se conservan crudos (OI-04)
      recorrido: recorridos.get(o.recorrido_uuid) ?? null, // desconocido -> sin recorrido
      cover: COVER.some((c) => o[c] == null)
        ? null
        : { lat: o.cover_lat, lon: o.cover_lon, minLat: o.cover_min_lat, maxLat: o.cover_max_lat, minLon: o.cover_min_lon, maxLon: o.cover_max_lon },
      artistas: [], routes: [], portals: [], maxRadius: 0,
    });
  }

  // Triggers agrupados por path y ordenados por (position, uuid); `index` = lugar en la lista filtrada (H5).
  const trigRows = new Map();
  for (const t of tables.triggers.values()) push(trigRows, t.path_uuid, t);

  const paths = new Map();
  const triggers = new Map();
  for (const p of tables.paths.values()) {
    const obra = obras.get(p.obra_uuid);
    if (!obra) { drop('paths'); continue; }
    const rows = (trigRows.get(p.uuid) ?? []).sort(byPositionThenUuid);
    const path = {
      uuid: p.uuid, name: p.name, kind: p.kind, obra,
      audio: audios.get(p.audio_uuid) ?? null,
      grabacion: audios.get(p.grabacion_uuid) ?? null,
      tolerance_meters: p.tolerance_meters,
      triggers: [], gaps: [], medianRadius: 0, spacing: 0,
    };
    path.triggers = rows.map((t, index) => {
      const tr = { uuid: t.uuid, path, index, latitude: t.latitude, longitude: t.longitude, radius_meters: t.radius_meters, offset_ms: t.offset_ms };
      triggers.set(tr.uuid, tr);
      return tr;
    });
    path.medianRadius = medianRadius(path.triggers);
    path.spacing = median(path.triggers.slice(1).map((t, i) => haversineM(path.triggers[i], t)));
    if (p.kind === 'route') path.gaps = findGaps(path.triggers);
    if (p.kind === 'portal') { // OI-01c: el portal es su primer trigger y la descripción de ese trigger
      path.trigger = path.triggers[0] ?? null;
      path.description = rows[0]?.description ?? null;
    }
    for (const t of path.triggers) obra.maxRadius = Math.max(obra.maxRadius, t.radius_meters);
    (p.kind === 'route' ? obra.routes : p.kind === 'portal' ? obra.portals : []).push(path);
    paths.set(path.uuid, path);
  }
  for (const [pu, rows] of trigRows) if (!paths.has(pu)) rows.forEach(() => drop('triggers'));

  const seen = new Set();
  for (const oa of tables.obra_artistas.values()) {
    const obra = obras.get(oa.obra_uuid);
    const artista = artistas.get(oa.artista_uuid);
    if (!obra || !artista) { drop('obra_artistas'); continue; }
    const pair = `${obra.uuid}|${artista.uuid}`;
    if (seen.has(pair)) continue;
    seen.add(pair);
    obra.artistas.push(artista);
    artista.obras.push(obra);
  }

  for (const o of obras.values()) {
    o.artistas.sort(byName);
    o.routes.sort(byName);
    o.portals.sort(byName);
    o.recorrido?.obras.push(o);
  }
  for (const a of artistas.values()) a.obras.sort(byName);
  for (const r of recorridos.values()) {
    r.obras.sort(byName);
    r.artistas = [...new Map(r.obras.flatMap((o) => o.artistas).map((a) => [a.uuid, a])).values()].sort(byName);
  }

  const all = [...paths.values()];
  const routes = all.filter((p) => p.kind === 'route');
  return {
    recorridos: [...recorridos.values()].sort(byName),
    obras: [...obras.values()].sort(byName),
    artistas: [...artistas.values()].sort(byName),
    byId: { recorrido: recorridos, obra: obras, artista: artistas, path: paths, trigger: triggers },
    counts: {
      obras: obras.size,
      paths: routes.length,
      triggers: routes.reduce((n, p) => n + p.triggers.length, 0),
      portales: all.filter((p) => p.kind === 'portal').length,
    },
    orphans,
  };
}
