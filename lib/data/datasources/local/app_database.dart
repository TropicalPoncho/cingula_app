import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'seed_data.dart';

/// Gestiona la instancia de SQLite y crea tablas iniciales.
class AppDatabase {
  static const _dbName = 'cingula.db';
  static const _dbVersion = 3;

  Database? _database;

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

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE audio_assets (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            description TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            local_path TEXT NOT NULL,
            remote_url TEXT
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
            fine_distance_filter_meters INTEGER DEFAULT 5
          );
        ''');

        // Insertamos registros base para pruebas iniciales.
        await SeedData.seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
          // Create regions table and add region_id to geo_triggers
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
              fine_distance_filter_meters INTEGER DEFAULT 5
            );
          ''');

          // Add nullable region_id column to geo_triggers if missing
          try {
            await db.execute('ALTER TABLE geo_triggers ADD COLUMN region_id INTEGER;');
          } catch (_) {
            // ignore if column already exists or other SQLite limitations
          }
          // Add nullable geo_path_id column to geo_triggers if missing
          try {
            await db.execute('ALTER TABLE geo_triggers ADD COLUMN geo_path_id INTEGER;');
          } catch (_) {
            // ignore if column already exists or other SQLite limitations
          }
          // Add offset_ms column to geo_triggers if missing (default 0)
          try {
            await db.execute('ALTER TABLE geo_triggers ADD COLUMN offset_ms INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {
            // ignore if column already exists or other SQLite limitations
          }
        }
      },
    );
  }

  /// For testing: delete existing DB file (if any) and reinitialize.
  /// Use this during development to ensure seeds and schema are recreated.
  Future<void> recreateForTesting() async {
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, _dbName);
    try {
      await deleteDatabase(path);
    } catch (_) {
      // ignore
    }
    await init();
  }
}

