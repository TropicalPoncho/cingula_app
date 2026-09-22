import 'dart:convert';

import 'package:cingula_app/data/datasources/local/audio_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/geo_path_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/geo_trigger_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/obra_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/sync_local_data_source.dart';
import 'package:cingula_app/data/migration/v7_schema.dart';
import 'package:cingula_app/data/repositories/geo_path_repository_impl.dart';
import 'package:cingula_app/data/repositories/obra_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite, inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Columnas que backend/api/_lib/spec.js acepta por tabla (TABLE_SPEC). Copiadas a
/// mano porque el test no puede leer JS: si spec.js cambia, este mapa hay que
/// actualizarlo a mano también.
const _specColumns = {
  'audios': {
    'uuid', 'kind', 'title', 'description', 'duration_seconds',
    'storage_key', 'checksum', 'logical_version', 'updated_at', 'deleted_at',
  },
  'obras': {
    'uuid', 'name', 'owner_id', 'visibility', 'share_token',
    'cover_lat', 'cover_lon', 'cover_min_lat', 'cover_max_lat',
    'cover_min_lon', 'cover_max_lon', 'logical_version', 'updated_at', 'deleted_at',
  },
  'paths': {
    'uuid', 'obra_uuid', 'kind', 'name', 'audio_uuid', 'grabacion_uuid',
    'tolerance_meters', 'logical_version', 'updated_at', 'deleted_at',
  },
  'triggers': {
    'uuid', 'path_uuid', 'position', 'name', 'description', 'latitude',
    'longitude', 'radius_meters', 'offset_ms', 'logical_version', 'updated_at', 'deleted_at',
  },
};

// sync_outbox/sync_state no cambian de forma en este plan (no son parte del
// esquema nuevo de v7_schema.dart): AppDatabase._onCreate (Task 3) las sigue
// creando directamente con este mismo DDL, ya existente desde antes de v7.
Future<void> _createSyncTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE sync_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      record_uuid TEXT NOT NULL,
      op TEXT NOT NULL,
      payload TEXT,
      device_id TEXT,
      created_at INTEGER NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at INTEGER
    );
  ''');
  await db.execute('''
    CREATE TABLE sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      server_cursor TEXT,
      last_sync_at INTEGER,
      device_id TEXT
    );
  ''');
}

Future<Database> _openV7() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 7,
      onCreate: (db, _) async {
        await createV7Tables(db);
        await _createSyncTables(db);
      },
    ),
  );
}

Future<int> _outboxCount(Database db) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_outbox')) ?? 0;

Future<List<Map<String, Object?>>> _outboxPayloadsFor(Database db, String table) async {
  final rows = await db.query('sync_outbox', where: 'table_name = ?', whereArgs: [table]);
  return rows.map((r) => jsonDecode(r['payload'] as String) as Map<String, Object?>).toList();
}

Map<String, Object?> _triggerValues(String pathUuid, {String name = 'T'}) => {
      'path_uuid': pathUuid,
      'name': name,
      'description': '',
      'latitude': -42.1,
      'longitude': -71.6,
      'radius_meters': 10.0,
    };

void main() {
  late Database db;
  late SyncLocalDataSource sync;

  setUp(() async {
    db = await _openV7();
    sync = SyncLocalDataSource(db);
  });

  tearDown(() => db.close());

  test('saveProgress escribe path_progress y no toca el outbox (MODEL-04)', () async {
    final obras = ObraLocalDataSource(db, sync);
    final paths = GeoPathLocalDataSource(db, sync);
    final obraUuid = await obras.createDraft('Obra x');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path x'});

    final before = await _outboxCount(db);
    await paths.saveProgress(pathUuid, 12000);
    final after = await _outboxCount(db);

    expect(after, before);
    final progress =
        (await db.query('path_progress', where: 'path_uuid = ?', whereArgs: [pathUuid])).single;
    expect(progress['saved_offset_ms'], 12000);
  });

  test('insertRecording crea audios+audio_local y encola una sola fila de audios sin local_path/remote_url', () async {
    final audios = AudioLocalDataSource(db, sync);
    final uuid = await audios.insertRecording(
      title: 'Grabación',
      description: 'desc',
      localPath: '/tmp/a.m4a',
      duration: const Duration(seconds: 30),
    );

    expect(await db.query('audios', where: 'uuid = ?', whereArgs: [uuid]), hasLength(1));
    expect(await db.query('audio_local', where: 'audio_uuid = ?', whereArgs: [uuid]), hasLength(1));

    final payloads = await _outboxPayloadsFor(db, 'audios');
    expect(payloads, hasLength(1));
    expect(payloads.single.containsKey('local_path'), isFalse);
    expect(payloads.single.containsKey('remote_url'), isFalse);
  });

  test('insertTrigger encola triggers con path_uuid, sin audio_asset_id/geo_path_id; position autoincrementa', () async {
    final obras = ObraLocalDataSource(db, sync);
    final paths = GeoPathLocalDataSource(db, sync);
    final triggers = GeoTriggerLocalDataSource(db, sync);
    final obraUuid = await obras.createDraft('Obra t');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path t'});

    final firstUuid = await triggers.insertTrigger(_triggerValues(pathUuid, name: 'T1'));
    final secondUuid = await triggers.insertTrigger(_triggerValues(pathUuid, name: 'T2'));

    final rows = await db.query('triggers', orderBy: 'position');
    expect(rows[0]['uuid'], firstUuid);
    expect(rows[0]['position'], 0);
    expect(rows[1]['uuid'], secondUuid);
    expect(rows[1]['position'], 1);

    final payloads = await _outboxPayloadsFor(db, 'triggers');
    expect(payloads, hasLength(2));
    for (final p in payloads) {
      expect(p.containsKey('path_uuid'), isTrue);
      expect(p.containsKey('audio_asset_id'), isFalse);
      expect(p.containsKey('geo_path_id'), isFalse);
    }
  });

  test('ObraLocalDataSource.createDraft crea obra draft y encola obras', () async {
    final obras = ObraLocalDataSource(db, sync);
    final uuid = await obras.createDraft('x');

    final row = (await db.query('obras', where: 'uuid = ?', whereArgs: [uuid])).single;
    expect(row['visibility'], 'draft');

    expect(await _outboxPayloadsFor(db, 'obras'), hasLength(1));
  });

  test('GeoPathRepositoryImpl.createPath sin obraUuid crea una obra draft con el nombre del path (D-22)', () async {
    final obraRepo = ObraRepositoryImpl(localDataSource: ObraLocalDataSource(db, sync));
    final pathRepo = GeoPathRepositoryImpl(
      localDataSource: GeoPathLocalDataSource(db, sync),
      obraRepository: obraRepo,
    );

    final pathUuid = await pathRepo.createPath(name: 'y');

    final pathRow = (await db.query('paths', where: 'uuid = ?', whereArgs: [pathUuid])).single;
    final obraUuid = pathRow['obra_uuid'] as String;
    final obraRow = (await db.query('obras', where: 'uuid = ?', whereArgs: [obraUuid])).single;
    expect(obraRow['name'], 'y');
    expect(obraRow['visibility'], 'draft');
  });

  test('deleteByUuid borra path, triggers y path_progress; encola deletes sin path_progress', () async {
    final obras = ObraLocalDataSource(db, sync);
    final paths = GeoPathLocalDataSource(db, sync);
    final triggers = GeoTriggerLocalDataSource(db, sync);
    final obraUuid = await obras.createDraft('Obra d');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path d'});
    await triggers.insertTrigger(_triggerValues(pathUuid));
    await paths.saveProgress(pathUuid, 5000);

    await db.delete('sync_outbox'); // limpiar el ruido de los inserts de fixture

    final deleted = await paths.deleteByUuid(pathUuid);

    expect(deleted, 2); // 1 path + 1 trigger
    expect(await db.query('paths', where: 'uuid = ?', whereArgs: [pathUuid]), isEmpty);
    expect(await db.query('triggers', where: 'path_uuid = ?', whereArgs: [pathUuid]), isEmpty);
    expect(await db.query('path_progress', where: 'path_uuid = ?', whereArgs: [pathUuid]), isEmpty);

    final deleteRows = await db.query('sync_outbox', where: "op = 'delete'");
    expect(deleteRows.map((r) => r['table_name']), containsAll(['paths', 'triggers']));
    expect(deleteRows.where((r) => r['table_name'] == 'path_progress'), isEmpty);
  });

  test('todo payload encolado usa solo columnas que backend/api/_lib/spec.js acepta para esa tabla', () async {
    final audios = AudioLocalDataSource(db, sync);
    final obras = ObraLocalDataSource(db, sync);
    final paths = GeoPathLocalDataSource(db, sync);
    final triggers = GeoTriggerLocalDataSource(db, sync);

    final audioUuid = await audios.insertRecording(
      title: 'a',
      description: '',
      localPath: '/tmp/a.m4a',
      duration: const Duration(seconds: 1),
    );
    final obraUuid = await obras.createDraft('o');
    final pathUuid =
        await paths.insertPath({'obra_uuid': obraUuid, 'name': 'p', 'audio_uuid': audioUuid});
    await triggers.insertTrigger(_triggerValues(pathUuid, name: 't'));

    final rows = await db.query('sync_outbox');
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final table = row['table_name'] as String;
      final allowed = _specColumns[table];
      expect(allowed, isNotNull, reason: 'tabla $table sin columnas conocidas en el test');
      final payload = jsonDecode(row['payload'] as String) as Map<String, Object?>;
      for (final key in payload.keys) {
        expect(allowed!.contains(key), isTrue, reason: '$table.$key no está en spec.js');
      }
    }
  });
}
