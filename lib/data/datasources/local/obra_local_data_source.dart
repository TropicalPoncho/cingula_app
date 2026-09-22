import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../migration/cover.dart';
import '../../models/obra_model.dart';

/// Acceso a `obras`. Las tablas de coautoría del backend (ver TABLE_SPEC) existen
/// vacías y sin consumidor en 2.1.
class ObraLocalDataSource {
  ObraLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<ObraModel>> getAll() async {
    final rows = await _database.query('obras');
    return rows.map(ObraModel.fromMap).toList(growable: false);
  }

  Future<ObraModel?> findByUuid(String uuid) async {
    final rows = await _database.query('obras', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : ObraModel.fromMap(rows.first);
  }

  Future<String> createDraft(String name) async {
    final values = _sync.withInsertMetadata({'name': name, 'visibility': 'draft'});
    await _database.insert('obras', values);
    final uuid = values['uuid'] as String;
    await _sync.enqueueOutbox(tableName: 'obras', recordUuid: uuid, op: 'insert', payload: values);
    return uuid;
  }

  /// Recalcula la cobertura de la obra a partir de TODOS los triggers de sus paths.
  /// El celular es el único escritor hoy (D-29): calcula acá y la cobertura viaja
  /// como columnas normales de la obra; el servidor no la recalcula (dos cálculos = divergencia).
  /// Solo escribe (y bumpea logical_version) si algún valor cambió.
  Future<void> refreshCover(String obraUuid) async {
    final current = await findByUuid(obraUuid);
    if (current == null) return;

    final rows = await _database.rawQuery(
      'SELECT t.latitude, t.longitude FROM triggers t '
      'JOIN paths p ON p.uuid = t.path_uuid '
      'WHERE p.obra_uuid = ? AND t.deleted_at IS NULL',
      [obraUuid],
    );
    final points = rows
        .map((r) => (lat: (r['latitude'] as num).toDouble(), lon: (r['longitude'] as num).toDouble()))
        .toList(growable: false);
    final cover = computeCover(points);

    final changed = current.coverLat != cover.centerLat ||
        current.coverLon != cover.centerLon ||
        current.coverMinLat != cover.minLat ||
        current.coverMaxLat != cover.maxLat ||
        current.coverMinLon != cover.minLon ||
        current.coverMaxLon != cover.maxLon;
    if (!changed) return;

    await _sync.updateAndEnqueue('obras', obraUuid, {
      'cover_lat': cover.centerLat,
      'cover_lon': cover.centerLon,
      'cover_min_lat': cover.minLat,
      'cover_max_lat': cover.maxLat,
      'cover_min_lon': cover.minLon,
      'cover_max_lon': cover.maxLon,
    });
  }
}
