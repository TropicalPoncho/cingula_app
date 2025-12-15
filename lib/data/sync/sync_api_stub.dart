import 'dart:developer';

import 'sync_client.dart';

/// Stub de red para ilustrar cómo consumir `SyncClient`.
/// No realiza llamadas HTTP; simplemente imprime el outbox pendiente
/// y marca como reconocido (ack) en local.
class SyncApiStub {
  SyncApiStub(this._client);

  final SyncClient _client;

  /// Realiza un ciclo de sincronización ficticio:
  /// - Lee outbox
  /// - "Envía" (log)
  /// - Ack en local
  /// - Actualiza cursor/lastSync
  Future<void> syncOnce() async {
    final outbox = await _client.pendingOutbox(limit: 50);
    if (outbox.isEmpty) {
      log('[SyncStub] Outbox vacío');
      return;
    }

    for (final item in outbox) {
      final id = item['id'] as int?;
      log('[SyncStub] Enviando -> $item');
      if (id != null) {
        await _client.ackOutbox(id);
      }
    }

    await _client.saveState(
      serverCursor: 'stub-cursor',
      lastSync: DateTime.now(),
    );
    log('[SyncStub] Sync ficticia completada');
  }
}