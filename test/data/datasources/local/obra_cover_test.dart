import 'package:cingula_app/data/datasources/local/geo_path_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/geo_trigger_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/obra_local_data_source.dart';
import 'package:cingula_app/data/datasources/local/sync_local_data_source.dart';
import 'package:cingula_app/data/migration/cover.dart';
import 'package:cingula_app/data/migration/v7_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite, inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// sync_outbox/sync_state no cambian de forma en este plan: mismo DDL que
// local_data_sources_test.dart, copiado porque un test no debe depender de otro.
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

Map<String, Object?> _triggerValues(String pathUuid, {required double lat, required double lon}) => {
      'path_uuid': pathUuid,
      'name': 'T',
      'description': '',
      'latitude': lat,
      'longitude': lon,
      'radius_meters': 10.0,
    };

void main() {
  late Database db;
  late SyncLocalDataSource sync;
  late ObraLocalDataSource obras;
  late GeoPathLocalDataSource paths;
  late GeoTriggerLocalDataSource triggers;

  setUp(() async {
    db = await _openV7();
    sync = SyncLocalDataSource(db);
    obras = ObraLocalDataSource(db, sync);
    paths = GeoPathLocalDataSource(db, sync);
    // Wireado igual que service_locator.dart: insertar/borrar triggers recalcula sola la cobertura.
    triggers = GeoTriggerLocalDataSource(db, sync, onObraTouched: obras.refreshCover);
  });

  tearDown(() => db.close());

  test('insertar el primer trigger deja la cobertura igual a ese punto', () async {
    final obraUuid = await obras.createDraft('Obra 1');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path 1'});

    await triggers.insertTrigger(_triggerValues(pathUuid, lat: -42.1, lon: -71.6));

    final obra = await obras.findByUuid(obraUuid);
    expect(obra!.coverLat, -42.1);
    expect(obra.coverLon, -71.6);
    expect(obra.coverMinLat, -42.1);
    expect(obra.coverMaxLat, -42.1);
    expect(obra.coverMinLon, -71.6);
    expect(obra.coverMaxLon, -71.6);
  });

  test('un segundo trigger expande la caja y mueve el centro a la media', () async {
    final obraUuid = await obras.createDraft('Obra 2');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path 2'});

    await triggers.insertTrigger(_triggerValues(pathUuid, lat: -42.0, lon: -71.0));
    await triggers.insertTrigger(_triggerValues(pathUuid, lat: -42.2, lon: -71.4));

    final obra = await obras.findByUuid(obraUuid);
    final expected = computeCover(const [(lat: -42.0, lon: -71.0), (lat: -42.2, lon: -71.4)]);
    expect(obra!.coverLat, expected.centerLat);
    expect(obra.coverLon, expected.centerLon);
    expect(obra.coverMinLat, expected.minLat);
    expect(obra.coverMaxLat, expected.maxLat);
    expect(obra.coverMinLon, expected.minLon);
    expect(obra.coverMaxLon, expected.maxLon);
  });

  test('borrar todos los triggers de la obra deja las seis columnas en NULL', () async {
    final obraUuid = await obras.createDraft('Obra 3');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path 3'});
    await triggers.insertTrigger(_triggerValues(pathUuid, lat: -42.0, lon: -71.0));

    await triggers.deleteByPathUuid(pathUuid);

    final obra = await obras.findByUuid(obraUuid);
    expect(obra!.coverLat, isNull);
    expect(obra.coverLon, isNull);
    expect(obra.coverMinLat, isNull);
    expect(obra.coverMaxLat, isNull);
    expect(obra.coverMinLon, isNull);
    expect(obra.coverMaxLon, isNull);
  });

  test('un recálculo que da el mismo resultado no bumpea logical_version ni agrega outbox', () async {
    final obraUuid = await obras.createDraft('Obra 4');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path 4'});
    await triggers.insertTrigger(_triggerValues(pathUuid, lat: -42.0, lon: -71.0));

    final before = await obras.findByUuid(obraUuid);
    final outboxBefore = await _outboxCount(db);

    await obras.refreshCover(obraUuid);

    final after = await obras.findByUuid(obraUuid);
    final outboxAfter = await _outboxCount(db);

    expect(after!.logicalVersion, before!.logicalVersion);
    expect(outboxAfter, outboxBefore);
  });

  test('un recálculo que cambia algo bumpea logical_version y encola UN update de obras', () async {
    final obraUuid = await obras.createDraft('Obra 5');
    final pathUuid = await paths.insertPath({'obra_uuid': obraUuid, 'name': 'Path 5'});
    await triggers.insertTrigger(_triggerValues(pathUuid, lat: -42.0, lon: -71.0));

    final before = await obras.findByUuid(obraUuid);
    await db.delete('sync_outbox'); // limpiar ruido de los inserts de fixture

    // Insertar un segundo trigger directo por SQL (sin pasar por GeoTriggerLocalDataSource)
    // para poder llamar a refreshCover de forma aislada y verificar que detecta el cambio.
    await db.insert('triggers', {
      'uuid': 'trigger-directo',
      'path_uuid': pathUuid,
      'position': 1,
      'name': 'directo',
      'description': '',
      'latitude': -42.5,
      'longitude': -71.9,
      'radius_meters': 10.0,
      'offset_ms': 0,
      'updated_at': 0,
      'logical_version': 1,
    });

    await obras.refreshCover(obraUuid);

    final after = await obras.findByUuid(obraUuid);
    expect(after!.logicalVersion, (before!.logicalVersion ?? 1) + 1);

    final updateRows = await db.query('sync_outbox', where: "table_name = 'obras' AND op = 'update'");
    expect(updateRows, hasLength(1));
  });
}
