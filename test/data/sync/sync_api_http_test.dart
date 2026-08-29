import 'dart:convert';

import 'package:cingula_app/core/config/api_config.dart';
import 'package:cingula_app/data/sync/sync_api_http.dart';
import 'package:cingula_app/data/sync/sync_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    ApiConfig.baseUrl = 'http://test.local';
    ApiConfig.apiKey = 'test-key';
  });

  tearDown(() {
    ApiConfig.baseUrl = 'http://localhost:3000';
    ApiConfig.apiKey = '';
  });

  group('pushOutbox', () {
    test('envía POST a {baseUrl}/sync/push con headers y body correctos', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ackedIds': [1],
            'serverCursor': 'c1',
            'receivedAt': '2026-08-29T12:00:00.000Z',
          }),
          200,
        );
      });
      final api = SyncApiHttp(client: client);

      final outbox = [
        {'id': 1, 'table_name': 'geo_triggers', 'payload': <String, Object?>{}},
      ];
      await api.pushOutbox(outbox: outbox, cursor: 'cur-0', deviceId: 'dev-1');

      expect(captured, isNotNull);
      expect(captured!.url.toString(), 'http://test.local/sync/push');
      expect(captured!.headers['Authorization'], 'Bearer test-key');
      expect(captured!.headers['Content-Type'], 'application/json');

      final decoded = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(decoded.containsKey('outbox'), isTrue);
      expect(decoded.containsKey('cursor'), isTrue);
      expect(decoded.containsKey('deviceId'), isTrue);
    });

    test('el array outbox del body es idéntico al que se pasó', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ackedIds': <int>[],
            'serverCursor': 'c1',
            'receivedAt': '2026-08-29T12:00:00.000Z',
          }),
          200,
        );
      });
      final api = SyncApiHttp(client: client);

      final outbox = [
        {
          'id': 12,
          'table_name': 'geo_triggers',
          'record_uuid': '8f14e45f',
          'op': 'update',
          'payload': {'id': 3, 'name': 'x'},
          'device_id': 'abc-123',
          'created_at': 1756400000,
          'attempt_count': 0,
          'next_attempt_at': null,
        },
      ];
      await api.pushOutbox(outbox: outbox, cursor: null, deviceId: null);

      final decoded = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(decoded['outbox'], outbox);
    });

    test('200 produce un SyncPushResult con los tres valores parseados', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ackedIds': [1, 2],
            'serverCursor': 'c2',
            'receivedAt': '2026-08-29T12:00:00.000Z',
          }),
          200,
        );
      });
      final api = SyncApiHttp(client: client);

      final result = await api.pushOutbox(outbox: const [], cursor: 'c0');

      expect(result.ackedIds, [1, 2]);
      expect(result.serverCursor, 'c2');
      expect(result.receivedAt, DateTime.parse('2026-08-29T12:00:00.000Z'));
    });

    test('serverCursor null cae de vuelta al cursor enviado', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ackedIds': <int>[],
            'serverCursor': null,
            'receivedAt': '2026-08-29T12:00:00.000Z',
          }),
          200,
        );
      });
      final api = SyncApiHttp(client: client);

      final result = await api.pushOutbox(outbox: const [], cursor: 'sent-cursor');

      expect(result.serverCursor, 'sent-cursor');
    });

    test('serverCursor null y sin cursor enviado cae a string vacío', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ackedIds': <int>[],
            'serverCursor': null,
            'receivedAt': '2026-08-29T12:00:00.000Z',
          }),
          200,
        );
      });
      final api = SyncApiHttp(client: client);

      final result = await api.pushOutbox(outbox: const []);

      expect(result.serverCursor, '');
    });

    test('401 lanza SyncAuthException', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'invalid or missing API key'}), 401);
      });
      final api = SyncApiHttp(client: client);

      expect(
        () => api.pushOutbox(outbox: const []),
        throwsA(isA<SyncAuthException>()),
      );
    });

    test('500 lanza SyncTransientException', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final api = SyncApiHttp(client: client);

      expect(
        () => api.pushOutbox(outbox: const []),
        throwsA(isA<SyncTransientException>()),
      );
    });

    test('503 lanza SyncTransientException', () async {
      final client = MockClient((request) async => http.Response('unavailable', 503));
      final api = SyncApiHttp(client: client);

      expect(
        () => api.pushOutbox(outbox: const []),
        throwsA(isA<SyncTransientException>()),
      );
    });

    test('408 lanza SyncTransientException', () async {
      final client = MockClient((request) async => http.Response('timeout', 408));
      final api = SyncApiHttp(client: client);

      expect(
        () => api.pushOutbox(outbox: const []),
        throwsA(isA<SyncTransientException>()),
      );
    });

    test('400 lanza SyncTransientException con el mensaje del cuerpo incluido', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'error': 'bad payload'}), 400),
      );
      final api = SyncApiHttp(client: client);

      await expectLater(
        () => api.pushOutbox(outbox: const []),
        throwsA(
          isA<SyncTransientException>().having(
            (e) => e.message,
            'message',
            contains('bad payload'),
          ),
        ),
      );
    });

    test('error de red (ClientException) lanza SyncTransientException', () async {
      final client = MockClient((request) async {
        throw http.ClientException('boom');
      });
      final api = SyncApiHttp(client: client);

      expect(
        () => api.pushOutbox(outbox: const []),
        throwsA(isA<SyncTransientException>()),
      );
    });
  });

  group('fetchState', () {
    test('hace GET a {baseUrl}/sync/state con Authorization y parsea la respuesta', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'serverCursor': 'c1',
            'lastSyncAt': '2026-08-29T12:00:00.000Z',
          }),
          200,
        );
      });
      final api = SyncApiHttp(client: client);

      final result = await api.fetchState();

      expect(captured!.method, 'GET');
      expect(captured!.url.toString(), 'http://test.local/sync/state');
      expect(captured!.headers['Authorization'], 'Bearer test-key');
      expect(result.serverCursor, 'c1');
      expect(result.lastSyncAt, DateTime.parse('2026-08-29T12:00:00.000Z'));
    });

    test('401 lanza SyncAuthException', () async {
      final client = MockClient((request) async => http.Response('{}', 401));
      final api = SyncApiHttp(client: client);

      expect(() => api.fetchState(), throwsA(isA<SyncAuthException>()));
    });
  });

  group('pullChanges', () {
    test('lanza UnimplementedError', () async {
      final api = SyncApiHttp(client: MockClient((request) async => http.Response('{}', 200)));

      expect(() => api.pullChanges(), throwsA(isA<UnimplementedError>()));
    });
  });
}
