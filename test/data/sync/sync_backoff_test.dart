import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cingula_app/data/sync/sync_backoff.dart';

void main() {
  group('fullJitterBackoff', () {
    test('attempt 0: resultado en [0ms, 2000ms]', () {
      for (var i = 0; i < 100; i++) {
        final d = fullJitterBackoff(0);
        expect(d.inMilliseconds, inInclusiveRange(0, 2000));
      }
    });

    test('attempt 3: resultado en [0ms, 16000ms]', () {
      for (var i = 0; i < 100; i++) {
        final d = fullJitterBackoff(3);
        expect(d.inMilliseconds, inInclusiveRange(0, 16000));
      }
    });

    test('attempt 30: nunca supera el cap de 5 minutos', () {
      for (var i = 0; i < 100; i++) {
        final d = fullJitterBackoff(30);
        expect(d.inMilliseconds, inInclusiveRange(0, kBackoffCap.inMilliseconds));
      }
    });

    test('attempt -1 se trata como attempt 0, no lanza excepción', () {
      expect(() => fullJitterBackoff(-1), returnsNormally);
      for (var i = 0; i < 100; i++) {
        final d = fullJitterBackoff(-1);
        expect(d.inMilliseconds, inInclusiveRange(0, 2000));
      }
    });

    test('con Random sembrado el resultado es determinista', () {
      final a = fullJitterBackoff(3, random: Random(42));
      final b = fullJitterBackoff(3, random: Random(42));
      expect(a, equals(b));
    });
  });

  group('isOutboxRowEligible', () {
    test('next_attempt_at null es elegible', () {
      expect(
        isOutboxRowEligible({'next_attempt_at': null}, nowSeconds: 100),
        isTrue,
      );
    });

    test('next_attempt_at == now es elegible (borde inclusivo)', () {
      expect(
        isOutboxRowEligible({'next_attempt_at': 100}, nowSeconds: 100),
        isTrue,
      );
    });

    test('next_attempt_at > now no es elegible', () {
      expect(
        isOutboxRowEligible({'next_attempt_at': 101}, nowSeconds: 100),
        isFalse,
      );
    });

    test('fila sin la clave next_attempt_at es elegible', () {
      expect(
        isOutboxRowEligible({}, nowSeconds: 100),
        isTrue,
      );
    });
  });
}
