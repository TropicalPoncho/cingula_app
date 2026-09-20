export const SCHEMA_VERSION = 2;

const META = { logical_version: 'int', updated_at: 'epoch', deleted_at: 'epoch' };

// Unica fuente de tablas/columnas/tipos para validar y generar SQL. spec.test.js la compara
// contra schema.sql. 'epoch' = segundos desde SQLite, se convierte con to_timestamp($n).
export const TABLE_SPEC = {
  audios: {
    rank: 1,
    columns: {
      uuid: 'uuid', kind: 'text', title: 'text', description: 'text', duration_seconds: 'int',
      storage_key: 'text', checksum: 'text', ...META,
    },
  },
  artistas: {
    rank: 2,
    columns: { uuid: 'uuid', name: 'text', bio: 'text', user_id: 'uuid', ...META },
  },
  obras: {
    rank: 3,
    columns: {
      uuid: 'uuid', name: 'text', owner_id: 'uuid', visibility: 'text', share_token: 'text',
      cover_lat: 'float', cover_lon: 'float', cover_min_lat: 'float', cover_max_lat: 'float',
      cover_min_lon: 'float', cover_max_lon: 'float', ...META,
    },
  },
  obra_artistas: {
    rank: 4,
    columns: { uuid: 'uuid', obra_uuid: 'uuid', artista_uuid: 'uuid', ...META },
  },
  paths: {
    rank: 5,
    columns: {
      uuid: 'uuid', obra_uuid: 'uuid', kind: 'text', name: 'text', audio_uuid: 'uuid',
      grabacion_uuid: 'uuid', tolerance_meters: 'float', ...META,
    },
  },
  triggers: {
    rank: 6,
    columns: {
      uuid: 'uuid', path_uuid: 'uuid', position: 'int', name: 'text', description: 'text',
      latitude: 'float', longitude: 'float', radius_meters: 'float', offset_ms: 'int', ...META,
    },
  },
};

export const SYNCABLE_TABLES = Object.keys(TABLE_SPEC);

export const REQUIRED = {
  audios: ['uuid', 'title', 'logical_version', 'updated_at'],
  artistas: ['uuid', 'name', 'logical_version', 'updated_at'],
  obras: ['uuid', 'name', 'visibility', 'logical_version', 'updated_at'],
  obra_artistas: ['uuid', 'obra_uuid', 'artista_uuid', 'logical_version', 'updated_at'],
  paths: ['uuid', 'obra_uuid', 'kind', 'name', 'logical_version', 'updated_at'],
  triggers: ['uuid', 'path_uuid', 'name', 'latitude', 'longitude', 'radius_meters', 'logical_version', 'updated_at'],
};
