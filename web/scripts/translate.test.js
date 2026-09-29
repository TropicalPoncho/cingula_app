import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildIdMap, translate } from './translate.js';
import { TABLE_SPEC } from '../api/_lib/spec.js';

const rows = JSON.parse(readFileSync(new URL('./fixture.json', import.meta.url), 'utf8'));
// Par (tabla, id) con dos uuid distintos: SOLO para el test de ambiguedad.
const dup = {
  table_name: 'audio_assets', record_uuid: 'a0000000-0000-4000-8000-0000000000ff', op: 'insert',
  current_version: 1, current_updated_at: '2026-01-01T00:00:00Z',
  current_payload: { id: 1, uuid: 'a0000000-0000-4000-8000-0000000000ff', title: 'dup', logical_version: 1, updated_at: 1 },
};
const ambiguousRows = [...rows, dup];
const VECTOR_OBRA = 'b2d73103-b352-5e06-a226-a632610b0402';

test('buildIdMap resuelve ids y usa previous para tombstones', () => {
  const { map, ambiguous } = buildIdMap(rows);
  assert.equal(ambiguous.length, 0);
  assert.equal(map.get('audio_assets:1'), 'a0000000-0000-4000-8000-000000000001');
  assert.equal(map.get('geo_paths:2'), '11111111-2222-4333-8444-666666666666');
});

test('ambiguedad: buildIdMap la reporta y translate aborta nombrando el caso', () => {
  const { ambiguous } = buildIdMap(ambiguousRows);
  assert.equal(ambiguous.length, 1);
  assert.equal(ambiguous[0].table, 'audio_assets');
  assert.throws(() => translate(ambiguousRows), /audio_assets:1/);
});

test('ambiguedad sin override para esa clave: sigue abortando aunque haya overrides de otras claves', () => {
  assert.throws(() => translate(ambiguousRows, { 'geo_paths:99': 'x' }), /audio_assets:1/);
});

test('ambiguedad con override: resuelve y reporta los uuid descartados en skipped', () => {
  const overrides = { 'audio_assets:1': 'a0000000-0000-4000-8000-000000000001' };
  const { ambiguous, resolved } = buildIdMap(ambiguousRows, overrides);
  assert.equal(ambiguous.length, 0);
  assert.equal(resolved.length, 1);
  assert.deepEqual(resolved[0].discarded, ['a0000000-0000-4000-8000-0000000000ff']);
  const { tables, skipped } = translate(ambiguousRows, overrides);
  assert.ok(tables.audios.some((a) => a.uuid === 'a0000000-0000-4000-8000-000000000001'));
  const s = skipped.find((x) => x.record_uuid === 'a0000000-0000-4000-8000-0000000000ff');
  assert.ok(s, 'uuid descartado listado en skipped');
  assert.equal(s.table_name, 'audio_assets');
  assert.match(s.reason, /audio_assets:1/);
});

test('conteos y uuid de obra compartido con el celular', () => {
  const { tables, counts } = translate(rows);
  assert.equal(tables.audios.length, 3);
  assert.equal(tables.triggers.length, 4); // el delete fino se omite
  assert.equal(tables.paths.length, 4); // 2 route + 2 portales
  assert.equal(tables.obras.length, 4);
  assert.equal(counts.target.paths, 4);
  const obra = tables.obras.find((o) => o.uuid === VECTOR_OBRA);
  assert.ok(obra, 'obra del vector compartido');
  assert.equal(obra.visibility, 'draft');
});

test('posicion por (offset_ms, id) y cobertura', () => {
  const { tables } = translate(rows);
  const t = (u) => tables.triggers.find((x) => x.uuid.endsWith(u));
  assert.equal(t('000000000002').position, 0);
  assert.equal(t('000000000001').position, 1);
  const obra = tables.obras.find((o) => o.uuid === VECTOR_OBRA);
  assert.equal(obra.cover_min_lat, -42.2);
  assert.equal(obra.cover_max_lat, -42.1);
});

test('tombstone con previous se reconstruye; delete fino a skipped; regions no produce', () => {
  const { tables, skipped } = translate(rows);
  const p = tables.paths.find((x) => x.uuid === '11111111-2222-4333-8444-666666666666');
  assert.equal(p.logical_version, 3);
  assert.equal(p.deleted_at, Math.floor(Date.parse('2026-01-05T00:00:00Z') / 1000));
  assert.equal(skipped.length, 1);
  assert.match(skipped[0].reason, /previous/);
  assert.ok(!JSON.stringify(tables).includes('99999999-0000'));
});

test('logical_version nulo -> 1 con advertencia; audio del trigger suelto resuelto', () => {
  const { tables, warnings } = translate(rows);
  assert.equal(tables.audios.find((a) => a.uuid.endsWith('03')).logical_version, 1);
  assert.ok(warnings.some((w) => /logical_version nulo/.test(w)));
  const portal = tables.paths.find((x) => x.kind === 'portal' && x.audio_uuid);
  assert.equal(portal.audio_uuid, 'a0000000-0000-4000-8000-000000000003');
});

test('columnas NOT NULL DEFAULT en schema.sql: null explicito se completa con el default, no rompe el insert', () => {
  const { tables } = translate(rows);
  // Rec 3 (fixture) no manda description ni duration_seconds.
  const rec3 = tables.audios.find((a) => a.uuid.endsWith('03'));
  assert.equal(rec3.description, '');
  assert.equal(rec3.duration_seconds, 0);
  const noTolerance = {
    table_name: 'geo_paths', record_uuid: 'dddddddd-0000-4000-8000-000000000001', op: 'insert',
    current_version: 1, current_updated_at: '2026-01-01T00:00:00Z',
    current_payload: { id: 60, uuid: 'dddddddd-0000-4000-8000-000000000001', name: 'Sin tolerancia', logical_version: 1, updated_at: 1 },
  };
  const { tables: t2 } = translate([...rows, noTolerance]);
  const p = t2.paths.find((x) => x.uuid === 'dddddddd-0000-4000-8000-000000000001');
  assert.equal(p.tolerance_meters, 10.0);
});

test('content override: completa title/name faltante', () => {
  const noName = {
    table_name: 'geo_paths', record_uuid: 'cccccccc-0000-4000-8000-000000000001', op: 'insert',
    current_version: 1, current_updated_at: '2026-01-01T00:00:00Z',
    current_payload: { id: 50, uuid: 'cccccccc-0000-4000-8000-000000000001', tolerance_meters: 5, logical_version: 1, updated_at: 1 },
  };
  const rowsWithGap = [...rows, noName];
  const overrides2 = { 'cccccccc-0000-4000-8000-000000000001': 'Nombre real' };
  const { tables, warnings } = translate(rowsWithGap, {}, overrides2);
  const p = tables.paths.find((x) => x.uuid === 'cccccccc-0000-4000-8000-000000000001');
  assert.equal(p.name, 'Nombre real');
  assert.ok(!warnings.some((w) => /content override/.test(w)));
});

test('content override: NO pisa un title/name que ya existe, y avisa', () => {
  const contentOverrides = { 'a0000000-0000-4000-8000-000000000001': 'Otro titulo' };
  const { tables, warnings } = translate(rows, {}, contentOverrides);
  const a = tables.audios.find((x) => x.uuid === 'a0000000-0000-4000-8000-000000000001');
  assert.equal(a.title, 'Rec 1'); // valor original del fixture, sin pisar
  assert.ok(warnings.some((w) => /content override.*ignorado/.test(w) && w.includes('a0000000-0000-4000-8000-000000000001')));
});

test('sin content override para una fila con title/name faltante: sigue fallando validacion (fail-safe sin cambios)', () => {
  const noName = {
    table_name: 'geo_paths', record_uuid: 'cccccccc-0000-4000-8000-000000000002', op: 'insert',
    current_version: 1, current_updated_at: '2026-01-01T00:00:00Z',
    current_payload: { id: 51, uuid: 'cccccccc-0000-4000-8000-000000000002', tolerance_meters: 5, logical_version: 1, updated_at: 1 },
  };
  const { tables } = translate([...rows, noName]);
  const p = tables.paths.find((x) => x.uuid === 'cccccccc-0000-4000-8000-000000000002');
  assert.equal(p.name, null); // no hay override: sigue nulo, la validacion de outbox lo rechaza aguas abajo
});

test('no filtra columnas locales', () => {
  const { tables } = translate(rows);
  for (const [t, list] of Object.entries(tables)) {
    for (const row of list) {
      assert.deepEqual(Object.keys(row).sort(), Object.keys(TABLE_SPEC[t].columns).sort());
      for (const k of ['id', 'region_id', 'saved_offset_ms', 'local_path', 'remote_url', 'artist', 'points']) {
        assert.ok(!(k in row), `${t} tiene ${k}`);
      }
    }
  }
});
