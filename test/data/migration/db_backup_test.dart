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
