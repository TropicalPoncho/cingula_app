import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/geo_path_model.dart';

const _select = 'SELECT paths.*, path_progress.saved_offset_ms '
    'FROM paths LEFT JOIN path_progress ON paths.uuid = path_progress.path_uuid';

/// Acceso a `paths` (sincronizada) y `path_progress` (solo local).
/// La geometría son los triggers.
class GeoPathLocalDataSource {
  GeoPathLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<GeoPathModel>> getAll() async {
    final rows = await _database.rawQuery(_select);
    return rows.map(GeoPathModel.fromMap).toList(growable: false);
  }

  /// Inserta un path y devuelve su uuid. [values] debe traer obra_uuid y name.
  Future<String> insertPath(Map<String, Object?> values) async {
    final stamped = _sync.withInsertMetadata(values);
    await _database.insert('paths', stamped);
    final uuid = stamped['uuid'] as String;
    await _sync.enqueueOutbox(tableName: 'paths', recordUuid: uuid, op: 'insert', payload: stamped);
    return uuid;
  }

  /// SOLO path_progress: no toca `paths` ni el outbox (D-10: con varios usuarios el
  /// progreso de uno pisaría el del otro).
  Future<void> saveProgress(String pathUuid, int offsetMs) async {
    await _database.insert(
      'path_progress',
      {
        'path_uuid': pathUuid,
        'saved_offset_ms': offsetMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateAudio({required String pathUuid, required String audioUuid}) =>
      _sync.updateAndEnqueue('paths', pathUuid, {'audio_uuid': audioUuid});

  /// Borra los paths que usan [audioUuid] (y su progreso); devuelve las filas borradas.
  Future<int> deleteByAudioUuid(String audioUuid) async {
    final rows = await _database.query(
      'paths',
      columns: ['uuid', 'logical_version'],
      where: 'audio_uuid = ?',
      whereArgs: [audioUuid],
    );
    for (final row in rows) {
      await _database.delete('path_progress', where: 'path_uuid = ?', whereArgs: [row['uuid']]);
    }
    final deleted = await _database.delete('paths', where: 'audio_uuid = ?', whereArgs: [audioUuid]);
    await _sync.enqueueDeletes('paths', rows);
    return deleted;
  }

  /// Borra un path, sus triggers y su progreso. Devuelve path + triggers borrados.
  Future<int> deleteByUuid(String pathUuid) async {
    final triggerRows = await _database.query(
      'triggers',
      columns: ['uuid', 'logical_version'],
      where: 'path_uuid = ?',
      whereArgs: [pathUuid],
    );
    final pathRows = await _database.query(
      'paths',
      columns: ['uuid', 'logical_version'],
      where: 'uuid = ?',
      whereArgs: [pathUuid],
    );

    final deletedTriggers = await _database.delete('triggers', where: 'path_uuid = ?', whereArgs: [pathUuid]);
    await _database.delete('path_progress', where: 'path_uuid = ?', whereArgs: [pathUuid]);
    final deletedPaths = await _database.delete('paths', where: 'uuid = ?', whereArgs: [pathUuid]);

    // Triggers primero, después el path.
    await _sync.enqueueDeletes('triggers', triggerRows);
    await _sync.enqueueDeletes('paths', pathRows);
    return deletedPaths + deletedTriggers;
  }
}
