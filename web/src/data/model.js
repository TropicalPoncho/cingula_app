// Lista blanca (H3), merge por uuid (WEB-08) y modelo derivado puro. Sin DOM, sin Leaflet.

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
