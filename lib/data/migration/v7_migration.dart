import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'cover.dart';
import 'ids.dart';
import 'preflight.dart';
import 'v7_schema.dart';

class MigrationException implements Exception {
  MigrationException(this.message, {this.report, this.cause});
  final String message;
  final Map<String, Object?>? report;

  /// La excepcion original cuando la migracion fallo por algo que NO es una
  /// discrepancia de verificacion (violacion de PK, error de SQL, disco lleno).
  /// El plan 02.1-08 envuelve TODO fallo de `migrateToV7` en esta clase: si no,
  /// el `catch (e)` generico de `AppDatabase.init()` trataria una base sana
  /// como corrupta y la renombraria (D-25).
  final Object? cause;

  @override
  String toString() =>
      'MigrationException: $message${cause == null ? '' : ' (causa: $cause)'}';
}

final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

// Mismo criterio de validez que _uuidRe, expresado como GLOB para los diffs SQL.
String _globUuid() {
  const h = '[0-9a-fA-F]';
  String n(int k) => List.filled(k, h).join();
  return '${n(8)}-${n(4)}-${n(4)}-${n(4)}-${n(12)}';
}

String _uuidOrNew(Object? v) {
  final s = v as String?;
  return (s != null && _uuidRe.hasMatch(s)) ? s : const Uuid().v4();
}

Future<int> _count(DatabaseExecutor db, String sql) async =>
    Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;

/// Corre DENTRO de la transaccion exclusiva que sqflite abre para onUpgrade.
/// NO abrir otra transaccion adentro (anidaria y trabaria la base).
/// Devuelve un reporte con los conteos y `portalsFromDangling`.
///
/// [onBeforeVerify]: ponytail: existe solo para probar el rollback ante una discrepancia.
Future<Map<String, Object?>> migrateToV7(
  DatabaseExecutor db, {
  DateTime? now,
  @visibleForTesting Future<void> Function(DatabaseExecutor db)? onBeforeVerify,
}) async {
  final nowSec = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final before = await preflight(db); // conteos ANTES de escribir nada
  await createV7Tables(db);

  // 1. audios + audio_local
  final audioUuidById = <int, String>{};
  for (final r in await db.rawQuery('SELECT * FROM audio_assets ORDER BY id')) {
    final uuid = _uuidOrNew(r['uuid']);
    audioUuidById[r['id'] as int] = uuid;
    await db.insert('audios', {
      'uuid': uuid,
      'kind': 'grabacion',
      'title': r['title'],
      'description': r['description'],
      'duration_seconds': r['duration_seconds'],
      'updated_at': r['updated_at'] ?? nowSec,
      'deleted_at': r['deleted_at'],
      'logical_version': r['logical_version'] ?? 1,
    });
    await db.insert('audio_local', {
      'audio_uuid': uuid,
      'local_path': r['local_path'],
      'remote_url': r['remote_url'],
    });
  }

  Future<void> insertObra(String uuid, Object? name, Object? updatedAt,
      Object? deletedAt, Object? version) async {
    await db.insert('obras', {
      'uuid': uuid,
      'name': name,
      'visibility': 'draft',
      'updated_at': updatedAt ?? nowSec,
      'deleted_at': deletedAt,
      'logical_version': version ?? 1,
    });
  }

  // 2. paths route + obras + path_progress
  final pathUuidById = <int, String>{};
  for (final r in await db.rawQuery('SELECT * FROM geo_paths ORDER BY id')) {
    final uuid = _uuidOrNew(r['uuid']);
    pathUuidById[r['id'] as int] = uuid;
    final obra = obraUuidForPath(uuid);
    await insertObra(obra, r['name'], r['updated_at'], r['deleted_at'],
        r['logical_version']);
    await db.insert('paths', {
      'uuid': uuid,
      'obra_uuid': obra,
      'kind': 'route',
      'name': r['name'],
      'audio_uuid': audioUuidById[r['audio_asset_id']],
      'tolerance_meters': r['tolerance_meters'],
      'updated_at': r['updated_at'] ?? nowSec,
      'deleted_at': r['deleted_at'],
      'logical_version': r['logical_version'] ?? 1,
    });
    await db.insert('path_progress', {
      'path_uuid': uuid,
      'saved_offset_ms': r['saved_offset_ms'] ?? 0,
      'updated_at': nowSec,
    });
  }

  // 3. triggers (+ portales para los sueltos y los de path colgante)
  var portals = 0, portalsFromDangling = 0;
  final position = <String, int>{};
  final pointsByObra = <String, List<({double lat, double lon})>>{};
  for (final r in await db.rawQuery(
      'SELECT * FROM geo_triggers ORDER BY geo_path_id, offset_ms, id')) {
    final uuid = _uuidOrNew(r['uuid']);
    final legacyPath = r['geo_path_id'] as int?;
    String pathUuid;
    String obra;
    if (legacyPath != null && pathUuidById.containsKey(legacyPath)) {
      pathUuid = pathUuidById[legacyPath]!;
      obra = obraUuidForPath(pathUuid);
    } else {
      if (legacyPath != null) portalsFromDangling++;
      portals++;
      pathUuid = portalUuidForTrigger(uuid);
      obra = obraUuidForPath(pathUuid);
      await insertObra(obra, r['name'], r['updated_at'], r['deleted_at'],
          r['logical_version']);
      await db.insert('paths', {
        'uuid': pathUuid,
        'obra_uuid': obra,
        'kind': 'portal',
        'name': r['name'],
        'audio_uuid': audioUuidById[r['audio_asset_id']],
        'tolerance_meters': 10.0,
        'updated_at': r['updated_at'] ?? nowSec,
        'deleted_at': r['deleted_at'],
        'logical_version': r['logical_version'] ?? 1,
      });
    }
    final pos = position[pathUuid] ?? 0;
    position[pathUuid] = pos + 1;
    await db.insert('triggers', {
      'uuid': uuid,
      'path_uuid': pathUuid,
      'position': pos,
      'name': r['name'],
      'description': r['description'],
      'latitude': r['latitude'],
      'longitude': r['longitude'],
      'radius_meters': r['radius_meters'],
      'offset_ms': r['offset_ms'],
      'updated_at': r['updated_at'] ?? nowSec,
      'deleted_at': r['deleted_at'],
      'logical_version': r['logical_version'] ?? 1,
    });
    (pointsByObra[obra] ??= []).add((
      lat: (r['latitude'] as num).toDouble(),
      lon: (r['longitude'] as num).toDouble(),
    ));
  }

  // 4. cobertura (obra sin triggers: las seis columnas quedan NULL, D-29)
  for (final e in pointsByObra.entries) {
    final c = computeCover(e.value);
    await db.update(
        'obras',
        {
          'cover_lat': c.centerLat,
          'cover_lon': c.centerLon,
          'cover_min_lat': c.minLat,
          'cover_max_lat': c.maxLat,
          'cover_min_lon': c.minLon,
          'cover_max_lon': c.maxLon,
        },
        where: 'uuid = ?',
        whereArgs: [e.key]);
  }

  if (onBeforeVerify != null) await onBeforeVerify(db);

  // 5. verificacion
  final report = await _verify(db, before, portals);
  report['portalsFromDangling'] = portalsFromDangling;
  return report;
}

Future<Map<String, Object?>> _verify(
    DatabaseExecutor db, Map<String, Object?> before, int portals) async {
  final report = <String, Object?>{'before': before};
  Never fail(String msg) =>
      throw MigrationException(msg, report: Map.of(report));

  Future<void> expectCount(String table, String sql, int expected) async {
    final got = await _count(db, sql);
    report[table] = got;
    if (got != expected) fail('$table: esperado $expected, hay $got');
  }

  final nAudio = await _count(db, 'SELECT COUNT(*) FROM audio_assets');
  final nPaths = await _count(db, 'SELECT COUNT(*) FROM geo_paths');
  final nTrig = await _count(db, 'SELECT COUNT(*) FROM geo_triggers');
  await expectCount('audios', 'SELECT COUNT(*) FROM audios', nAudio);
  await expectCount('triggers', 'SELECT COUNT(*) FROM triggers', nTrig);
  await expectCount('paths', 'SELECT COUNT(*) FROM paths', nPaths + portals);
  await expectCount('obras', 'SELECT COUNT(*) FROM obras', nPaths + portals);
  await expectCount('audio_local', 'SELECT COUNT(*) FROM audio_local', nAudio);
  await expectCount(
      'path_progress', 'SELECT COUNT(*) FROM path_progress', nPaths);
  final regionsBefore = (before['counts'] as Map)['regions'] as int;
  await expectCount('regions', 'SELECT COUNT(*) FROM regions', regionsBefore);

  // Diffs exactos en ambos sentidos. Adelante solo filas con uuid valido (las
  // demas recibieron uuid nuevo); atras solo uuid que ya existian en legacy.
  final g = _globUuid();
  const cT = 'uuid,name,latitude,longitude,radius_meters,offset_ms';
  const cA = 'uuid,title,description,duration_seconds';
  final diffs = <String, String>{
    'triggers fwd':
        "SELECT $cT FROM geo_triggers WHERE uuid GLOB '$g' EXCEPT SELECT $cT FROM triggers",
    'triggers rev':
        "SELECT $cT FROM triggers WHERE uuid IN (SELECT uuid FROM geo_triggers) EXCEPT SELECT $cT FROM geo_triggers",
    'audios fwd':
        "SELECT $cA FROM audio_assets WHERE uuid GLOB '$g' EXCEPT SELECT $cA FROM audios",
    'audios rev':
        "SELECT $cA FROM audios WHERE uuid IN (SELECT uuid FROM audio_assets) EXCEPT SELECT $cA FROM audio_assets",
    'audio_local fwd':
        "SELECT uuid, local_path, remote_url FROM audio_assets WHERE uuid GLOB '$g' EXCEPT SELECT audio_uuid, local_path, remote_url FROM audio_local",
    'audio_local rev':
        "SELECT audio_uuid, local_path, remote_url FROM audio_local WHERE audio_uuid IN (SELECT uuid FROM audio_assets) EXCEPT SELECT uuid, local_path, remote_url FROM audio_assets",
    'paths fwd':
        "SELECT uuid,name,tolerance_meters FROM geo_paths WHERE uuid GLOB '$g' EXCEPT SELECT uuid,name,tolerance_meters FROM paths",
    'paths rev':
        "SELECT uuid,name,tolerance_meters FROM paths WHERE kind = 'route' AND uuid IN (SELECT uuid FROM geo_paths) EXCEPT SELECT uuid,name,tolerance_meters FROM geo_paths",
  };
  for (final e in diffs.entries) {
    final rows = await db.rawQuery(e.value);
    if (rows.isNotEmpty) {
      report['diff ${e.key}'] = rows.length;
      fail('diff ${e.key}: ${rows.length} filas distintas');
    }
  }

  // Integridad referencial
  // Solo las tablas nuevas: las legacy pueden traer refs colgantes de origen.
  for (final t in ['audio_local', 'paths', 'triggers', 'path_progress']) {
    final fk = await db.rawQuery('PRAGMA foreign_key_check($t)');
    if (fk.isNotEmpty) fail('foreign_key_check($t): ${fk.length} violaciones');
  }
  if (await _count(db,
          'SELECT COUNT(*) FROM triggers WHERE path_uuid NOT IN (SELECT uuid FROM paths)') >
      0) {
    fail('triggers con path_uuid inexistente');
  }
  if (await _count(db,
          'SELECT COUNT(*) FROM paths WHERE obra_uuid NOT IN (SELECT uuid FROM obras)') >
      0) {
    fail('paths con obra_uuid inexistente');
  }
  for (final t in ['audios', 'obras', 'paths', 'triggers']) {
    if (await _count(
            db, "SELECT COUNT(*) FROM $t WHERE uuid IS NULL OR uuid = ''") >
        0) {
      fail('$t con uuid NULL o vacio');
    }
  }
  return report;
}
