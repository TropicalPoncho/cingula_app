import { neon } from '@neondatabase/serverless';

let _sql;

export function getSql() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('DATABASE_URL is not set');
  _sql ??= neon(url);
  return _sql;
}

// ponytail: un solo advisory lock global para todo lo que escribe tablas sincronizables (D-01,
// ADR-012). El push lo toma exclusivo (pg_advisory_xact_lock) como PRIMERA sentencia; cada página
// de pull lo toma compartido (pg_advisory_xact_lock_shared). Así un pull nunca lee mientras hay un
// push con change_seq asignados sin comitear. TECHO: solo protege a quien toma el lock. Todo
// escritor nuevo (escritura de la web ADR-006, scripts como scripts/migrate_v2.mjs, SQL manual en
// la consola de Neon) tiene que tomar pg_advisory_xact_lock(SYNC_LOCK_KEY) en su transacción, o
// puede generar un salto permanente en el cursor de los clientes.
export const SYNC_LOCK_KEY = 20260923;
