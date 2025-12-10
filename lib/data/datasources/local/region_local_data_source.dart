import 'package:sqflite/sqflite.dart';

import '../../models/region_model.dart';
import '../../../domain/value_objects/coordinate.dart';

class RegionLocalDataSource {
  RegionLocalDataSource(this._database);

  final Database _database;

  Future<List<RegionModel>> getAll() async {
    final rows = await _database.query('regions');
    return rows.map(RegionModel.fromMap).toList(growable: false);
  }

  Future<RegionModel?> findContaining(Coordinate coordinate) async {
    final regions = await getAll();
    for (final r in regions) {
      if (r.contains(coordinate)) return r;
    }
    return null;
  }

  Future<int> insertRegion(Map<String, Object?> values) async {
    return await _database.insert('regions', values);
  }
}
