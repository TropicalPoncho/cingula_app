import 'dart:io';

import 'package:cingula_app/data/migration/db_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/v6_fixture.dart';

void main() {
  final now = DateTime(2026, 9, 21, 10, 30, 5);

  Future<(String, Directory)> seeded() async {
    final (db, dir) = await openSeededV6Temp();
    await db.close();
    addTearDown(() => dir.deleteSync(recursive: true));
    return ('${dir.path}/v6.db', dir);
  }

  test('copia con timestamp, original intacto', () async {
    final (path, _) = await seeded();
    final size = File(path).lengthSync();
    final b = await backupBeforeMigration(path, now, factory: databaseFactoryFfi);
    expect(b, '$path.pre-v7-20260921-103005');
    expect(File(b!).existsSync(), isTrue);
    expect(File(path).lengthSync(), size);
    final db = await databaseFactoryFfi.openDatabase(path);
    expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM geo_triggers')), 459);
    await db.close();
  });

  test('copia sidecars que existan', () async {
    final (path, _) = await seeded();
    File('$path-journal').writeAsBytesSync([]);
    final b = await backupBeforeMigration(path, now, factory: databaseFactoryFfi);
    expect(File('$b-journal').existsSync(), isTrue);
  });

  test('sin archivo devuelve null', () async {
    final dir = Directory.systemTemp.createTempSync('cgb');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(await backupBeforeMigration('${dir.path}/no.db', now, factory: databaseFactoryFfi),
        isNull);
  });

  test('ya en v7 devuelve null y no copia', () async {
    final (path, dir) = await seeded();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('PRAGMA user_version = 7');
    await db.close();
    expect(await backupBeforeMigration(path, now, factory: databaseFactoryFfi), isNull);
    expect(dir.listSync().where((e) => e.path.contains('pre-v7')), isEmpty);
  });

  test('tras el chequeo (ya en v7), reabrir el MISMO path como singleInstance '
      'no da database_closed en la primera query — regresion del bug real: '
      'app_database.dart abre singleInstance el mismo path justo despues de '
      'esta funcion, y si esta funcion usara la cache singleInstance para su '
      'propio open+close, esa reapertura podia devolver una conexion ya '
      'cerrada', () async {
    final (path, _) = await seeded();
    final db0 = await databaseFactoryFfi.openDatabase(path);
    await db0.execute('PRAGMA user_version = 7');
    await db0.close();

    expect(await backupBeforeMigration(path, now, factory: databaseFactoryFfi), isNull);

    // Exactamente lo que hace AppDatabase.init() a continuacion: abrir el
    // mismo path, singleInstance (default), y correr la primera query real.
    final real = await databaseFactoryFfi.openDatabase(path);
    addTearDown(real.close);
    await expectLater(
      real.rawQuery('SELECT COUNT(*) FROM geo_triggers'),
      completes,
    );
  });

  test('base ilegible para la verificacion aborta ruidosamente', () async {
    final (path, _) = await seeded();
    // Sin las tablas esperadas no se puede contar: no se sigue adelante.
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('DROP TABLE regions');
    await db.close();
    await expectLater(backupBeforeMigration(path, now, factory: databaseFactoryFfi),
        throwsA(anything));
  });
}
