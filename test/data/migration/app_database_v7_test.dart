import 'dart:io';

import 'package:cingula_app/data/datasources/local/app_database.dart';
import 'package:cingula_app/data/migration/v7_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/v6_fixture.dart';

Future<int> _n(Database db, String table, [String where = '']) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table $where'))!;

bool _hasCorruptoFile(Directory dir) =>
    dir.listSync().any((f) => f.path.contains('.corrupto-'));

bool _hasPreV7Backup(Directory dir) =>
    dir.listSync().any((f) => f.path.contains('.pre-v7-'));

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('init() sobre una base v6 sembrada migra a v7, respalda antes y deja lastBackupPath', () async {
    final dir = Directory.systemTemp.createTempSync('cg7_migrate_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v6.db';
    final seedDb = await openV6(path);
    await seedSynthetic(seedDb);
    await seedDb.close();

    final appDb = AppDatabase();
    await appDb.init(dbPath: path, factory: databaseFactoryFfi);

    expect(await appDb.database.getVersion(), 7);
    expect(await _n(appDb.database, 'audios'), 77);
    expect(await _n(appDb.database, 'triggers'), 459);
    expect(appDb.lastBackupPath, isNotNull);
    expect(File(appDb.lastBackupPath!).existsSync(), isTrue);
    expect(_hasPreV7Backup(dir), isTrue);
    await appDb.database.close();
  });

  test('D-25 discrepancia: init() lanza MigrationException, NO renombra, la base sana sigue en v6', () async {
    final dir = Directory.systemTemp.createTempSync('cg7_discrepancy_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v6.db';
    final seedDb = await openV6(path);
    await seedSynthetic(seedDb);
    await seedDb.close();

    final appDb = AppDatabase();
    // Reusa el mismo hook @visibleForTesting que expone migrateToV7 para forzar
    // una discrepancia de verificación (no un error crudo de SQL).
    appDb.debugOnBeforeVerifyV7 = (d) => d.execute('DELETE FROM triggers WHERE rowid = 1');

    await expectLater(
      () => appDb.init(dbPath: path, factory: databaseFactoryFfi),
      throwsA(isA<MigrationException>()),
    );

    expect(_hasCorruptoFile(dir), isFalse);

    final reopened = await databaseFactoryFfi.openDatabase(path); // sin version: no migra
    expect(await reopened.getVersion(), 6);
    expect(await _n(reopened, 'audio_assets'), 77);
    expect(await _n(reopened, 'geo_paths'), 70);
    expect(await _n(reopened, 'geo_triggers'), 459);
    expect(await _n(reopened, 'regions'), 20);
    await reopened.close();
  });

  test('D-25 error crudo de SQL: init() igual lanza MigrationException con cause, NO renombra', () async {
    final dir = Directory.systemTemp.createTempSync('cg7_raw_error_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v6.db';
    final seedDb = await openV6(path);
    await seedSynthetic(seedDb);
    await addDuplicateUuid(seedDb); // choca contra la PK de `triggers` en la migración
    await seedDb.close();

    final appDb = AppDatabase();

    Object? caught;
    try {
      await appDb.init(dbPath: path, factory: databaseFactoryFfi);
    } catch (e) {
      caught = e;
    }

    expect(caught, isA<MigrationException>());
    expect((caught as MigrationException).cause, isNotNull);
    expect(_hasCorruptoFile(dir), isFalse);

    final reopened = await databaseFactoryFfi.openDatabase(path); // sin version: no migra
    expect(await reopened.getVersion(), 6);
    // 459 originales + la fila duplicada que addDuplicateUuid agregó a mano.
    expect(await _n(reopened, 'geo_triggers'), 460);
    await reopened.close();
  });

  test('instalación limpia crea v7 directo, siembra, no migra y no deja respaldo', () async {
    final dir = Directory.systemTemp.createTempSync('cg7_clean_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/clean.db';

    final appDb = AppDatabase();
    await appDb.init(dbPath: path, factory: databaseFactoryFfi);

    expect(await appDb.database.getVersion(), 7);
    expect(await _n(appDb.database, 'audios'), 2);
    expect(await _n(appDb.database, 'obras'), 1);
    expect(await _n(appDb.database, 'paths'), 1);
    expect(await _n(appDb.database, 'triggers'), 1);
    expect(appDb.lastBackupPath, isNull);
    await appDb.database.close();
  });

  test('abrir dos veces la misma base ya migrada no vuelve a respaldar ni a migrar', () async {
    final dir = Directory.systemTemp.createTempSync('cg7_reopen_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v6.db';
    final seedDb = await openV6(path);
    await seedSynthetic(seedDb);
    await seedDb.close();

    final first = AppDatabase();
    await first.init(dbPath: path, factory: databaseFactoryFfi);
    expect(first.lastBackupPath, isNotNull);
    await first.database.close();

    final second = AppDatabase();
    await second.init(dbPath: path, factory: databaseFactoryFfi);
    expect(await second.database.getVersion(), 7);
    expect(second.lastBackupPath, isNull);
    expect(await _n(second.database, 'audios'), 77);
    await second.database.close();
  });
}
