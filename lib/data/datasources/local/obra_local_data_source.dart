import 'package:sqflite/sqflite.dart';

import 'sync_local_data_source.dart';
import '../../models/obra_model.dart';

/// Acceso a `obras`. `artistas`/`obra_artistas` existen vacías y sin consumidor en 2.1.
class ObraLocalDataSource {
  ObraLocalDataSource(this._database, this._sync);

  final Database _database;
  final SyncLocalDataSource _sync;

  Future<List<ObraModel>> getAll() async {
    final rows = await _database.query('obras');
    return rows.map(ObraModel.fromMap).toList(growable: false);
  }

  Future<ObraModel?> findByUuid(String uuid) async {
    final rows = await _database.query('obras', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : ObraModel.fromMap(rows.first);
  }

  Future<String> createDraft(String name) async {
    final values = _sync.withInsertMetadata({'name': name, 'visibility': 'draft'});
    await _database.insert('obras', values);
    final uuid = values['uuid'] as String;
    await _sync.enqueueOutbox(tableName: 'obras', recordUuid: uuid, op: 'insert', payload: values);
    return uuid;
  }
}
