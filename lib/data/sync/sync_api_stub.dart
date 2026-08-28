import 'dart:developer';

import 'sync_api.dart';

/// Stub remoto para probar flujo de sincronizacion sin HTTP real.
class SyncApiStub implements SyncApi {
  @override
  Future<SyncPushResult> pushOutbox({
    required List<Map<String, Object?>> outbox,
    String? cursor,
    String? deviceId,
  }) async {
    if (outbox.isEmpty) {
      log('[SyncStub] Outbox vacio');
      return SyncPushResult(
        ackedIds: const [],
        serverCursor: cursor ?? 'stub-cursor',
        receivedAt: DateTime.now(),
      );
    }

    final ackedIds = <int>[];
    for (final item in outbox) {
      final id = item['id'];
      log('[SyncStub] Enviando -> $item');
      if (id is int) {
        ackedIds.add(id);
      }
    }

    return SyncPushResult(
      ackedIds: ackedIds,
      serverCursor: cursor ?? 'stub-cursor',
      receivedAt: DateTime.now(),
    );
  }

  @override
  Future<SyncStateResult> fetchState() async {
    return SyncStateResult(
      serverCursor: 'stub-cursor',
      lastSyncAt: DateTime.now(),
    );
  }

  @override
  Future<SyncPullResult> pullChanges({String? cursor}) async {
    return SyncPullResult(
      changes: const [],
      serverCursor: cursor ?? 'stub-cursor',
    );
  }
}