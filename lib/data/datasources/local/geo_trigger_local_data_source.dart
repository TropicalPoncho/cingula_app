import 'package:sqflite/sqflite.dart';

import '../../models/geo_trigger_model.dart';

/// Acceso directo a la tabla de geozonas configuradas.
class GeoTriggerLocalDataSource {
  GeoTriggerLocalDataSource(this._database);

  final Database _database;

  Future<List<GeoTriggerModel>> getAll() async {
    final rows = await _database.query('geo_triggers');
    return rows.map(GeoTriggerModel.fromMap).toList(growable: false);
  }

  Future<List<GeoTriggerModel>> fetchByPathId(int pathId) async {
    final rows = await _database.query('geo_triggers', where: 'geo_path_id = ?', whereArgs: [pathId]);
    return rows.map(GeoTriggerModel.fromMap).toList(growable: false);
  }

  /// Borra todos los triggers asociados a un audioAssetId y devuelve el número de filas borradas.
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    return await _database.delete('geo_triggers', where: 'audio_asset_id = ?', whereArgs: [audioAssetId]);
  }

  /// Inserta un nuevo trigger y devuelve el id insertado.
  Future<int> insertTrigger(Map<String, Object?> values) async {
    return await _database.insert('geo_triggers', values);
  }
}

