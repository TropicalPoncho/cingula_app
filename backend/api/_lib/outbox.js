export const SYNCABLE_TABLES = ['audio_assets', 'geo_triggers', 'geo_paths', 'regions'];
const OPS = ['insert', 'update', 'delete'];

/** La versión SIEMPRE sale de payload.logical_version. Null si no hay una válida. */
export function extractVersion(item) {
  const v = item?.payload?.logical_version;
  return Number.isInteger(v) ? v : null;
}

/** Devuelve null si el item es válido, o un string describiendo el primer problema. */
export function validateOutboxItem(item) {
  if (!Number.isInteger(item?.id)) return 'id must be an integer';
  if (!SYNCABLE_TABLES.includes(item?.table_name)) return `unknown table_name: ${item?.table_name}`;
  if (typeof item?.record_uuid !== 'string' || item.record_uuid.length === 0) return 'record_uuid must be a non-empty string';
  if (!OPS.includes(item?.op)) return `unknown op: ${item?.op}`;
  const version = extractVersion(item);
  if (version === null || version < 1) return 'payload.logical_version must be an integer >= 1';
  return null;
}

/** Un statement atómico por item; el llamador los agrupa con sql.transaction([...]). */
export function upsertStatement(sql, item) {
  const version = extractVersion(item);
  return sql`
    INSERT INTO synced_entities
      (table_name, record_uuid, op, current_version, current_payload, current_updated_at, deleted_at)
    VALUES
      (${item.table_name}, ${item.record_uuid}, ${item.op}, ${version},
       ${JSON.stringify(item.payload)}::jsonb, now(),
       ${item.op === 'delete' ? 'now()' : null}::timestamptz)
    ON CONFLICT (table_name, record_uuid) DO UPDATE SET
      previous_version    = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN synced_entities.current_version    ELSE synced_entities.previous_version    END,
      previous_payload    = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN synced_entities.current_payload    ELSE synced_entities.previous_payload    END,
      previous_updated_at = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN synced_entities.current_updated_at ELSE synced_entities.previous_updated_at END,
      current_version     = GREATEST(synced_entities.current_version, EXCLUDED.current_version),
      current_payload     = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN EXCLUDED.current_payload    ELSE synced_entities.current_payload    END,
      current_updated_at  = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN EXCLUDED.current_updated_at ELSE synced_entities.current_updated_at END,
      op                  = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN EXCLUDED.op                 ELSE synced_entities.op                 END,
      deleted_at          = CASE WHEN synced_entities.current_version < EXCLUDED.current_version
                                 THEN EXCLUDED.deleted_at         ELSE synced_entities.deleted_at         END
  `;
}
