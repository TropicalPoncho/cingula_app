import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Congela el esquema v6 (copia literal del `_onCreate` previo a la migracion a v7).
/// NO llama a SeedData: los tests siembran con [seedSynthetic].
Future<void> buildV6(Database db) async {
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
}

/// Abre una base v6 vacia (solo esquema) en [path].
Future<Database> openV6(String path) async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(version: 6, onCreate: (d, _) => buildV6(d)),
  );
}

/// Crea un directorio temporal, abre una v6 ahi y la siembra. Devuelve la base
/// y el directorio (el llamador lo borra).
Future<(Database, Directory)> openSeededV6Temp({int seed = 42}) async {
  final dir = Directory.systemTemp.createTempSync('cingula_v6_');
  final db = await openV6('${dir.path}/v6.db');
  await seedSynthetic(db, seed: seed);
  return (db, dir);
}

String _uuid(math.Random r) {
  String h(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  final variant = '89ab'[r.nextInt(4)];
  return '${h(8)}-${h(4)}-4${h(3)}-$variant${h(3)}-${h(12)}';
}

/// Dataset sintetico deterministico con la forma real del celular:
/// 77 audio_assets, 70 geo_paths, 459 geo_triggers (444 con path, 15 sueltos;
/// 4 de los de path llevan region_id), 20 regions, 6 sync_outbox, 1 sync_state.
Future<void> seedSynthetic(Database db, {int seed = 42}) async {
  final r = math.Random(seed);
  const ts = 1750000000000;
  final b = db.batch();

  // audio_assets 1..77. Referenciados: 1..70 por paths, 71..73 por sueltos.
  // Huerfanos: 74..77. uuid NULL: 1,2. assets/: 3,4,5. metadata NULL: 6..10.
  for (var i = 1; i <= 77; i++) {
    b.insert('audio_assets', {
      'id': i,
      'title': 'Audio $i',
      'artist': 'Artista',
      'description': 'desc $i',
      'duration_seconds': 30 + r.nextInt(300),
      'local_path': (i >= 3 && i <= 5)
          ? 'assets/audio/a$i.mp3'
          : '/data/user/0/app/files/a$i.m4a',
      'uuid': i <= 2 ? null : _uuid(r),
      'updated_at': (i >= 6 && i <= 10) ? null : ts + i,
      'logical_version': (i >= 6 && i <= 10) ? null : 1,
    });
  }

  for (var i = 1; i <= 70; i++) {
    b.insert('geo_paths', {
      'id': i,
      'name': 'Recorrido $i',
      'points': '[]',
      'audio_asset_id': i,
      'saved_offset_ms': i <= 6 ? 1000 * i : 0,
      'uuid': _uuid(r),
      'updated_at': ts + i,
      'logical_version': 1,
    });
  }

  for (var i = 1; i <= 20; i++) {
    b.insert('regions', {
      'id': i,
      'name': 'Region $i',
      'center_lat': -42.1 - r.nextDouble() / 10,
      'center_lon': -71.6 - r.nextDouble() / 10,
      'radius_meters': 1000.0,
      'uuid': _uuid(r),
      'updated_at': ts + i,
      'logical_version': 1,
    });
  }

  final perPath = <int, int>{};
  for (var i = 1; i <= 444; i++) {
    final pathId = (i - 1) % 70 + 1;
    final n = perPath[pathId] = (perPath[pathId] ?? 0) + 1;
    b.insert('geo_triggers', {
      'id': i,
      'name': 'Trigger $i',
      'description': '',
      'latitude': -42.1 - r.nextDouble() / 10,
      'longitude': -71.6 - r.nextDouble() / 10,
      'radius_meters': 15.0,
      // 3 triggers con audio distinto al del path (caso informativo).
      'audio_asset_id': i <= 3 ? 71 : pathId,
      'geo_path_id': pathId,
      'offset_ms': n * 1000,
      'region_id': (i >= 10 && i < 14) ? 1 : null,
      'uuid': _uuid(r),
      'updated_at': ts + i,
      'logical_version': 1,
    });
  }
  for (var i = 445; i <= 459; i++) {
    b.insert('geo_triggers', {
      'id': i,
      'name': 'Suelto $i',
      'description': '',
      'latitude': -42.1 - r.nextDouble() / 10,
      'longitude': -71.6 - r.nextDouble() / 10,
      'radius_meters': 25.0,
      'audio_asset_id': 71 + (i % 3),
      'geo_path_id': null,
      'offset_ms': 0,
      'uuid': _uuid(r),
      'updated_at': ts + i,
      'logical_version': 1,
    });
  }

  Map<String, Object?> ob(String t, String op, String? payload) => {
        'table_name': t,
        'record_uuid': _uuid(r),
        'op': op,
        'payload': payload,
        'created_at': ts,
      };
  b.insert('sync_outbox', ob('geo_triggers', 'insert', jsonEncode({'id': 1, 'uuid': 'x', 'logical_version': 1})));
  b.insert('sync_outbox', ob('geo_triggers', 'insert', jsonEncode({'id': 2, 'uuid': 'y', 'logical_version': 1})));
  b.insert('sync_outbox', ob('geo_paths', 'update', jsonEncode({'id': 1, 'uuid': 'z', 'logical_version': 2})));
  b.insert('sync_outbox', ob('geo_triggers', 'delete', jsonEncode({'uuid': 'w', 'logical_version': 3})));
  b.insert('sync_outbox', ob('audio_assets', 'delete', jsonEncode({'id': 9, 'uuid': 'v', 'logical_version': 2})));
  b.insert('sync_outbox', ob('regions', 'delete', jsonEncode({'id': 20, 'uuid': 'u', 'logical_version': 2})));

  b.insert('sync_state', {
    'id': 1,
    'server_cursor': '2026-09-16T03:12:44.000Z',
    'last_sync_at': ts,
    'device_id': 'dev-synthetic',
  });

  await b.commit(noResult: true);
}

Future<void> addDuplicateUuid(Database db) async {
  final row = (await db.query('geo_triggers', where: 'id = 1')).first;
  final dup = Map<String, Object?>.from(row)..['id'] = 9001;
  await db.insert('geo_triggers', dup);
}

Future<void> addDanglingPathRef(Database db) async {
  await db.insert('geo_triggers', {
    'id': 9002,
    'name': 'Colgante',
    'description': '',
    'latitude': -42.1,
    'longitude': -71.6,
    'radius_meters': 10.0,
    'audio_asset_id': 1,
    'geo_path_id': 99999,
    'uuid': '00000000-0000-4000-8000-000000009002',
  });
}

Future<void> addDanglingAudioRef(Database db) async {
  await db.insert('geo_paths', {
    'id': 9003,
    'name': 'Path audio colgante',
    'points': '[]',
    'audio_asset_id': 99999,
    'uuid': '00000000-0000-4000-8000-000000009003',
  });
}

Future<void> addInvalidUuidFormat(Database db) async {
  await db.insert('regions', {
    'id': 9004,
    'name': 'Uuid invalido',
    'center_lat': -42.1,
    'center_lon': -71.6,
    'radius_meters': 100.0,
    'uuid': 'no-es-un-uuid',
  });
}
