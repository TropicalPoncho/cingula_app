import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { TABLE_SPEC, REQUIRED } from './spec.js';
import { splitStatements } from './schema_loader.js';

const schema = readFileSync(fileURLToPath(new URL('../../schema.sql', import.meta.url)), 'utf8');

test('spec y schema.sql no divergen: cada tabla y columna existe en el DDL', () => {
  for (const [table, { columns }] of Object.entries(TABLE_SPEC)) {
    const m = new RegExp(`CREATE TABLE IF NOT EXISTS ${table} \\(([\\s\\S]*?)\\n\\);`).exec(schema);
    assert.ok(m, `tabla ${table} no esta en schema.sql`);
    for (const col of Object.keys(columns)) {
      assert.match(m[1], new RegExp(`(^|\\s)"?${col}"? `), `${table}.${col} no esta en el DDL`);
    }
    for (const col of REQUIRED[table]) assert.ok(col in columns, `${table}.${col} requerida sin columna`);
  }
});

test('splitStatements: >= 20 statements, ninguno parte un $$, DO entero', () => {
  const stmts = splitStatements(schema);
  assert.ok(stmts.length >= 20, `solo ${stmts.length}`);
  for (const s of stmts) assert.equal((s.match(/\$\$/g) ?? []).length % 2, 0, s.slice(0, 60));
  const doBlocks = stmts.filter((s) => s.startsWith('DO $$'));
  assert.equal(doBlocks.length, 1);
  assert.match(doBlocks[0], /END LOOP;\s*END;\s*\$\$$/);
});
