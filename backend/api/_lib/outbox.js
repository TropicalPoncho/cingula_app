import { TABLE_SPEC, SYNCABLE_TABLES, REQUIRED } from './spec.js';

export { SYNCABLE_TABLES };
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

  const { columns } = TABLE_SPEC[item.table_name];
  const payload = item.payload;
  for (const key of Object.keys(payload)) {
    if (!Object.hasOwn(columns, key)) return `unknown column: ${key}`;
  }
  if (item.op !== 'delete') {
    for (const col of REQUIRED[item.table_name]) {
      if (payload[col] === undefined || payload[col] === null) return `missing required column: ${col}`;
    }
    if (payload.uuid !== item.record_uuid) return 'payload.uuid must equal record_uuid';
  }
  return null;
}

const q = (id) => `"${id}"`;

/**
 * Un statement atómico por item (sql.query(text, params)); el llamador los agrupa con
 * sql.transaction([...]). Identificadores SIEMPRE del spec, valores SIEMPRE parametrizados.
 * Asume que el item ya pasó validateOutboxItem.
 */
export function upsertStatement(sql, item) {
  const t = item.table_name;
  const table = q(t);
  const version = extractVersion(item);

  if (item.op === 'delete') {
    // ponytail: un uuid desconocido es un no-op (se ackea igual); no se inserta tombstone fino.
    return sql.query(
      `UPDATE ${table} SET deleted_at = now(), logical_version = $2, updated_at = now() ` +
        `WHERE uuid = $1 AND ${table}.logical_version < $2`,
      [item.record_uuid, version],
    );
  }

  const { columns } = TABLE_SPEC[t];
  const cols = Object.keys(item.payload);
  const params = cols.map((c) => item.payload[c]);
  const values = cols.map((c, i) => (columns[c] === 'epoch' ? `to_timestamp($${i + 1})` : `$${i + 1}`));
  const sets = cols.filter((c) => c !== 'uuid').map((c) => `${q(c)} = EXCLUDED.${q(c)}`);
  return sql.query(
    `INSERT INTO ${table} (${cols.map(q).join(', ')}) VALUES (${values.join(', ')}) ` +
      `ON CONFLICT ("uuid") DO UPDATE SET ${sets.join(', ')} ` +
      `WHERE ${table}."logical_version" < EXCLUDED."logical_version"`,
    params,
  );
}
