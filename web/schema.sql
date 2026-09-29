-- Esquema tipado v2 (D-09): una tabla por entidad, columnas consultables. Reemplaza a la tabla
-- generica de la Fase 2 (revierte esa decision). La tabla vieja NO se toca aca: el script
-- scripts/migrate_v2.mjs --finalize la conserva renombrada.
-- Re-ejecutable: todo es IF NOT EXISTS / OR REPLACE, sin ningun DROP de tablas.

CREATE SEQUENCE IF NOT EXISTS change_seq;

-- D-33: agrupa obras (una por artista/sesion). Vacia hasta que exista un consumidor.
CREATE TABLE IF NOT EXISTS recorridos (
  uuid uuid PRIMARY KEY,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq')
);

CREATE TABLE IF NOT EXISTS audios (
  uuid uuid PRIMARY KEY,
  kind text NOT NULL DEFAULT 'grabacion' CHECK (kind IN ('grabacion','final')),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  duration_seconds integer NOT NULL DEFAULT 0,
  storage_key text,
  checksum text,
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq')
);

CREATE TABLE IF NOT EXISTS artistas (
  uuid uuid PRIMARY KEY,
  name text NOT NULL,
  bio text,
  user_id uuid,
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq')
);

CREATE TABLE IF NOT EXISTS obras (
  uuid uuid PRIMARY KEY,
  name text NOT NULL,
  owner_id uuid,
  recorrido_uuid uuid REFERENCES recorridos(uuid) DEFERRABLE INITIALLY DEFERRED,
  visibility text NOT NULL DEFAULT 'draft' CHECK (visibility IN ('draft','private','public')),
  share_token text UNIQUE,
  cover_lat double precision,
  cover_lon double precision,
  cover_min_lat double precision,
  cover_max_lat double precision,
  cover_min_lon double precision,
  cover_max_lon double precision,
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq')
);
-- recorrido_uuid llega despues de la primera version de esta tabla en algunas ramas
-- (D-33): CREATE TABLE IF NOT EXISTS no altera una tabla ya creada, asi que el ALTER
-- de abajo es lo que de verdad agrega la columna donde ya existia obras sin ella.
ALTER TABLE obras ADD COLUMN IF NOT EXISTS recorrido_uuid uuid REFERENCES recorridos(uuid) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE IF NOT EXISTS obra_artistas (
  uuid uuid PRIMARY KEY,
  obra_uuid uuid NOT NULL REFERENCES obras(uuid) DEFERRABLE INITIALLY DEFERRED,
  artista_uuid uuid NOT NULL REFERENCES artistas(uuid) DEFERRABLE INITIALLY DEFERRED,
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq'),
  UNIQUE (obra_uuid, artista_uuid)
);

CREATE TABLE IF NOT EXISTS paths (
  uuid uuid PRIMARY KEY,
  obra_uuid uuid NOT NULL REFERENCES obras(uuid) DEFERRABLE INITIALLY DEFERRED,
  kind text NOT NULL DEFAULT 'route' CHECK (kind IN ('route','portal')),
  name text NOT NULL,
  audio_uuid uuid REFERENCES audios(uuid) DEFERRABLE INITIALLY DEFERRED,
  grabacion_uuid uuid REFERENCES audios(uuid) DEFERRABLE INITIALLY DEFERRED,
  tolerance_meters double precision NOT NULL DEFAULT 10.0,
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq')
);

CREATE TABLE IF NOT EXISTS triggers (
  uuid uuid PRIMARY KEY,
  path_uuid uuid NOT NULL REFERENCES paths(uuid) DEFERRABLE INITIALLY DEFERRED,
  "position" integer NOT NULL DEFAULT 0,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  radius_meters double precision NOT NULL,
  offset_ms integer NOT NULL DEFAULT 0,
  logical_version integer NOT NULL CHECK (logical_version >= 1),
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  change_seq bigint NOT NULL DEFAULT nextval('change_seq')
);

-- Una fila por entidad: la PK hace cumplir "exactamente 1 version anterior" sin codigo de poda.
CREATE TABLE IF NOT EXISTS entity_prev (
  table_name text NOT NULL,
  record_uuid uuid NOT NULL,
  version integer NOT NULL,
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (table_name, record_uuid)
);

CREATE INDEX IF NOT EXISTS recorridos_change_seq_idx ON recorridos (change_seq);
CREATE INDEX IF NOT EXISTS audios_change_seq_idx ON audios (change_seq);
CREATE INDEX IF NOT EXISTS artistas_change_seq_idx ON artistas (change_seq);
CREATE INDEX IF NOT EXISTS obras_change_seq_idx ON obras (change_seq);
CREATE INDEX IF NOT EXISTS obra_artistas_change_seq_idx ON obra_artistas (change_seq);
CREATE INDEX IF NOT EXISTS paths_change_seq_idx ON paths (change_seq);
CREATE INDEX IF NOT EXISTS triggers_change_seq_idx ON triggers (change_seq);
CREATE INDEX IF NOT EXISTS paths_obra_uuid_idx ON paths (obra_uuid);
CREATE INDEX IF NOT EXISTS triggers_path_uuid_idx ON triggers (path_uuid);
CREATE INDEX IF NOT EXISTS obras_cover_bbox_idx ON obras (cover_min_lat, cover_max_lat, cover_min_lon, cover_max_lon);

CREATE OR REPLACE FUNCTION bump_change_seq() RETURNS trigger AS $$
BEGIN
  NEW.change_seq := nextval('change_seq');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION save_prev_version() RETURNS trigger AS $$
BEGIN
  INSERT INTO entity_prev (table_name, record_uuid, version, payload, updated_at)
  VALUES (TG_TABLE_NAME, OLD.uuid, OLD.logical_version, to_jsonb(OLD), OLD.updated_at)
  ON CONFLICT (table_name, record_uuid) DO UPDATE
    SET version = EXCLUDED.version, payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['recorridos','audios','artistas','obras','obra_artistas','paths','triggers'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_bump_seq', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION bump_change_seq()', t || '_bump_seq', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_save_prev', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW WHEN (OLD.logical_version < NEW.logical_version) EXECUTE FUNCTION save_prev_version()', t || '_save_prev', t);
  END LOOP;
END;
$$;
