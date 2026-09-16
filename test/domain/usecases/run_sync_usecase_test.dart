import 'package:cingula_app/data/sync/sync_api.dart';
import 'package:cingula_app/data/sync/sync_client.dart';
import 'package:cingula_app/data/sync/sync_errors.dart';
import 'package:cingula_app/domain/usecases/run_sync_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake escrito a mano: `implements` sobre una clase concreta no invoca su constructor,
/// así que no hace falta ninguna DB real detrás.
class _FakeSyncApi implements SyncApi {
  _FakeSyncApi({List<int>? ackIds, Exception? throwException})
      : _ackIds = ackIds,
        _throwException = throwException;

  final List<int>? _ackIds;
  final Exception? _throwException;
  final String serverCursor = 'server-cursor-test';

  final List<List<Map<String, Object?>>> pushCalls = [];

  @override
  Future<SyncPushResult> pushOutbox({
    required List<Map<String, Object?>> outbox,
    String? cursor,
    String? deviceId,
  }) async {
    pushCalls.add(outbox);
    final exception = _throwException;
    if (exception != null) throw exception;
    final ids = _ackIds ?? outbox.map((row) => row['id'] as int).toList();
    return SyncPushResult(
      ackedIds: ids,
      serverCursor: serverCursor,
      receivedAt: DateTime(2026, 8, 29),
    );
  }

  @override
  Future<SyncStateResult> fetchState() async {
    return SyncStateResult(serverCursor: serverCursor, lastSyncAt: DateTime(2026, 8, 29));
  }

  @override
  Future<SyncPullResult> pullChanges({String? cursor}) async {
    return SyncPullResult(changes: const [], serverCursor: serverCursor);
  }
}

class _FakeSyncClient implements SyncClient {
  _FakeSyncClient({List<Map<String, Object?>>? outbox, String? cursor, String? deviceId})
      : _outbox = outbox ?? const [],
        _cursor = cursor,
        _deviceId = deviceId;

  final List<Map<String, Object?>> _outbox;
  final String? _cursor;
  final String? _deviceId;

  final List<int> ackedIds = [];
  final List<Map<String, Object?>> markedAttempts = [];
  final List<Map<String, Object?>> savedStates = [];

  @override
  Future<Map<String, Object?>> getState() async {
    return {'server_cursor': _cursor, 'device_id': _deviceId};
  }

  @override
  Future<List<Map<String, Object?>>> pendingOutbox({int limit = 50, DateTime? now}) async {
    return _outbox.take(limit).toList();
  }

  @override
  Future<void> ackOutbox(int id) async {
    ackedIds.add(id);
  }

  @override
  Future<void> markAttempt(int id, {required int attemptCount, DateTime? now}) async {
    markedAttempts.add({'id': id, 'attemptCount': attemptCount});
  }

  @override
  Future<void> saveState({String? serverCursor, DateTime? lastSync, String? deviceId}) async {
    savedStates.add({'serverCursor': serverCursor, 'lastSync': lastSync, 'deviceId': deviceId});
  }
}

void main() {
  group('RunSyncUseCase.pushOutboxOnce', () {
    test('outbox vacío: no llama a la API, totalOutbox == 0, hadWork == false', () async {
      final api = _FakeSyncApi();
      final client = _FakeSyncClient(outbox: const []);
      final useCase = RunSyncUseCase(client: client, api: api);

      final result = await useCase.pushOutboxOnce();

      expect(result.totalOutbox, 0);
      expect(result.hadWork, isFalse);
      expect(api.pushCalls, isEmpty);
    });

    test('todos acked: ackOutbox por cada id, nunca markAttempt, se guarda estado', () async {
      final outbox = [
        {'id': 1, 'attempt_count': 0},
        {'id': 2, 'attempt_count': 0},
      ];
      final api = _FakeSyncApi();
      final client = _FakeSyncClient(outbox: outbox);
      final useCase = RunSyncUseCase(client: client, api: api);

      final result = await useCase.pushOutboxOnce();

      expect(client.ackedIds, unorderedEquals([1, 2]));
      expect(client.markedAttempts, isEmpty);
      expect(client.savedStates, hasLength(1));
      expect(result.acked, 2);
    });

    test('acked parcial: ackOutbox para el ackeado, markAttempt para el otro con su attemptCount', () async {
      final outbox = [
        {'id': 1, 'attempt_count': 2},
        {'id': 2, 'attempt_count': 5},
      ];
      final api = _FakeSyncApi(ackIds: [1]);
      final client = _FakeSyncClient(outbox: outbox);
      final useCase = RunSyncUseCase(client: client, api: api);

      await useCase.pushOutboxOnce();

      expect(client.ackedIds, [1]);
      expect(client.markedAttempts, [
        {'id': 2, 'attemptCount': 5},
      ]);
    });

    test('doble push idempotente: mismo lote dos veces produce los mismos acks sin markAttempt extra', () async {
      final outbox = [
        {'id': 1, 'attempt_count': 0},
      ];
      final api = _FakeSyncApi();
      final client = _FakeSyncClient(outbox: outbox);
      final useCase = RunSyncUseCase(client: client, api: api);

      await useCase.pushOutboxOnce();
      await useCase.pushOutboxOnce();

      expect(client.ackedIds, [1, 1]);
      expect(client.markedAttempts, isEmpty);
    });

    test('SyncTransientException: markAttempt para todas las filas, sin ack, sin guardar estado, se propaga', () async {
      final outbox = [
        {'id': 1, 'attempt_count': 1},
        {'id': 2, 'attempt_count': 3},
      ];
      final api = _FakeSyncApi(throwException: SyncTransientException('boom'));
      final client = _FakeSyncClient(outbox: outbox);
      final useCase = RunSyncUseCase(client: client, api: api);

      await expectLater(
        () => useCase.pushOutboxOnce(),
        throwsA(isA<SyncTransientException>()),
      );

      expect(client.ackedIds, isEmpty);
      expect(client.savedStates, isEmpty);
      expect(client.markedAttempts, unorderedEquals([
        {'id': 1, 'attemptCount': 1},
        {'id': 2, 'attemptCount': 3},
      ]));
    });

    test('SyncAuthException: no markAttempt para ninguna fila (D-03), sin ack, se propaga', () async {
      final outbox = [
        {'id': 1, 'attempt_count': 1},
        {'id': 2, 'attempt_count': 3},
      ];
      final api = _FakeSyncApi(throwException: SyncAuthException('nope'));
      final client = _FakeSyncClient(outbox: outbox);
      final useCase = RunSyncUseCase(client: client, api: api);

      await expectLater(
        () => useCase.pushOutboxOnce(),
        throwsA(isA<SyncAuthException>()),
      );

      expect(client.ackedIds, isEmpty);
      expect(client.markedAttempts, isEmpty);
      expect(client.savedStates, isEmpty);
    });
  });
}
