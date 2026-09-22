// Migracion one-shot synced_entities -> tablas tipadas (D-13 / MODEL-06).
// Uso (desde backend/): node scripts/migrate_v2.mjs [--url=<...>] [--apply] [--finalize]
// Sin flags es DRY-RUN: no escribe una sola fila.
import { neon } from '@neondatabase/serverless';
import { writeFileSync, readFileSync } from 'node:fs';
import { TABLE_SPEC } from '../api/_lib/spec.js';
import { upsertStatement, validateOutboxItem } from '../api/_lib/outbox.js';
import { applySchema } from '../api/_lib/schema_loader.js';
import { translate } from './translate.js';

// Ids de SQLite reutilizados (delete+recreate) que un humano ya resolvió a mano mirando la copia
// local de la BD del celular. Ver 02.1-NEON-REHEARSAL.md.
const overrides = JSON.parse(readFileSync(new URL('./id_overrides.json', import.meta.url), 'utf8'));

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const finalize = args.includes('--finalize');
const url = args.find((a) => a.startsWith('--url='))?.slice(6) || process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL requerido');
  process.exit(1);
}

// El script tiene que decir a que rama de Neon le pega, sin credenciales.
const u = new URL(url);
console.log(`Conectado a: ${u.host}${u.pathname}`);
const sql = neon(url);

if (finalize) {
  // Solo cuando los conteos cuadraron Y el backend nuevo esta desplegado. NUNCA se borra.
  const [{ n }] = await sql.query(
    "SELECT count(*)::int AS n FROM information_schema.tables WHERE table_name = 'synced_entities'",
  );
  if (n === 0) {
    console.log('synced_entities ya esta renombrada (o no existe). Nada que hacer.');
  } else {
    await sql.query('ALTER TABLE synced_entities RENAME TO synced_entities_legacy');
    console.log('synced_entities -> synced_entities_legacy');
  }
  process.exit(0);
}

const rows = await sql.query('SELECT * FROM synced_entities');
let result;
try {
  result = translate(rows, overrides);
} catch (e) {
  console.error('ABORTA:', e.message);
  process.exit(1);
}
const { tables, skipped, warnings, counts } = result;

console.log('\nOrigen (por tabla):');
for (const [t, c] of Object.entries(counts.source)) console.log(`  ${t}: ${c.live} vivos, ${c.tombstone} con tombstone`);
console.log('Destino (por tabla):');
for (const [t, n] of Object.entries(counts.target)) console.log(`  ${t}: ${n}`);
console.log(`Omitidos: ${skipped.length}`);
for (const s of skipped) console.log(`  ${s.table_name} ${s.record_uuid}: ${s.reason}`);
console.log(`Advertencias: ${warnings.length}`);
for (const w of warnings) console.log(`  ${w}`);

// Cada fila tiene que pasar la misma validacion que el push: no entra por la puerta de atras.
const items = Object.keys(TABLE_SPEC)
  .sort((a, b) => TABLE_SPEC[a].rank - TABLE_SPEC[b].rank)
  .flatMap((t) => tables[t].map((row) => ({ table_name: t, record_uuid: row.uuid, op: 'insert', payload: row })))
  .map((item, i) => ({ ...item, id: i + 1 }));
const invalid = items.map((it) => [it, validateOutboxItem(it)]).filter(([, err]) => err);
if (invalid.length) {
  for (const [it, err] of invalid) console.error(`INVALIDA ${it.table_name} ${it.record_uuid}: ${err}`);
  process.exit(1);
}

if (!apply) {
  console.log('\nDRY-RUN: no se escribio nada. Usar --apply para aplicar.');
  process.exit(0);
}

if (apply) {
  // Volcado previo (ignorado por git).
  const dump = `scripts/dump-synced-entities-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  writeFileSync(dump, JSON.stringify(rows, null, 2));
  console.log(`\nVolcado: ${dump}`);

  await applySchema(sql); // fuera de la transaccion de datos: schema.sql es re-ejecutable
  await sql.transaction(items.map((it) => upsertStatement(sql, it)));
  console.log(`Aplicadas ${items.length} filas.`);

  // Verificacion re-consultando la base. >= y no ==: una re-corrida posterior al deploy
  // convive con filas que el celular ya subio por el push normal.
  const n = async (t) => (await sql.query(`SELECT count(*)::int AS n FROM "${t}"`))[0].n;
  const got = Object.fromEntries(await Promise.all(Object.keys(tables).map(async (t) => [t, await n(t)])));
  console.log('En la base:', got);
  const bad = Object.keys(tables).filter((t) => got[t] < counts.target[t]);
  if (got.obras < got.paths) bad.push('obras<paths');
  if (bad.length) {
    console.error('NO CUADRA:', bad.join(', '));
    process.exit(1);
  }
  console.log('Conteos verificados.');
}

// Orden del corte (D-20, guion del plan 02.1-12):
// ensayar en una rama descartable -> no abrir la app (modo avion) -> correr este script en la
// rama objetivo -> desplegar el backend nuevo -> --finalize -> instalar la app nueva ->
// el primer arranque migra y reenvia todo.
