import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/geo_trigger_model.dart';

/// Próxima versión lógica para un borrado, misma regla que SyncLocalDataSource.withUpdateMetadata.
int _nextDeleteVersion(Object? current) => ((current as int?) ?? 0) + 1;

/// Acceso directo a la tabla de geozonas configuradas.
class GeoTriggerLocalDataSource {
  GeoTriggerLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<GeoTriggerModel>> getAll() async {
    final rows = await _database.query('geo_triggers');
    return rows.map(GeoTriggerModel.fromMap).toList(growable: false);
  }

  Future<List<GeoTriggerModel>> fetchByPathId(int pathId) async {
    final rows = await _database.query('geo_triggers', where: 'geo_path_id = ?', whereArgs: [pathId]);
    return rows.map(GeoTriggerModel.fromMap).toList(growable: false);
  }

  /// Borra triggers cuyo geo_path_id apunta a paths inexistentes.
  Future<int> deleteOrphaned() async {
    // Capturar UUIDs de huérfanos antes de borrar para encolar outbox.
    final rows = await _database.rawQuery(
      'SELECT uuid, logical_version FROM geo_triggers WHERE geo_path_id IS NOT NULL AND geo_path_id NOT IN (SELECT id FROM geo_paths)',
    );

    final deleted = await _database.delete(
      'geo_triggers',
      where: 'geo_path_id IS NOT NULL AND geo_path_id NOT IN (SELECT id FROM geo_paths)',
    );

    for (final row in rows) {
      final uuid = row['uuid'] as String?;
      if (uuid != null) {
        await _sync.enqueueOutbox(
          tableName: 'geo_triggers',
          recordUuid: uuid,
          op: 'delete',
          payload: {
            'reason': 'orphan_geo_path',
            'uuid': uuid,
            'logical_version': _nextDeleteVersion(row['logical_version']),
          },
        );
      }
    }

    return deleted;
  }

  /// Borra todos los triggers asociados a un audioAssetId y devuelve el número de filas borradas.
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    // Capture UUIDs before deleting so we can enqueue delete events.
    final rows = await _database.query(
      'geo_triggers',
      columns: ['uuid', 'logical_version'],
      where: 'audio_asset_id = ?',
      whereArgs: [audioAssetId],
    );

    final deleted = await _database.delete('geo_triggers', where: 'audio_asset_id = ?', whereArgs: [audioAssetId]);

    for (final row in rows) {
      final uuid = row['uuid'] as String?;
      if (uuid != null) {
        await _sync.enqueueOutbox(
          tableName: 'geo_triggers',
          recordUuid: uuid,
          op: 'delete',
          payload: {
            'audio_asset_id': audioAssetId,
            'uuid': uuid,
            'logical_version': _nextDeleteVersion(row['logical_version']),
          },
        );
      }
    }

    return deleted;
  }

  /// Inserta un nuevo trigger y devuelve el id insertado.
  Future<int> insertTrigger(Map<String, Object?> values) async {
    final stamped = _sync.withInsertMetadata(values);
    final id = await _database.insert('geo_triggers', stamped);
    await _sync.enqueueOutbox(
      tableName: 'geo_triggers',
      recordUuid: stamped['uuid'] as String,
      op: 'insert',
      payload: {
        ...stamped,
        'id': id,
      },
    );
    return id;
  }
}

