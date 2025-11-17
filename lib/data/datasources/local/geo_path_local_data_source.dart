import 'package:sqflite/sqflite.dart';

import '../../models/geo_path_model.dart';
// GeoPathLocalDataSource no longer handles storing raw point arrays. Path
// geometry is modelled by GeoTriggers that reference geo_path_id.

/// Acceso a la tabla `geo_paths`.
class GeoPathLocalDataSource {
  GeoPathLocalDataSource(this._database);

  final Database _database;

  Future<List<GeoPathModel>> getAll() async {
    final rows = await _database.query('geo_paths');
    return rows.map(GeoPathModel.fromMap).toList(growable: false);
  }
  /// Inserta un nuevo geo path y devuelve el id insertado.
  Future<int> insertPath(Map<String, Object?> values) async {
    return await _database.insert('geo_paths', values);
  }

  Future<void> saveProgress(int pathId, int offsetMs) async {
    await _database.update(
      'geo_paths',
      {'saved_offset_ms': offsetMs},
      where: 'id = ?',
      whereArgs: [pathId],
    );
  }

  /// Borra paths (metadata) asociados a un audio y devuelve el número de filas borradas.
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    return await _database.delete('geo_paths', where: 'audio_asset_id = ?', whereArgs: [audioAssetId]);
  }
}
