import 'dart:io';

import 'package:cingula_app/data/datasources/local/db_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cingula_recovery');
  });

  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('formatRecoveryTimestamp pads a fixed date correctly', () {
    expect(
      formatRecoveryTimestamp(DateTime(2026, 8, 8, 13, 10, 3)),
      '20260808-131003',
    );
  });

  test('renameCorruptDatabase renames the file preserving its content', () async {
    final dbPath = '${tmp.path}/cingula.db';
    File(dbPath).writeAsStringSync('DATOS-ORIGINALES');

    final backupPath = await renameCorruptDatabase(dbPath, DateTime(2026, 8, 8, 13, 10, 3));

    expect(backupPath, '$dbPath.corrupto-20260808-131003');
    expect(File(backupPath!).existsSync(), isTrue);
    expect(File(backupPath).readAsStringSync(), 'DATOS-ORIGINALES');
    expect(File(dbPath).existsSync(), isFalse);
  });

  test('renameCorruptDatabase moves sqlite sidecars alongside the backup', () async {
    final dbPath = '${tmp.path}/cingula.db';
    File(dbPath).writeAsStringSync('DATOS-ORIGINALES');
    File('$dbPath-wal').writeAsStringSync('wal');
    File('$dbPath-shm').writeAsStringSync('shm');
    File('$dbPath-journal').writeAsStringSync('journal');

    final backupPath = await renameCorruptDatabase(dbPath, DateTime(2026, 8, 8, 13, 10, 3));

    expect(File('$backupPath-wal').existsSync(), isTrue);
    expect(File('$backupPath-shm').existsSync(), isTrue);
    expect(File('$backupPath-journal').existsSync(), isTrue);
    expect(File('$dbPath-wal').existsSync(), isFalse);
    expect(File('$dbPath-shm').existsSync(), isFalse);
    expect(File('$dbPath-journal').existsSync(), isFalse);
  });

  test('renameCorruptDatabase returns null and does not throw when file is missing', () async {
    final dbPath = '${tmp.path}/cingula.db';

    final backupPath = await renameCorruptDatabase(dbPath, DateTime(2026, 8, 8, 13, 10, 3));

    expect(backupPath, isNull);
  });

  test('DatabaseRecoveryEvent.backupFileName strips the directory', () {
    final event = DatabaseRecoveryEvent(
      backupPath: '<tmp>/cingula.db.corrupto-20260808-131003',
      occurredAt: DateTime(2026, 8, 8, 13, 10, 3),
    );

    expect(event.backupFileName, 'cingula.db.corrupto-20260808-131003');
  });
}
