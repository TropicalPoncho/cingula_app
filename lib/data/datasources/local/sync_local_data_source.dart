import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Pequeñas utilidades para metadatos de sincronización y outbox.
class SyncLocalDataSource {
  SyncLocalDataSource(this._database, {Uuid? uuidGenerator})
      : _uuid = uuidGenerator ?? const Uuid();

  final Database _database;
  final Uuid _uuid;

  /// Se invoca después de encolar una fila de outbox. El service locator lo cablea a
  /// SyncTrigger.schedule() para que cada escritura local dispare un push (D-04).
  /// Nullable a propósito: en tests y en el arranque temprano puede no haber trigger todavía.
  void Function()? onOutboxEnqueued;

  /// Epoch seconds helper.
  int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Genera un nuevo UUID v4.
  String newUuid() => _uuid.v4();

  /// Agrega uuid/updated_at/logical_version iniciales para inserciones.
  Map<String, Object?> withInsertMetadata(Map<String, Object?> values) {
    return {
      ...values,
      'uuid': values['uuid'] ?? newUuid(),
      'updated_at': _nowSeconds(),
      'logical_version': values['logical_version'] ?? 1,
      'deleted_at': values['deleted_at'],
    };
  }

  /// Agrega updated_at y bump de logical_version para actualizaciones o soft deletes.
  Map<String, Object?> withUpdateMetadata(Map<String, Object?> values) {
    final currentVersion = values['logical_version'] as int?;
    final nextVersion = currentVersion != null ? currentVersion + 1 : 1;
    return {
      ...values,
      'updated_at': _nowSeconds(),
      'logical_version': nextVersion,
    };
  }

  /// Inserta en el outbox una operación pendiente de sincronización.
  Future<void> enqueueOutbox({
    required String tableName,
    required String recordUuid,
    required String op,
    Map<String, Object?>? payload,
    String? deviceId,
  }) async {
    await _database.insert('sync_outbox', {
      'table_name': tableName,
      'record_uuid': recordUuid,
      'op': op,
      'payload': payload == null ? null : jsonEncode(payload),
      'device_id': deviceId,
      'created_at': _nowSeconds(),
      'attempt_count': 0,
      'next_attempt_at': null,
    });
    onOutboxEnqueued?.call();
  }

  /// Lee el outbox ordenado por creación, limita resultados y los devuelve con payload ya decodificado.
  Future<List<Map<String, Object?>>> readOutbox({int limit = 50}) async {
    final rows = await _database.query(
      'sync_outbox',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows
        .map((row) => {
              ...row,
              'payload': row['payload'] != null ? jsonDecode(row['payload'] as String) : null,
            })
        .toList(growable: false);
  }

  /// Elimina una fila de outbox una vez confirmada por el servidor.
  Future<void> deleteOutboxById(int id) async {
    await _database.delete('sync_outbox', where: 'id = ?', whereArgs: [id]);
  }

  /// Incrementa el contador de intentos y agenda cuándo la fila vuelve a ser elegible.
  /// [nextAttemptAt] son epoch seconds; null = elegible inmediatamente.
  Future<void> incrementOutboxAttempt(int id, {int? nextAttemptAt}) async {
    await _database.rawUpdate(
      'UPDATE sync_outbox SET attempt_count = attempt_count + 1, next_attempt_at = ? WHERE id = ?',
      [nextAttemptAt, id],
    );
  }

  /// Obtiene el estado de sincronización (cursor y device_id si existe).
  Future<Map<String, Object?>> getSyncState() async {
    final rows = await _database.query('sync_state', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return {'id': 1, 'server_cursor': null, 'last_sync_at': null, 'device_id': null};
    return rows.first;
  }

  /// Persiste el estado de sincronización (upsert id=1).
  Future<void> upsertSyncState({String? serverCursor, int? lastSyncAt, String? deviceId}) async {
    await _database.insert(
      'sync_state',
      {
        'id': 1,
        'server_cursor': serverCursor,
        'last_sync_at': lastSyncAt,
        'device_id': deviceId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
