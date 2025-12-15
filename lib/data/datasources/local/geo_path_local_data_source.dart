import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/geo_path_model.dart';
// GeoPathLocalDataSource no longer handles storing raw point arrays. Path
// geometry is modelled by GeoTriggers that reference geo_path_id.

/// Acceso a la tabla `geo_paths`.
class GeoPathLocalDataSource {
  GeoPathLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<GeoPathModel>> getAll() async {
    final rows = await _database.query('geo_paths');
    return rows.map(GeoPathModel.fromMap).toList(growable: false);
  }
  /// Inserta un nuevo geo path y devuelve el id insertado.
  Future<int> insertPath(Map<String, Object?> values) async {
    final stamped = _sync.withInsertMetadata(values);
    final id = await _database.insert('geo_paths', stamped);
    await _sync.enqueueOutbox(
      tableName: 'geo_paths',
      recordUuid: stamped['uuid'] as String,
      op: 'insert',
      payload: {
        ...stamped,
        'id': id,
      },
    );
    return id;
  }

  Future<void> saveProgress(int pathId, int offsetMs) async {
    final existing = await _database.query(
      'geo_paths',
      columns: ['uuid', 'logical_version'],
      where: 'id = ?',
      whereArgs: [pathId],
      limit: 1,
    );
    final existingUuid = existing.isNotEmpty ? existing.first['uuid'] as String? : null;
    final existingVersion = existing.isNotEmpty ? existing.first['logical_version'] as int? : null;

    final values = _sync.withUpdateMetadata({
      'uuid': existingUuid ?? _sync.newUuid(),
      'logical_version': existingVersion,
      'saved_offset_ms': offsetMs,
    });

    await _database.update(
      'geo_paths',
      values,
      where: 'id = ?',
      whereArgs: [pathId],
    );

    await _sync.enqueueOutbox(
      tableName: 'geo_paths',
      recordUuid: values['uuid'] as String,
      op: 'update',
      payload: {
        ...values,
        'id': pathId,
      },
    );
  }

  /// Borra paths (metadata) asociados a un audio y devuelve el número de filas borradas.
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    final rows = await _database.query(
      'geo_paths',
      columns: ['uuid'],
      where: 'audio_asset_id = ?',
      whereArgs: [audioAssetId],
    );

    final deleted = await _database.delete('geo_paths', where: 'audio_asset_id = ?', whereArgs: [audioAssetId]);

    for (final row in rows) {
      final uuid = row['uuid'] as String?;
      if (uuid != null) {
        await _sync.enqueueOutbox(
          tableName: 'geo_paths',
          recordUuid: uuid,
          op: 'delete',
          payload: {'audio_asset_id': audioAssetId},
        );
      }
    }

    return deleted;
  }

  /// Borra un path por id y también elimina triggers asociados para mantener consistencia.
  Future<int> deleteById(int pathId) async {
    // Capturamos UUID del path y de los triggers asociados antes de borrar.
    final pathRows = await _database.query(
      'geo_paths',
      columns: ['uuid'],
      where: 'id = ?',
      whereArgs: [pathId],
      limit: 1,
    );
    final triggerRows = await _database.query(
      'geo_triggers',
      columns: ['uuid'],
      where: 'geo_path_id = ?',
      whereArgs: [pathId],
    );

    final deletedTriggers = await _database.delete('geo_triggers', where: 'geo_path_id = ?', whereArgs: [pathId]);
    final deletedPaths = await _database.delete('geo_paths', where: 'id = ?', whereArgs: [pathId]);

    // Enqueue delete events for triggers first, then path.
    for (final row in triggerRows) {
      final uuid = row['uuid'] as String?;
      if (uuid != null) {
        await _sync.enqueueOutbox(
          tableName: 'geo_triggers',
          recordUuid: uuid,
          op: 'delete',
          payload: {'geo_path_id': pathId},
        );
      }
    }

    if (pathRows.isNotEmpty) {
      final uuid = pathRows.first['uuid'] as String?;
      if (uuid != null) {
        await _sync.enqueueOutbox(
          tableName: 'geo_paths',
          recordUuid: uuid,
          op: 'delete',
          payload: {'id': pathId},
        );
      }
    }

    // Devuelve total borrado (path + triggers) para fines informativos.
    return deletedPaths + deletedTriggers;
  }
}
