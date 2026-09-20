import 'dart:io';

import 'package:cingula_app/data/migration/ids.dart';
import 'package:cingula_app/data/migration/v7_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/v6_fixture.dart';

Future<String> _seed(Future<void> Function(Database db)? extra) async {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('cg7');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/v6.db';
  final db = await openV6(path);
  await seedSynthetic(db);
  if (extra != null) await extra(db);
  await db.close();
  return path;
}

Future<Database> _upgrade(String path,
    {Future<void> Function(DatabaseExecutor)? hook,
    void Function(Map<String, Object?>)? onReport}) {
  return databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(
          version: 7,
          onUpgrade: (d, o, n) async {
            if (o < 7) {
              final r = await migrateToV7(d, onBeforeVerify: hook);
              onReport?.call(r);
            }
          }));
}

Future<int> _n(Database db, String t, [String where = '']) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t $where'))!;

/// La base sigue en v6, con las tablas viejas completas y sin tablas nuevas.
Future<void> _expectRolledBack(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), 6);
  expect(await _n(db, 'audio_assets'), 77);
  expect(await _n(db, 'geo_paths'), 70);
  expect(await _n(db, 'geo_triggers'), 459);
  expect(await _n(db, 'regions'), 20);
  expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name='obras'"),
      isEmpty);
  await db.close();
}

void main() {
  test('base v6 sintetica migra a v7 con todos los datos', () async {
    final path = await _seed(null);
    late Map<String, Object?> report;
    final db = await _upgrade(path, onReport: (r) => report = r);
    expect(await db.getVersion(), 7);
    expect(await _n(db, 'audios'), 77);
    expect(await _n(db, 'paths'), 85);
    expect(await _n(db, 'paths', "WHERE kind='route'"), 70);
    expect(await _n(db, 'paths', "WHERE kind='portal'"), 15);
    expect(await _n(db, 'obras'), 85);
    expect(await _n(db, 'triggers'), 459);
    expect(await _n(db, 'audio_local'), 77);
    expect(await _n(db, 'path_progress'), 70);
    expect(await _n(db, 'path_progress', 'WHERE saved_offset_ms > 0'), 6);
    // tablas viejas intactas
    expect(await _n(db, 'audio_assets'), 77);
    expect(await _n(db, 'geo_paths'), 70);
    expect(await _n(db, 'geo_triggers'), 459);
    expect(await _n(db, 'regions'), 20);
    expect(report['portalsFromDangling'], 0);
    // ruta de asset intacta
    expect(await _n(db, 'audio_local', "WHERE local_path LIKE 'assets/%'"), 3);
    // position: cada path arranca en 0 y no se repite
    expect(
        await _n(db, '(SELECT path_uuid FROM triggers GROUP BY path_uuid '
            'HAVING MIN(position) != 0 OR COUNT(*) != COUNT(DISTINCT position))'),
        0);
    // obras con triggers tienen cobertura
    expect(await _n(db, 'obras', 'WHERE cover_lat IS NULL'), 0);
    // ids deterministicos
    final p = (await db.query('paths', where: "kind='route'", limit: 1)).first;
    expect(p['obra_uuid'], obraUuidForPath(p['uuid'] as String));
    await db.close();
  });

  test('dos corridas sobre copias iguales dan los mismos uuid de obra', () async {
    Future<List<String>> run() async {
      final db = await _upgrade(await _seed(null));
      final r = await db.rawQuery('SELECT uuid FROM obras ORDER BY name, uuid');
      await db.close();
      return r.map((e) => e['uuid'] as String).toList();
    }

    // Los uuid de path dependen del uuid legacy (mismo seed) o v4 (2 audios sin uuid
    // no afectan paths): las obras/portales salen iguales.
    expect(await run(), await run());
  });

  test('uuid duplicado: excepcion cruda de SQLite y rollback a v6', () async {
    final path = await _seed(addDuplicateUuid);
    // 460 triggers en vez de 459: el rollback se chequea con el conteo base
    await expectLater(_upgrade(path), throwsA(anything));
    final db = await databaseFactoryFfi.openDatabase(path);
    expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), 6);
    expect(await _n(db, 'geo_triggers'), 460);
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name='obras'"),
        isEmpty);
    await db.close();
  });

  test('discrepancia forzada: MigrationException y rollback', () async {
    final path = await _seed(null);
    await expectLater(
        _upgrade(path, hook: (d) => d.execute('DELETE FROM triggers WHERE rowid = 1')),
        throwsA(isA<MigrationException>()));
    await _expectRolledBack(path);
  });

  test('path colgante: el trigger termina como portal', () async {
    final path = await _seed(addDanglingPathRef);
    late Map<String, Object?> report;
    final db = await _upgrade(path, onReport: (r) => report = r);
    expect(report['portalsFromDangling'], 1);
    expect(await _n(db, 'triggers'), 460);
    expect(await _n(db, 'paths', "WHERE kind='portal'"), 16);
    final t = (await db.query('triggers',
            where: 'uuid = ?', whereArgs: ['00000000-0000-4000-8000-000000009002']))
        .single;
    expect(t['path_uuid'],
        portalUuidForTrigger('00000000-0000-4000-8000-000000009002'));
    await db.close();
  });

  test('audio colgante: path con audio_uuid NULL, sin fallar', () async {
    final path = await _seed(addDanglingAudioRef);
    final db = await _upgrade(path);
    final r = await db.query('paths',
        where: 'uuid = ?', whereArgs: ['00000000-0000-4000-8000-000000009003']);
    expect(r.single['audio_uuid'], isNull);
    await db.close();
  });

  test('uuid con formato invalido recibe uuid v4 nuevo y no se pierde', () async {
    final path = await _seed((db) =>
        db.update('audio_assets', {'uuid': 'no-es-un-uuid'}, where: 'id = 30'));
    final db = await _upgrade(path);
    expect(await _n(db, 'audios'), 77);
    expect(await _n(db, 'audios', "WHERE uuid = 'no-es-un-uuid'"), 0);
    await db.close();
  });

  // MODEL-08: nunca se corre contra el celular; recibe la ruta de una COPIA ya
  // extraida a la PC.
  final real = Platform.environment['CINGULA_REAL_DB'];
  test('copia real de la base', () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('cg7real');
    addTearDown(() => dir.deleteSync(recursive: true));
    final copy = File(real!).copySync('${dir.path}/real.db');
    final db = await _upgrade(copy.path);
    expect(await db.getVersion(), 7);
    await db.close();
  }, skip: real == null ? 'requiere CINGULA_REAL_DB' : false);
}
