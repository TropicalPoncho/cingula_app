/// API contract to push/pull sync data against the server.
abstract class SyncApi {
  Future<SyncPushResult> pushOutbox({
    required List<Map<String, Object?>> outbox,
    String? cursor,
    String? deviceId,
  });

  Future<SyncStateResult> fetchState();

  Future<SyncPullResult> pullChanges({String? cursor});
}

class SyncPushResult {
  SyncPushResult({
    required this.ackedIds,
    required this.serverCursor,
    required this.receivedAt,
  });

  final List<int> ackedIds;
  final String serverCursor;
  final DateTime receivedAt;
}

class SyncStateResult {
  SyncStateResult({
    required this.serverCursor,
    required this.lastSyncAt,
  });

  final String? serverCursor;
  final DateTime? lastSyncAt;
}

class SyncPullResult {
  SyncPullResult({
    required this.changes,
    required this.serverCursor,
  });

  final List<Map<String, Object?>> changes;
  final String serverCursor;
}
