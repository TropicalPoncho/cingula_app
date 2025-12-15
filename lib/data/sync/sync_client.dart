import '../datasources/local/sync_local_data_source.dart';

/// Cliente mínimo de sincronización que opera solo en lo local.
/// Integraremos HTTP más adelante; por ahora expone lectura de outbox
/// y persistencia de cursor de servidor para pruebas manuales.
class SyncClient {
  SyncClient({required SyncLocalDataSource sync}) : _sync = sync;

  final SyncLocalDataSource _sync;

  /// Devuelve lote de outbox listo para enviar.
  Future<List<Map<String, Object?>>> pendingOutbox({int limit = 50}) {
    return _sync.readOutbox(limit: limit);
  }

  /// Marca un elemento como entregado (lo elimina).
  Future<void> ackOutbox(int id) => _sync.deleteOutboxById(id);

  /// Marca un intento fallido incrementando contador.
  Future<void> markAttempt(int id) => _sync.incrementOutboxAttempt(id);

  /// Obtiene estado local de sync (cursor, device_id).
  Future<Map<String, Object?>> getState() => _sync.getSyncState();

  /// Actualiza estado local tras ciclo de sync.
  Future<void> saveState({String? serverCursor, DateTime? lastSync, String? deviceId}) async {
    await _sync.upsertSyncState(
      serverCursor: serverCursor,
      lastSyncAt: lastSync != null ? lastSync.millisecondsSinceEpoch ~/ 1000 : null,
      deviceId: deviceId,
    );
  }
}
