import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/region_model.dart';
import '../../../domain/value_objects/coordinate.dart';

class RegionLocalDataSource {
  RegionLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

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
    final stamped = _sync.withInsertMetadata(values);
    final id = await _database.insert('regions', stamped);
    await _sync.enqueueOutbox(
      tableName: 'regions',
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
