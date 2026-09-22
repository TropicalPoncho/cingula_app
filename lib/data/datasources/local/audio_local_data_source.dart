import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/audio_asset_model.dart';

const _select = 'SELECT audios.*, audio_local.local_path, audio_local.remote_url '
    'FROM audios LEFT JOIN audio_local ON audios.uuid = audio_local.audio_uuid';

/// Acceso a `audios` (sincronizada) y `audio_local` (solo local).
class AudioLocalDataSource {
  AudioLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<AudioAssetModel>> getAll() async {
    final rows = await _database.rawQuery(_select);
    return rows.map(AudioAssetModel.fromMap).toList(growable: false);
  }

  Future<AudioAssetModel?> getByUuid(String uuid) async {
    final rows = await _database.rawQuery('$_select WHERE audios.uuid = ? LIMIT 1', [uuid]);
    return rows.isEmpty ? null : AudioAssetModel.fromMap(rows.first);
  }

  /// Devuelve el uuid del audio creado.
  Future<String> insertRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) async {
    final values = _sync.withInsertMetadata({
      'kind': 'grabacion',
      'title': title,
      'description': description,
      'duration_seconds': duration.inSeconds,
    });
    final uuid = values['uuid'] as String;

    await _database.insert('audios', values);
    await _database.insert('audio_local', {
      'audio_uuid': uuid,
      'local_path': localPath,
      'remote_url': null,
    });
    // El payload lleva SOLO columnas de `audios`: local_path/remote_url no se sincronizan.
    await _sync.enqueueOutbox(tableName: 'audios', recordUuid: uuid, op: 'insert', payload: values);
    return uuid;
  }

  Future<void> updateDuration({required String uuid, required Duration duration}) =>
      _sync.updateAndEnqueue('audios', uuid, {'duration_seconds': duration.inSeconds});
}
