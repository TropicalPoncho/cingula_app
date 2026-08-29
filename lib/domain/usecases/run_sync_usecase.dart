import '../../data/sync/sync_api.dart';
import '../../data/sync/sync_client.dart';

/// Caso de uso simple que empuja el outbox al servidor y confirma acks.
class RunSyncUseCase {
  RunSyncUseCase({required SyncClient client, required SyncApi api})
      : _client = client,
        _api = api;

  final SyncClient _client;
  final SyncApi _api;

  /// Empuja un lote del outbox y actualiza el estado local usando los acks recibidos.
  Future<SyncRunResult> pushOutboxOnce({int limit = 50}) async {
    final state = await _client.getState();
    final outbox = await _client.pendingOutbox(limit: limit);
    final cursor = state['server_cursor'] as String?;
    final deviceId = state['device_id'] as String?;

    if (outbox.isEmpty) {
      return SyncRunResult(
        totalOutbox: 0,
        acked: 0,
        serverCursor: cursor,
        syncedAt: DateTime.now(),
      );
    }

    final response = await _api.pushOutbox(
      outbox: outbox,
      cursor: cursor,
      deviceId: deviceId,
    );

    final ackedSet = response.ackedIds.toSet();
    final sentIds = outbox.map((row) => row['id']).whereType<int>().toSet();

    for (final id in ackedSet) {
      await _client.ackOutbox(id);
    }

    // Incrementar contador de intentos y agendar backoff para los que no se confirmaron.
    final byId = {for (final row in outbox) row['id'] as int: row};
    for (final id in sentIds.difference(ackedSet)) {
      await _client.markAttempt(id, attemptCount: (byId[id]?['attempt_count'] as int?) ?? 0);
    }

    await _client.saveState(
      serverCursor: response.serverCursor,
      lastSync: response.receivedAt,
      deviceId: deviceId,
    );

    return SyncRunResult(
      totalOutbox: outbox.length,
      acked: response.ackedIds.length,
      serverCursor: response.serverCursor,
      syncedAt: response.receivedAt,
    );
  }
}

class SyncRunResult {
  SyncRunResult({
    required this.totalOutbox,
    required this.acked,
    required this.serverCursor,
    required this.syncedAt,
  });

  final int totalOutbox;
  final int acked;
  final String? serverCursor;
  final DateTime syncedAt;

  bool get hadWork => totalOutbox > 0;
  int get unacked => totalOutbox - acked;
}
