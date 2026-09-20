import 'dart:io';

import 'package:cingula_app/data/migration/preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../../support/v6_fixture.dart';

void main() {
  late Database db;
  late Directory dir;

  setUp(() async => (db, dir) = await openSeededV6Temp());
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('dataset limpio', () async {
    final r = await preflight(db);
    final counts = r['counts'] as Map;
    expect(counts['audio_assets'], 77);
    expect(counts['geo_paths'], 70);
    expect(counts['geo_triggers'], 459);
    expect(counts['regions'], 20);
    expect((r['nullUuid'] as Map)['audio_assets'], 2);
    expect(r['duplicateUuids'], isEmpty);
    expect(r['danglingPathRefs'], isEmpty);
    expect((r['orphanAudios'] as List).length, 4);
    expect(r['standaloneTriggers'], 15);
    expect((r['outboxByTableOp'] as Map)['regions/delete'], 1);
    expect(r['outboxThinDeletes'], 1);
    expect(r['assetPathAudios'], 3);
    expect(r['triggerAudioDiffersFromPath'], 3);
    expect(r['pathsWithPoints'], 0);
    expect(r['syncStateCursor'], '2026-09-16T03:12:44.000Z');
    expect(formatPreflight(r), contains('pathsWithPoints: 0'));
  });

  test('paths con points', () async {
    await db.update('geo_paths', {'points': '[[1,2]]'}, where: 'id = 1');
    expect((await preflight(db))['pathsWithPoints'], 1);
  });

  test('casos borde', () async {
    await addDuplicateUuid(db);
    await addDanglingPathRef(db);
    await addDanglingAudioRef(db);
    await addInvalidUuidFormat(db);
    final r = await preflight(db);
    expect((r['duplicateUuids'] as List).length, 1);
    expect((r['danglingPathRefs'] as List).single,
        {'triggerId': 9002, 'geoPathId': 99999});
    expect(r['danglingAudioRefsPaths'], [9003]);
    expect((r['invalidUuidFormat'] as List).length, 1);
  });

  test('no escribe nada', () async {
    Future<List<Object?>> snap() async => [
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          for (final t in ['audio_assets', 'geo_paths', 'geo_triggers', 'regions'])
            Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')),
        ];
    final before = await snap();
    await preflight(db);
    expect(await snap(), before);
  });
}
