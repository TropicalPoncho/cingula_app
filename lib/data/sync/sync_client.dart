import '../datasources/local/sync_local_data_source.dart';
import 'sync_backoff.dart';

/// Cliente mínimo de sincronización que opera solo en lo local.
/// Integraremos HTTP más adelante; por ahora expone lectura de outbox
/// y persistencia de cursor de servidor para pruebas manuales.
class SyncClient {
  SyncClient({required SyncLocalDataSource sync}) : _sync = sync;

  final SyncLocalDataSource _sync;

  /// Devuelve el lote de outbox listo para enviar, salteando filas que están en backoff.
  Future<List<Map<String, Object?>>> pendingOutbox({int limit = 50, DateTime? now}) async {
    final rows = await _sync.readOutbox(limit: limit);
    final nowSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    // ponytail: corte por cabeza (takeWhile), no filtro global. Si la fila más vieja está en
    // backoff frenamos ahí a propósito: mantiene el orden FIFO global, que es lo que impide
    // que una versión nueva de una entidad llegue al servidor antes que una vieja.
    return rows
        .takeWhile((row) => isOutboxRowEligible(row, nowSeconds: nowSeconds))
        .toList(growable: false);
  }

  /// Marca un elemento como entregado (lo elimina).
  Future<void> ackOutbox(int id) => _sync.deleteOutboxById(id);

  /// Marca un intento fallido: incrementa el contador y agenda el próximo intento
  /// con Full Jitter sobre el número de intentos ya acumulado.
  Future<void> markAttempt(int id, {required int attemptCount, DateTime? now}) async {
    final base = now ?? DateTime.now();
    final nextAt = base.add(fullJitterBackoff(attemptCount));
    await _sync.incrementOutboxAttempt(
      id,
      nextAttemptAt: nextAt.millisecondsSinceEpoch ~/ 1000,
    );
  }

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
