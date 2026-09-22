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

  /// Aplica [changes] a la fila [uuid] de [table], sube la versión y encola la FILA COMPLETA
  /// (el backend exige las columnas requeridas también en los updates).
  Future<void> updateAndEnqueue(String table, String uuid, Map<String, Object?> changes) async {
    final rows = await _database.query(table, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return;
    final row = {...rows.first, ...changes};
    final values = withUpdateMetadata(row);
    await _database.update(table, values, where: 'uuid = ?', whereArgs: [uuid]);
    await enqueueOutbox(tableName: table, recordUuid: uuid, op: 'update', payload: values);
  }

  /// Encola el borrado (hard delete local) de las filas [rows] (uuid + logical_version) de [table].
  Future<void> enqueueDeletes(String table, List<Map<String, Object?>> rows) async {
    for (final row in rows) {
      final uuid = row['uuid'] as String;
      await enqueueOutbox(
        tableName: table,
        recordUuid: uuid,
        op: 'delete',
        payload: {'uuid': uuid, 'logical_version': ((row['logical_version'] as int?) ?? 0) + 1},
      );
    }
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

  /// Repara filas de outbox `op: delete` encoladas antes de que existiera el arreglo de
  /// la Fase 2 (plan 02-01) que agrega `logical_version` al payload de los deletes.
  /// Sin este campo el backend rechaza el lote ENTERO donde viaja la fila (ver
  /// backend/api/_lib/outbox.js validateOutboxItem), lo que además bloquea todo lo que
  /// está detrás en la cola por el orden FIFO de `SyncClient.pendingOutbox`.
  /// Es seguro poner logical_version=1: estas filas nunca llegaron a un backend real
  /// (SyncApiStub nunca tocó un servidor), así que no hay ninguna versión previa que pisar.
  /// Devuelve la cantidad de filas reparadas.
  Future<int> repairDeleteOutboxPayloads() async {
    final rows = await _database.query(
      'sync_outbox',
      columns: ['id', 'payload'],
      where: "op = 'delete'",
    );

    var repaired = 0;
    for (final row in rows) {
      final rawPayload = row['payload'] as String?;
      final payload = rawPayload == null
          ? <String, Object?>{}
          : jsonDecode(rawPayload) as Map<String, Object?>;
      final version = payload['logical_version'];
      final isValid = version is int && version >= 1;
      if (isValid) continue;

      await _database.update(
        'sync_outbox',
        {'payload': jsonEncode({...payload, 'logical_version': 1})},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      repaired++;
    }
    return repaired;
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
