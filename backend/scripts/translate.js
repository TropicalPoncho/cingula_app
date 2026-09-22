import { TABLE_SPEC } from '../api/_lib/spec.js';
import { obraUuidForPath, portalUuidForTrigger } from '../api/_lib/ids.js';
import { computeCover } from '../api/_lib/cover.js';

// Traduccion PURA synced_entities -> filas tipadas. Mismas reglas que migrateToV7 (Dart):
// si divergen, el primer sync duplica filas. No genera SQL (eso es upsertStatement).

const isTomb = (r) => r.op === 'delete';
const epoch = (d) => Math.floor(new Date(d).getTime() / 1000);

/**
 * 'tabla:id' -> uuid. Los payloads vivos mandan; previous solo completa lo que falta.
 * `overrides`: { 'tabla:id': uuid } para ids reutilizados por SQLite (delete+recreate) donde el
 * humano ya confirmó a mano cuál uuid es el vivo (ver id_overrides.json). Sin override para una
 * clave ambigua, esa clave sigue abortando (fail-safe, no fail-silent).
 */
export function buildIdMap(rows, overrides = {}) {
  const map = new Map();
  const seen = new Map(); // key -> Set(uuid) de payloads vivos
  const add = (table, p, live) => {
    if (p?.id == null || !p.uuid) return;
    const key = `${table}:${p.id}`;
    if (live) {
      const s = seen.get(key) ?? new Set();
      s.add(p.uuid);
      seen.set(key, s);
      map.set(key, p.uuid);
    } else if (!map.has(key)) {
      map.set(key, p.uuid);
    }
  };
  for (const r of rows) if (!isTomb(r)) add(r.table_name, r.current_payload, true);
  for (const r of rows) add(r.table_name, r.previous_payload, false);
  const ambiguous = [];
  const resolved = [];
  for (const [key, s] of seen) {
    if (s.size > 1) {
      const i = key.indexOf(':');
      const table = key.slice(0, i);
      const id = key.slice(i + 1);
      const override = overrides[key];
      if (override && s.has(override)) {
        map.set(key, override);
        resolved.push({ table, id, uuid: override, discarded: [...s].filter((u) => u !== override) });
      } else {
        ambiguous.push({ table, id, uuids: [...s] });
      }
    }
  }
  return { map, ambiguous, resolved };
}

// Solo las claves del spec (el generador de SQL rechaza cualquier otra); faltantes = null.
const pick = (t, src) =>
  Object.fromEntries(Object.keys(TABLE_SPEC[t].columns).map((c) => [c, src[c] ?? null]));

export function translate(rows, overrides = {}) {
  const { map, ambiguous, resolved } = buildIdMap(rows, overrides);
  if (ambiguous.length) {
    throw new Error(
      'ids ambiguos: ' + ambiguous.map((a) => `${a.table}:${a.id} -> ${a.uuids.join(', ')}`).join('; '),
    );
  }
  const tables = { audios: [], artistas: [], obras: [], obra_artistas: [], paths: [], triggers: [] };
  const skipped = [];
  const warnings = [];
  const source = {};
  for (const r of resolved) {
    for (const uuid of r.discarded) {
      skipped.push({
        table_name: r.table,
        record_uuid: uuid,
        reason: `id ambiguo: uuid descartado por override, ver ${r.table}:${r.id}`,
      });
    }
  }

  // Estado efectivo de cada entidad (tombstone reconstruido desde previous_payload).
  const ents = { audio_assets: [], geo_paths: [], geo_triggers: [] };
  for (const r of rows) {
    const s = (source[r.table_name] ??= { live: 0, tombstone: 0 });
    if (isTomb(r)) s.tombstone++;
    else s.live++;
    if (!ents[r.table_name]) continue; // regions y otras: no producen nada (D-16)
    let p;
    if (isTomb(r)) {
      if (!r.previous_payload) {
        skipped.push({
          table_name: r.table_name,
          record_uuid: r.record_uuid,
          reason: 'delete sin previous_payload: no se puede reconstruir',
        });
        continue;
      }
      p = { ...r.previous_payload, deleted_at: epoch(r.current_updated_at), logical_version: r.current_version };
    } else {
      p = { ...r.current_payload };
    }
    p.uuid ??= r.record_uuid;
    if (p.logical_version == null) {
      warnings.push(`${r.table_name} ${p.uuid}: logical_version nulo, se usa 1`);
      p.logical_version = 1;
    }
    p.updated_at ??= epoch(r.current_updated_at);
    ents[r.table_name].push(p);
  }

  const audioUuid = (id) => (id == null ? null : (map.get(`audio_assets:${id}`) ?? null));
  const meta = (p) => ({
    updated_at: p.updated_at,
    deleted_at: p.deleted_at ?? null,
    logical_version: p.logical_version,
  });
  const points = new Map(); // obra uuid -> [{lat, lon}]
  const obras = new Map();

  const addObra = (pathUuid, p) => {
    const uuid = obraUuidForPath(pathUuid);
    obras.set(uuid, pick('obras', { uuid, name: p.name, visibility: 'draft', ...meta(p) }));
    return uuid;
  };

  for (const p of ents.audio_assets) {
    // artist/local_path/remote_url no viajan (D-30, MODEL-04)
    tables.audios.push(pick('audios', {
      uuid: p.uuid, kind: 'grabacion', title: p.title, description: p.description,
      duration_seconds: p.duration_seconds, ...meta(p),
    }));
  }

  const pathUuidById = new Map();
  for (const p of ents.geo_paths) {
    if (p.id != null) pathUuidById.set(p.id, p.uuid);
    const obra = addObra(p.uuid, p);
    tables.paths.push(pick('paths', {
      uuid: p.uuid, obra_uuid: obra, kind: 'route', name: p.name,
      audio_uuid: audioUuid(p.audio_asset_id), tolerance_meters: p.tolerance_meters, ...meta(p),
    }));
  }

  const position = new Map();
  const trigs = [...ents.geo_triggers].sort(
    (a, b) => (a.offset_ms ?? 0) - (b.offset_ms ?? 0) || (a.id ?? 0) - (b.id ?? 0),
  );
  for (const p of trigs) {
    let pathUuid = p.geo_path_id != null ? pathUuidById.get(p.geo_path_id) : undefined;
    if (!pathUuid) {
      if (p.geo_path_id != null) warnings.push(`trigger ${p.uuid}: geo_path_id ${p.geo_path_id} colgante, se crea portal`);
      pathUuid = portalUuidForTrigger(p.uuid);
      const obra = addObra(pathUuid, p);
      tables.paths.push(pick('paths', {
        uuid: pathUuid, obra_uuid: obra, kind: 'portal', name: p.name,
        audio_uuid: audioUuid(p.audio_asset_id), tolerance_meters: 10.0, ...meta(p),
      }));
    }
    const pos = position.get(pathUuid) ?? 0;
    position.set(pathUuid, pos + 1);
    tables.triggers.push(pick('triggers', {
      uuid: p.uuid, path_uuid: pathUuid, position: pos, name: p.name, description: p.description,
      latitude: p.latitude, longitude: p.longitude, radius_meters: p.radius_meters,
      offset_ms: p.offset_ms, ...meta(p),
    }));
    const obra = obraUuidForPath(pathUuid);
    if (!points.has(obra)) points.set(obra, []);
    points.get(obra).push({ lat: p.latitude, lon: p.longitude });
  }

  for (const [uuid, o] of obras) {
    const pts = points.get(uuid);
    if (pts) {
      const c = computeCover(pts);
      Object.assign(o, {
        cover_lat: c.centerLat, cover_lon: c.centerLon, cover_min_lat: c.minLat,
        cover_max_lat: c.maxLat, cover_min_lon: c.minLon, cover_max_lon: c.maxLon,
      });
    }
    tables.obras.push(o);
  }

  const target = Object.fromEntries(Object.entries(tables).map(([t, r]) => [t, r.length]));
  return { tables, skipped, warnings, counts: { source, target } };
}
