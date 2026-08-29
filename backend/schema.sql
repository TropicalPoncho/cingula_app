-- Una sola tabla genérica en vez de 4 espejando el schema SQLite: en esta fase el payload
-- es opaco para el servidor (no hay queries por columna hasta el pull de la Fase 3), así que
-- 4 tablas serían 4x DDL sin ningún beneficio. Ver 02-RESEARCH.md > Alternatives Considered.
CREATE TABLE IF NOT EXISTS synced_entities (
  table_name           TEXT        NOT NULL,
  record_uuid          TEXT        NOT NULL,
  op                   TEXT        NOT NULL,
  current_version      INTEGER     NOT NULL,
  current_payload      JSONB       NOT NULL,
  current_updated_at   TIMESTAMPTZ NOT NULL,
  previous_version     INTEGER,
  previous_payload     JSONB,
  previous_updated_at  TIMESTAMPTZ,
  deleted_at           TIMESTAMPTZ,
  PRIMARY KEY (table_name, record_uuid)
);
