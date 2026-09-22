import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/geo_trigger_model.dart';

/// Acceso directo a la tabla `triggers`.
class GeoTriggerLocalDataSource {
  GeoTriggerLocalDataSource(this._database, this._sync, {this.onObraTouched});

  final Database _database;
  final SyncLocalDataSource _sync;

  /// Se invoca con el obra_uuid afectado tras insertar/borrar triggers, para que la
  /// cobertura de la obra se mantenga al día (D-16/D-29). Nullable: en tests que no
  /// necesitan cobertura, y para evitar una dependencia circular directa con
  /// ObraLocalDataSource, se cablea desde service_locator.dart a ObraRepository.refreshCover.
  final Future<void> Function(String obraUuid)? onObraTouched;

  Future<void> _touchObraForPath(String pathUuid) async {
    if (onObraTouched == null) return;
    final rows = await _database.query('paths', columns: ['obra_uuid'], where: 'uuid = ?', whereArgs: [pathUuid], limit: 1);
    if (rows.isEmpty) return;
    final obraUuid = rows.first['obra_uuid'] as String?;
    if (obraUuid == null) return;
    await onObraTouched!(obraUuid);
  }

  Future<List<GeoTriggerModel>> getAll() async {
    final rows = await _database.query('triggers');
    return rows.map(GeoTriggerModel.fromMap).toList(growable: false);
  }

  Future<List<GeoTriggerModel>> fetchByPathUuid(String pathUuid) async {
    final rows = await _database.query(
      'triggers',
      where: 'path_uuid = ?',
      whereArgs: [pathUuid],
      orderBy: 'position',
    );
    return rows.map(GeoTriggerModel.fromMap).toList(growable: false);
  }

  Future<int> _deleteWhere(String where, List<Object?> args) async {
    final rows = await _database.query('triggers', columns: ['uuid', 'logical_version', 'path_uuid'], where: where, whereArgs: args);
    final deleted = await _database.delete('triggers', where: where, whereArgs: args);
    await _sync.enqueueDeletes('triggers', rows);
    // Una sola llamada por path afectado, no por trigger.
    final pathUuids = rows.map((r) => r['path_uuid'] as String).toSet();
    for (final pathUuid in pathUuids) {
      await _touchObraForPath(pathUuid);
    }
    return deleted;
  }

  /// Borra triggers cuyo path_uuid apunta a paths inexistentes.
  Future<int> deleteOrphaned() =>
      _deleteWhere('path_uuid NOT IN (SELECT uuid FROM paths)', const []);

  Future<int> deleteByPathUuid(String pathUuid) => _deleteWhere('path_uuid = ?', [pathUuid]);

  /// Inserta un trigger y devuelve su uuid. [values] trae path_uuid, name, description,
  /// latitude, longitude, radius_meters y opcionalmente offset_ms.
  Future<String> insertTrigger(Map<String, Object?> values) async {
    final pathUuid = values['path_uuid'] as String;
    final next = Sqflite.firstIntValue(await _database.rawQuery(
          'SELECT COALESCE(MAX(position), -1) + 1 FROM triggers WHERE path_uuid = ?',
          [pathUuid],
        )) ??
        0;
    final stamped = _sync.withInsertMetadata({...values, 'position': next});
    await _database.insert('triggers', stamped);
    final uuid = stamped['uuid'] as String;
    await _sync.enqueueOutbox(tableName: 'triggers', recordUuid: uuid, op: 'insert', payload: stamped);
    await _touchObraForPath(pathUuid);
    return uuid;
  }
}
