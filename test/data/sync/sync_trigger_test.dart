import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cingula_app/data/sync/sync_errors.dart';
import 'package:cingula_app/data/sync/sync_trigger.dart';
import 'package:cingula_app/domain/usecases/run_sync_usecase.dart';

/// Fake sobre la clase concreta `RunSyncUseCase` (implements: legal en Dart,
/// no invoca su constructor, no necesita SyncClient/SyncApi/DB reales).
class _FakeRunSync implements RunSyncUseCase {
  int callCount = 0;

  /// Cuando true, cada llamada a pushOutboxOnce se bloquea hasta que el test
  /// llame a completeNext() — permite probar la no-reentrancia con precisión.
  bool manualCompletion = false;
  final List<Completer<void>> _pending = [];

  /// Si no es null, se lanza en la próxima llamada (una vez).
  Object? nextError;

  @override
  Future<SyncRunResult> pushOutboxOnce({int limit = 50}) async {
    callCount++;
    if (manualCompletion) {
      final completer = Completer<void>();
      _pending.add(completer);
      await completer.future;
    }
    final err = nextError;
    if (err != null) {
      nextError = null;
      throw err;
    }
    return SyncRunResult(
      totalOutbox: 0,
      acked: 0,
      serverCursor: null,
      syncedAt: DateTime.now(),
    );
  }

  void completeNext() {
    if (_pending.isNotEmpty) {
      _pending.removeAt(0).complete();
    }
  }
}

void main() {
  group('SyncTrigger', () {
    test('schedule() x5 dentro de la ventana de debounce produce UN solo push', () async {
      final fake = _FakeRunSync();
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      for (var i = 0; i < 5; i++) {
        trigger.schedule();
      }
      await Future.delayed(const Duration(milliseconds: 50));

      expect(fake.callCount, 1);
      trigger.dispose();
    });

    test('schedule() durante un push en vuelo no arranca uno concurrente; encola una re-corrida', () async {
      final fake = _FakeRunSync()..manualCompletion = true;
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      final flushFuture = trigger.flush();
      await Future.delayed(const Duration(milliseconds: 5));
      expect(fake.callCount, 1);

      // Pide una re-corrida mientras el primer push sigue bloqueado.
      trigger.schedule();
      await Future.delayed(const Duration(milliseconds: 30));
      // El debounce ya venció, pero como hay un push en vuelo NO debe haber
      // un segundo pushOutboxOnce corriendo en paralelo.
      expect(fake.callCount, 1);

      fake.completeNext(); // termina el primer push -> dispara la re-corrida encolada
      await Future.delayed(const Duration(milliseconds: 5));
      expect(fake.callCount, 2);

      fake.completeNext(); // termina la re-corrida
      await flushFuture;
      trigger.dispose();
    });

    test('después de un push exitoso, lastStatus es ok', () async {
      final fake = _FakeRunSync();
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      await trigger.flush();

      expect(trigger.lastStatus, SyncTriggerStatus.ok);
      trigger.dispose();
    });

    test('SyncTransientException produce lastStatus transientError y no se propaga', () async {
      final fake = _FakeRunSync()..nextError = SyncTransientException('boom');
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      await expectLater(trigger.flush(), completes);

      expect(trigger.lastStatus, SyncTriggerStatus.transientError);
      trigger.dispose();
    });

    test('SyncAuthException produce lastStatus authError', () async {
      final fake = _FakeRunSync()..nextError = SyncAuthException('bad key');
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      await expectLater(trigger.flush(), completes);

      expect(trigger.lastStatus, SyncTriggerStatus.authError);
      trigger.dispose();
    });

    test('cada cambio de estado se emite por statusStream', () async {
      final fake = _FakeRunSync();
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      final statuses = <SyncTriggerStatus>[];
      final sub = trigger.statusStream.listen(statuses.add);

      await trigger.flush();
      await Future.delayed(const Duration(milliseconds: 5));

      expect(statuses, [SyncTriggerStatus.running, SyncTriggerStatus.ok]);
      await sub.cancel();
      trigger.dispose();
    });

    test('dispose() cancela el timer pendiente y cierra el stream sin lanzar', () async {
      final fake = _FakeRunSync();
      final trigger = SyncTrigger(runSync: fake, debounce: const Duration(milliseconds: 10));

      trigger.schedule();
      expect(() => trigger.dispose(), returnsNormally);

      // El timer cancelado no debe disparar un push tardío.
      await Future.delayed(const Duration(milliseconds: 30));
      expect(fake.callCount, 0);
    });
  });
}
