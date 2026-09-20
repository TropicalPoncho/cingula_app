import 'dart:convert';

import 'package:sqflite/sqflite.dart';

const _syncTables = ['audio_assets', 'geo_paths', 'geo_triggers', 'regions'];
final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

Future<int> _count(DatabaseExecutor db, String sql) async =>
    Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;

/// Reporte previo a migrar v6 -> v7. SOLO LECTURA: no escribe nada.
Future<Map<String, Object?>> preflight(DatabaseExecutor db) async {
  final counts = <String, int>{};
  for (final t in [..._syncTables, 'sync_outbox']) {
    counts[t] = await _count(db, 'SELECT COUNT(*) FROM $t');
  }

  final nullUuid = <String, int>{};
  final nullUuidIds = <String, List<int>>{};
  final nullMetadata = <String, Map<String, int>>{};
  final softDeleted = <String, int>{};
  final duplicateUuids = <Map<String, Object?>>[];
  final invalidUuidFormat = <Map<String, Object?>>[];
  for (final t in _syncTables) {
    nullUuid[t] = await _count(db, 'SELECT COUNT(*) FROM $t WHERE uuid IS NULL');
    nullUuidIds[t] = (await db
            .rawQuery('SELECT id FROM $t WHERE uuid IS NULL LIMIT 50'))
        .map((r) => r['id'] as int)
        .toList();
    nullMetadata[t] = {
      'logical_version': await _count(
          db, 'SELECT COUNT(*) FROM $t WHERE logical_version IS NULL'),
      'updated_at':
          await _count(db, 'SELECT COUNT(*) FROM $t WHERE updated_at IS NULL'),
    };
    softDeleted[t] =
        await _count(db, 'SELECT COUNT(*) FROM $t WHERE deleted_at IS NOT NULL');
    for (final r in await db.rawQuery(
        'SELECT uuid, COUNT(*) AS c FROM $t WHERE uuid IS NOT NULL '
        'GROUP BY uuid HAVING COUNT(*) > 1')) {
      duplicateUuids.add({'table': t, 'uuid': r['uuid'], 'count': r['c']});
    }
    for (final r
        in await db.rawQuery('SELECT id, uuid FROM $t WHERE uuid IS NOT NULL')) {
      if (!_uuidRe.hasMatch(r['uuid'] as String)) {
        invalidUuidFormat.add({'table': t, 'id': r['id'], 'uuid': r['uuid']});
      }
    }
  }

  final orphanAudios = (await db.rawQuery(
          'SELECT id FROM audio_assets WHERE id NOT IN '
          '(SELECT audio_asset_id FROM geo_paths) AND id NOT IN '
          '(SELECT audio_asset_id FROM geo_triggers)'))
      .map((r) => r['id'] as int)
      .toList();

  final danglingPathRefs = (await db.rawQuery(
          'SELECT id, geo_path_id FROM geo_triggers WHERE geo_path_id IS NOT NULL '
          'AND geo_path_id NOT IN (SELECT id FROM geo_paths)'))
      .map((r) => {'triggerId': r['id'], 'geoPathId': r['geo_path_id']})
      .toList();

  Future<List<int>> danglingAudio(String t) async => (await db.rawQuery(
          'SELECT id FROM $t WHERE audio_asset_id NOT IN (SELECT id FROM audio_assets)'))
      .map((r) => r['id'] as int)
      .toList();

  final outboxByTableOp = <String, int>{};
  var outboxThinDeletes = 0;
  for (final r
      in await db.rawQuery('SELECT table_name, op, payload FROM sync_outbox')) {
    final k = '${r['table_name']}/${r['op']}';
    outboxByTableOp[k] = (outboxByTableOp[k] ?? 0) + 1;
    if (r['op'] == 'delete') {
      var hasId = false;
      try {
        final p = jsonDecode(r['payload'] as String? ?? '');
        hasId = p is Map && p.containsKey('id');
      } catch (_) {}
      if (!hasId) outboxThinDeletes++;
    }
  }

  final cursor =
      await db.rawQuery('SELECT server_cursor FROM sync_state LIMIT 1');

  return {
    'counts': counts,
    'nullUuid': nullUuid,
    'nullUuidIds': nullUuidIds,
    'duplicateUuids': duplicateUuids,
    'invalidUuidFormat': invalidUuidFormat,
    'nullMetadata': nullMetadata,
    'orphanAudios': orphanAudios,
    'standaloneTriggers': await _count(
        db, 'SELECT COUNT(*) FROM geo_triggers WHERE geo_path_id IS NULL'),
    'danglingPathRefs': danglingPathRefs,
    'danglingAudioRefsTriggers': await danglingAudio('geo_triggers'),
    'danglingAudioRefsPaths': await danglingAudio('geo_paths'),
    // Informativo: el monitor usa SIEMPRE el audio del path cuando hay geo_path_id.
    'triggerAudioDiffersFromPath': await _count(
        db,
        'SELECT COUNT(*) FROM geo_triggers t JOIN geo_paths p ON p.id = t.geo_path_id '
        'WHERE t.audio_asset_id != p.audio_asset_id'),
    'softDeleted': softDeleted,
    'outboxByTableOp': outboxByTableOp,
    'outboxThinDeletes': outboxThinDeletes,
    'assetPathAudios': await _count(
        db, "SELECT COUNT(*) FROM audio_assets WHERE local_path LIKE 'assets/%'"),
    // points solo sobrevive en legacy_geo_paths: mirar esto en el go/no-go de 02.1-04.
    'pathsWithPoints': await _count(
        db,
        "SELECT COUNT(*) FROM geo_paths WHERE points IS NOT NULL AND points NOT IN ('', '[]')"),
    'syncStateCursor': cursor.isEmpty ? null : cursor.first['server_cursor'],
    'userVersion': await _count(db, 'PRAGMA user_version'),
  };
}

String formatPreflight(Map<String, Object?> report) =>
    report.entries.map((e) => '${e.key}: ${e.value}').join('\n');
