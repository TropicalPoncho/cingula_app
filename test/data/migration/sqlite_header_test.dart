import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cingula_app/data/migration/sqlite_header.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('lee el mismo user_version que PRAGMA, sin abrir por sqflite', () async {
    final dir = Directory.systemTemp.createTempSync('sqlite_header');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v.db';

    final db = await databaseFactoryFfi.openDatabase(path);
    await db.setVersion(7);
    await db.close();

    expect(await readSqliteUserVersionRaw(path), 7);
  });

  test('detecta version 6 (celular viejo, antes de migrar)', () async {
    final dir = Directory.systemTemp.createTempSync('sqlite_header');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v.db';

    final db = await databaseFactoryFfi.openDatabase(path);
    await db.setVersion(6);
    await db.close();

    expect(await readSqliteUserVersionRaw(path), 6);
  });

  test('archivo que no existe: null (nunca falso-migrado)', () async {
    expect(await readSqliteUserVersionRaw('/no/existe/cingula.db'), isNull);
  });

  test('archivo que no es SQLite: null, no explota', () async {
    final dir = Directory.systemTemp.createTempSync('sqlite_header');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/no_es_sqlite.db';
    File(path).writeAsBytesSync(List.filled(200, 0x41)); // 'AAAA...'

    expect(await readSqliteUserVersionRaw(path), isNull);
  });

  test('archivo vacio o truncado: null, no explota', () async {
    final dir = Directory.systemTemp.createTempSync('sqlite_header');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/vacio.db';
    File(path).writeAsBytesSync(<int>[]);

    expect(await readSqliteUserVersionRaw(path), isNull);
  });
}
