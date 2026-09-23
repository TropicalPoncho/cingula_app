import 'package:sqflite/sqflite.dart';

/// Unica definicion del esquema v7. La migracion v6 -> v7 y AppDatabase._onCreate
/// (plan 02.1-08) llaman a [createV7Tables]; nadie repite este DDL.
///
/// REFERENCES documenta y habilita `PRAGMA foreign_key_check`, pero NO se activa
/// el enforcement de claves foraneas: la app nunca lo tuvo encendido y encenderlo cambiaria
/// el borrado de hoy.
///
/// Compatibilidad: nada posterior a SQLite 3.22 (Android API 21-28 trae 3.8-3.22).
/// La lista de construcciones prohibidas vive en 02.1-RESEARCH.md (Pitfall 7) y el
/// barrido automatico esta en el plan 02.1-11; aca no se nombran para que el grep
/// de ese barrido no se dispare contra este comentario.
const List<String> v7CreateStatements = [
  '''
CREATE TABLE audios (
  uuid TEXT PRIMARY KEY,
  kind TEXT NOT NULL DEFAULT 'grabacion' CHECK (kind IN ('grabacion','final')),
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  storage_key TEXT,
  checksum TEXT,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  logical_version INTEGER NOT NULL DEFAULT 1
)''',
  // SOLO LOCAL: nunca va al outbox (D-05/MODEL-04)
  '''
CREATE TABLE audio_local (
  audio_uuid TEXT PRIMARY KEY REFERENCES audios(uuid),
  local_path TEXT NOT NULL,
  remote_url TEXT,
  download_state TEXT
)''',
  // Vacia en 2.1: sin repositorio, entidad ni UI. Agrupa obras (D-30); recorrido_uuid en
  // obras es nullable a proposito, ninguna obra existente se le asigna un recorrido.
  '''
CREATE TABLE recorridos (
  uuid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL, deleted_at INTEGER, logical_version INTEGER NOT NULL DEFAULT 1
)''',
  // owner_id: uuid nullable sin FK, no hay tabla users todavia (D-17)
  // recorrido_uuid: nullable, D-30 — una obra puede no pertenecer a ningun recorrido todavia.
  '''
CREATE TABLE obras (
  uuid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  owner_id TEXT,
  recorrido_uuid TEXT REFERENCES recorridos(uuid),
  visibility TEXT NOT NULL DEFAULT 'draft' CHECK (visibility IN ('draft','private','public')),
  share_token TEXT,
  cover_lat REAL, cover_lon REAL,
  cover_min_lat REAL, cover_max_lat REAL, cover_min_lon REAL, cover_max_lon REAL,
  updated_at INTEGER NOT NULL, deleted_at INTEGER, logical_version INTEGER NOT NULL DEFAULT 1
)''',
  // Vacia en 2.1: sin repositorio, entidad ni UI.
  '''
CREATE TABLE artistas (
  uuid TEXT PRIMARY KEY, name TEXT NOT NULL, bio TEXT, user_id TEXT,
  updated_at INTEGER NOT NULL, deleted_at INTEGER, logical_version INTEGER NOT NULL DEFAULT 1
)''',
  // Idem: existe para el modelo, sin consumidor en 2.1.
  '''
CREATE TABLE obra_artistas (
  uuid TEXT PRIMARY KEY,
  obra_uuid TEXT NOT NULL REFERENCES obras(uuid),
  artista_uuid TEXT NOT NULL REFERENCES artistas(uuid),
  updated_at INTEGER NOT NULL, deleted_at INTEGER, logical_version INTEGER NOT NULL DEFAULT 1,
  UNIQUE (obra_uuid, artista_uuid)
)''',
  // audio_uuid nullable a proposito: tolera refs colgantes legacy.
  '''
CREATE TABLE paths (
  uuid TEXT PRIMARY KEY,
  obra_uuid TEXT NOT NULL REFERENCES obras(uuid),
  kind TEXT NOT NULL DEFAULT 'route' CHECK (kind IN ('route','portal')),
  name TEXT NOT NULL,
  audio_uuid TEXT REFERENCES audios(uuid),
  grabacion_uuid TEXT REFERENCES audios(uuid),
  tolerance_meters REAL NOT NULL DEFAULT 10.0,
  updated_at INTEGER NOT NULL, deleted_at INTEGER, logical_version INTEGER NOT NULL DEFAULT 1
)''',
  '''
CREATE TABLE triggers (
  uuid TEXT PRIMARY KEY,
  path_uuid TEXT NOT NULL REFERENCES paths(uuid),
  position INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
  latitude REAL NOT NULL, longitude REAL NOT NULL, radius_meters REAL NOT NULL,
  offset_ms INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL, deleted_at INTEGER, logical_version INTEGER NOT NULL DEFAULT 1
)''',
  // SOLO LOCAL: reemplaza geo_paths.saved_offset_ms (D-10)
  '''
CREATE TABLE path_progress (
  path_uuid TEXT PRIMARY KEY REFERENCES paths(uuid),
  saved_offset_ms INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER
)''',
  'CREATE INDEX idx_triggers_path ON triggers(path_uuid)',
  'CREATE INDEX idx_paths_obra ON paths(obra_uuid)',
];

Future<void> createV7Tables(DatabaseExecutor db) async {
  for (final s in v7CreateStatements) {
    await db.execute(s);
  }
}
