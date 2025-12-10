import 'package:sqflite/sqflite.dart';

import '../../models/audio_asset_model.dart';

/// Lecturas sobre la tabla de audios persistidos.
class AudioLocalDataSource {
  AudioLocalDataSource(this._database);

  final Database _database;

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
    return _database.insert('audio_assets', {
      'title': title,
      'artist': 'Field Recording',
      'description': description,
      'duration_seconds': duration.inSeconds,
      'local_path': localPath,
      'remote_url': null,
    });
  }

  Future<void> updateDuration({required int id, required Duration duration}) async {
    await _database.update(
      'audio_assets',
      {'duration_seconds': duration.inSeconds},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

