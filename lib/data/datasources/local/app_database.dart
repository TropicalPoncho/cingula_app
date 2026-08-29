import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'db_recovery.dart';
import 'seed_data.dart';

/// Gestiona la instancia de SQLite y crea tablas iniciales.
class AppDatabase {
  static const _dbName = 'cingula.db';
  static const _dbVersion = 6;

  Database? _database;

  /// Registro del último evento de recuperación de base (null si no hubo).
  /// La UI lo lee una vez tras el primer frame y lo limpia (ver plan 01-03).
  DatabaseRecoveryEvent? lastRecoveryEvent;

  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError('Base de datos no inicializada');
    }
    return db;
  }

  /// Abre o crea el archivo de base de datos en almacenamiento seguro.
  Future<void> init() async {
    if (_database != null) return;

    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, _dbName);

    try {
      _database = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      stderr.writeln(
        'Database init failed: $e. Renombrando el archivo existente y arrancando en limpio...',
      );
      // Si el rename falla, la excepción se propaga a propósito: preferimos
      // no arrancar antes que destruir datos del usuario (DATA-01).
      final backupPath = await renameCorruptDatabase(path, DateTime.now());

      _database = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      if (backupPath != null) {
        lastRecoveryEvent = DatabaseRecoveryEvent(backupPath: backupPath);
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE audio_assets (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        description TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        local_path TEXT NOT NULL,
        remote_url TEXT,
        uuid TEXT,
        updated_at INTEGER,
        deleted_at INTEGER,
        logical_version INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE geo_triggers (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius_meters REAL NOT NULL,
        audio_asset_id INTEGER NOT NULL,
        geo_path_id INTEGER,
        offset_ms INTEGER NOT NULL DEFAULT 0,
        region_id INTEGER,
        uuid TEXT,
        updated_at INTEGER,
        deleted_at INTEGER,
        logical_version INTEGER,
        FOREIGN KEY(audio_asset_id) REFERENCES audio_assets(id),
        FOREIGN KEY(geo_path_id) REFERENCES geo_paths(id),
        FOREIGN KEY(region_id) REFERENCES regions(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE geo_paths (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        points TEXT NOT NULL,
        audio_asset_id INTEGER NOT NULL,
        tolerance_meters REAL NOT NULL DEFAULT 10.0,
        saved_offset_ms INTEGER NOT NULL DEFAULT 0,
        uuid TEXT,
        updated_at INTEGER,
        deleted_at INTEGER,
        logical_version INTEGER,
        FOREIGN KEY(audio_asset_id) REFERENCES audio_assets(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE regions (
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

    await SeedData.seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
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

    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE sync_outbox ADD COLUMN next_attempt_at INTEGER;');
      } catch (_) {}
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
          await _database!.rawQuery('SELECT COUNT(*) FROM audio_assets'),
        ) ??
        0;

    final triggersCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM geo_triggers'),
        ) ??
        0;

    final pathsCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM geo_paths'),
        ) ??
        0;

    final regionsCount =
        Sqflite.firstIntValue(
          await _database!.rawQuery('SELECT COUNT(*) FROM regions'),
        ) ??
        0;

    return {
      'audio_assets': audioCount,
      'geo_triggers': triggersCount,
      'geo_paths': pathsCount,
      'regions': regionsCount,
    };
  }
}
