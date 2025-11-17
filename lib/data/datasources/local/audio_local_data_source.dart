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
}

