import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../datasources/local/db_recovery.dart' show formatRecoveryTimestamp;

// Nota: este archivo NO tiene (ni debe tener) ninguna funcion que borre o
// mueva un respaldo. "Confirmar el respaldo" es descartar el aviso en la UI y
// nada mas (D-26 + feedback_no_destructive_automation).

class BackupFailedException implements Exception {
  BackupFailedException(this.message);
  final String message;
  @override
  String toString() => 'BackupFailedException: $message';
}

const _tables = ['audio_assets', 'geo_paths', 'geo_triggers', 'regions'];

Future<Map<String, int>> _counts(Database db) async => {
      for (final t in _tables)
        t: Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0,
    };

/// Copia la base ANTES de abrirla con la version nueva. `onUpgrade` no puede
/// copiar de forma segura la base que tiene abierta, asi que esto corre primero.
/// Devuelve la ruta del respaldo, o null si no hacia falta (sin archivo, o ya en v7).
Future<String?> backupBeforeMigration(
  String dbPath,
  DateTime now, {
  DatabaseFactory? factory,
}) async {
  if (!File(dbPath).existsSync()) return null;
  final f = factory ?? databaseFactory;

  // Sin `version` ni callbacks: abrir asi no dispara ninguna migracion.
  final db = await f.openDatabase(dbPath);
  final Map<String, int> original;
  try {
    final v = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
    if (v >= 7) return null;
    original = await _counts(db);
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    await db.close();
  }

  // COPIA, no rename: la original tiene que seguir en su lugar para migrarla.
  final backupPath = '$dbPath.pre-v7-${formatRecoveryTimestamp(now)}';
  File(dbPath).copySync(backupPath);
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final side = File('$dbPath$suffix');
    if (side.existsSync()) side.copySync('$backupPath$suffix');
  }

  try {
    final copy = await f.openDatabase(backupPath, options: OpenDatabaseOptions(readOnly: true));
    try {
      final got = await _counts(copy);
      if (got.toString() != original.toString()) {
        throw BackupFailedException('la copia no coincide: $got != $original');
      }
    } finally {
      await copy.close();
    }
  } on BackupFailedException {
    rethrow;
  } catch (e) {
    throw BackupFailedException('la copia no abre: $e');
  }
  return backupPath;
}
