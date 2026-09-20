import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SCHEMA_PATH = fileURLToPath(new URL('../../schema.sql', import.meta.url));

/// Parte el texto en statements de nivel superior. Respeta el dollar-quoting de Postgres
/// ($$ ... $$ y $tag$ ... $tag$), lo unico que puede contener ';' dentro de schema.sql.
/// No es un parser de SQL: es lo que hace falta para este archivo y nada mas.
export function splitStatements(sqlText) {
  const out = [];
  let cur = '';
  let tag = null; // tag de dollar-quote abierto, o null
  const lines = sqlText.split('\n');
  for (const line of lines) {
    if (tag === null && line.trimStart().startsWith('--')) continue;
    let i = 0;
    while (i < line.length) {
      const ch = line[i];
      if (ch === '$') {
        const m = /^\$[A-Za-z_]*\$/.exec(line.slice(i));
        if (m) {
          if (tag === null) tag = m[0];
          else if (tag === m[0]) tag = null;
          cur += m[0];
          i += m[0].length;
          continue;
        }
      }
      if (ch === ';' && tag === null) {
        if (cur.trim()) out.push(cur.trim());
        cur = '';
      } else {
        cur += ch;
      }
      i++;
    }
    cur += '\n';
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

/// Ejecuta los statements EN ORDEN, sin transaccion (el archivo es re-ejecutable).
export async function applySchema(sql, sqlText = readFileSync(SCHEMA_PATH, 'utf8')) {
  for (const stmt of splitStatements(sqlText)) await sql.query(stmt);
}
