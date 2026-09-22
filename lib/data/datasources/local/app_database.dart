import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../migration/db_backup.dart';
import '../../migration/v7_migration.dart';
import '../../migration/v7_schema.dart';
import 'db_recovery.dart';
import 'seed_data.dart';

/// Gestiona la instancia de SQLite y crea tablas iniciales.
class AppDatabase {
  static const _dbName = 'cingula.db';
  static const _dbVersion = 7;

  Database? _database;

  /// Registro del último evento de recuperación de base (null si no hubo).
  /// La UI lo lee una vez tras el primer frame y lo limpia (ver plan 01-03).
  DatabaseRecoveryEvent? lastRecoveryEvent;

  /// Ruta del respaldo tomado ANTES de migrar a v7 (null si no hubo migración
  /// en este `init()`), para el aviso D-19/D-26.
  String? lastBackupPath;

  /// Costura de test para forzar el camino de "discrepancia de verificación"
  /// (D-25) a través de `init()`, sin exponer nada nuevo en su firma: reusa
  /// el mismo hook `onBeforeVerify` que ya expone `migrateToV7`.
  @visibleForTesting
  Future<void> Function(DatabaseExecutor db)? debugOnBeforeVerifyV7;

  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError('Base de datos no inicializada');
    }
    return db;
  }

  /// Abre o crea el archivo de base de datos en almacenamiento seguro.
  /// [dbPath] y [factory] existen SOLO para poder probar `init()` sin
  /// dispositivo: por defecto son `getApplicationDocumentsDirectory()` + el
  /// `databaseFactory` global, exactamente el comportamiento de hoy.
  Future<void> init({String? dbPath, DatabaseFactory? factory}) async {
    if (_database != null) return;

    final f = factory ?? databaseFactory;
    final path = dbPath ?? p.join((await getApplicationDocumentsDirectory()).path, _dbName);

    try {
      // Respaldo tomado ANTES de abrir en v7: `onUpgrade` no puede copiar de
      // forma segura la base que tiene abierta.
      lastBackupPath = await backupBeforeMigration(path, DateTime.now(), factory: f);
      _database = await f.openDatabase(
        path,
        options: OpenDatabaseOptions(version: _dbVersion, onCreate: _onCreate, onUpgrade: _onUpgrade),
      );
    } on MigrationException {
      rethrow; // NO entra al camino de "BD corrupta": la base sana no se toca.
    } on BackupFailedException {
      rethrow; // sin respaldo confiable no se migra.
    } catch (e) {
      stderr.writeln(
        'Database init failed: $e. Renombrando el archivo existente y arrancando en limpio...',
      );
      // Si el rename falla, la excepción se propaga a propósito: preferimos
      // no arrancar antes que destruir datos del usuario (DATA-01).
      final backupPath = await renameCorruptDatabase(path, DateTime.now());

      _database = await f.openDatabase(
        path,
        options: OpenDatabaseOptions(version: _dbVersion, onCreate: _onCreate, onUpgrade: _onUpgrade),
      );

      if (backupPath != null) {
        lastRecoveryEvent = DatabaseRecoveryEvent(backupPath: backupPath);
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await createV7Tables(db);
    await _createSyncTables(db);
    await SeedData.seed(db);
  }

  /// sync_outbox/sync_state no cambian de forma en este plan (no son parte del
  /// esquema nuevo de entidades en `v7_schema.dart`): se crean tal cual venían.
  Future<void> _createSyncTables(Database db) async {
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // legacy-upgrade: no tocar (camino que lleva una base vieja hasta v6).
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS geo_paths (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          points TEXT NOT NULL,
          audio_asset_id INTEGER NOT NULL,
          tolerance_meters REAL NOT NULL DEFAULT 10.0,
          saved_offset_ms INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(audio_asset_id) REFERENCES audio_assets(id)
        );
      ''');
    }

    // legacy-upgrade: no tocar
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS regions (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          center_lat REAL NOT NULL,
          center_lon REAL NOT NULL,
          radius_meters REAL NOT NULL,
          sample_coarse_seconds INTEGER NOT NULL DEFAULT 30,
          sample_fine_seconds INTEGER NOT NULL DEFAULT 2,
          coarse_distance_filter_meters INTEGER DEFAULT 500,
          fine_distance_filter_meters INTEGER DEFAULT 5,
          uuid TEXT,
          updated_at INTEGER,
          deleted_at INTEGER,
          logical_version INTEGER
        );
      ''');

      try {
        await db.execute(
          'ALTER TABLE geo_triggers ADD COLUMN region_id INTEGER;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE geo_triggers ADD COLUMN geo_path_id INTEGER;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE geo_triggers ADD COLUMN offset_ms INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
    }

    // legacy-upgrade: no tocar
    if (oldVersion < 4) {
      for (final table in [
        'audio_assets',
        'geo_triggers',
        'geo_paths',
        'regions',
      ]) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN uuid TEXT;');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN updated_at INTEGER;');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN deleted_at INTEGER;');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN logical_version INTEGER;');
        } catch (_) {}
      }
    }

    // legacy-upgrade: no tocar
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_outbox (
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
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            server_cursor TEXT,
            last_sync_at INTEGER,
            device_id TEXT
          );
        ''');
      } catch (_) {}
    }

    // legacy-upgrade: no tocar
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE sync_outbox ADD COLUMN next_attempt_at INTEGER;');
      } catch (_) {}
    }

    if (oldVersion < 7) {
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        await migrateToV7(db, onBeforeVerify: debugOnBeforeVerifyV7);
      } on MigrationException {
        rethrow; // ya viene normalizada.
      } catch (e) {
        // D-25: CUALQUIER otro fallo tiene que llegar a init() como MigrationException.
        // Si sale crudo, el catch genérico de init() lo trata como "BD corrupta", renombra
        // una base SANA y arranca vacía: exactamente el escenario que esta fase existe para
        // evitar.
        throw MigrationException('Falló la migración v6→v7', cause: e);
      }
      // NO envolver en db.transaction(): sqflite ya corre onUpgrade dentro de una
      // transacción exclusiva, y esa transacción es la que revierte todo si esto lanza.
    }
  }

  /// Exporta la base de datos actual a la carpeta Downloads.
  /// Retorna la ruta del archivo exportado.
  Future<String> exportDatabase() async {
    if (_database == null) {
      throw StateError('Base de datos no inicializada');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, _dbName);

    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
    } else {
      downloadsDir = await getDownloadsDirectory();
    }

    if (downloadsDir == null || !downloadsDir.existsSync()) {
      throw Exception('No se pudo acceder a la carpeta Downloads');
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final exportFileName = 'cingula_backup_$timestamp.db';
    final exportPath = p.join(downloadsDir.path, exportFileName);

    final dbFile = File(dbPath);
    await dbFile.copy(exportPath);

    return exportPath;
  }

  /// Retorna estadisticas basicas de tablas principales.
  Future<Map<String, int>> getDatabaseStats() async {
    if (_database == null) {
      throw StateError('Base de datos no inicializada');
    }

    final audioCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM audios'),
        ) ??
        0;

    final obraCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM obras'),
        ) ??
        0;

    final pathsCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM paths'),
        ) ??
        0;

    final triggersCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM triggers'),
        ) ??
        0;

    return {
      'audios': audioCount,
      'obras': obraCount,
      'paths': pathsCount,
      'triggers': triggersCount,
    };
  }
}
