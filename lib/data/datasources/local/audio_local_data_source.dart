import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/audio_asset_model.dart';

/// Lecturas sobre la tabla de audios persistidos.
class AudioLocalDataSource {
  AudioLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<AudioAssetModel>> getAll() async {
    final rows = await _database.query('audio_assets');
    return rows.map(AudioAssetModel.fromMap).toList(growable: false);
  }

  Future<AudioAssetModel?> getById(int id) async {
    final rows = await _database.query(
      'audio_assets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AudioAssetModel.fromMap(rows.first);
  }

  Future<int> insertRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) async {
    final values = _sync.withInsertMetadata({
      'title': title,
      'artist': 'Field Recording',
      'description': description,
      'duration_seconds': duration.inSeconds,
      'local_path': localPath,
      'remote_url': null,
    });

    final id = await _database.insert('audio_assets', values);
    await _sync.enqueueOutbox(
      tableName: 'audio_assets',
      recordUuid: values['uuid'] as String,
      op: 'insert',
      payload: {
        ...values,
        'id': id,
      },
    );
    return id;
  }

  Future<void> updateDuration({required int id, required Duration duration}) async {
    final existing = await _database.query(
      'audio_assets',
      columns: ['uuid', 'logical_version'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final existingUuid = existing.isNotEmpty ? existing.first['uuid'] as String? : null;
    final existingVersion = existing.isNotEmpty ? existing.first['logical_version'] as int? : null;
    final values = _sync.withUpdateMetadata({
      'uuid': existingUuid ?? _sync.newUuid(),
      'logical_version': existingVersion,
      'duration_seconds': duration.inSeconds,
    });

    await _database.update(
      'audio_assets',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _sync.enqueueOutbox(
      tableName: 'audio_assets',
      recordUuid: values['uuid'] as String,
      op: 'update',
      payload: {
        ...values,
        'id': id,
      },
    );
  }
}

