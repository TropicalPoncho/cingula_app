import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import 'sync_api.dart';
import 'sync_errors.dart';

/// Implementación real de [SyncApi] contra el backend de Vercel + Neon.
class SyncApiHttp implements SyncApi {
  SyncApiHttp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${ApiConfig.apiKey}',
        'Content-Type': 'application/json',
      };

  @override
  Future<SyncPushResult> pushOutbox({
    required List<Map<String, Object?>> outbox,
    String? cursor,
    String? deviceId,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        ApiConfig.syncPushUri(),
        headers: _headers,
        body: jsonEncode({'outbox': outbox, 'cursor': cursor, 'deviceId': deviceId}),
      );
    } catch (e) {
      // Sin respuesta = no llegamos al servidor: transitorio por definición.
      throw SyncTransientException('network failure: $e');
    }

    _throwForStatus(response);

    final body = jsonDecode(response.body) as Map<String, Object?>;
    return SyncPushResult(
      ackedIds: (body['ackedIds'] as List? ?? const []).cast<int>(),
      serverCursor: (body['serverCursor'] as String?) ?? cursor ?? '',
      receivedAt: DateTime.parse(body['receivedAt'] as String),
    );
  }

  // ponytail: sin llamadores hoy (ni el panel, ni RunSyncUseCase) fuera de sus propios
  // tests; existe porque SyncApi lo declara como parte del contrato. Si la Fase 3 no
  // termina usándolo, sacar el método del contrato en vez de dejarlo sin uso.
  @override
  Future<SyncStateResult> fetchState() async {
    final http.Response response;
    try {
      response = await _client.get(ApiConfig.syncStateUri(), headers: _headers);
    } catch (e) {
      throw SyncTransientException('network failure: $e');
    }
    _throwForStatus(response);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final lastSyncAt = body['lastSyncAt'] as String?;
    return SyncStateResult(
      serverCursor: body['serverCursor'] as String?,
      lastSyncAt: lastSyncAt == null ? null : DateTime.parse(lastSyncAt),
    );
  }

  @override
  Future<SyncPullResult> pullChanges({String? cursor}) {
    // El pull es Fase 3 (SYNC-04/SYNC-05). Falla ruidosamente en vez de devolver
    // una lista vacía que parecería "no hay cambios".
    throw UnimplementedError('pullChanges llega en la Fase 3 (sync bidireccional)');
  }

  /// Clasifica la respuesta: 401 es terminal, cualquier otro no-200 es transitorio.
  /// Compartido por pushOutbox/fetchState -- ambos hacían la misma clasificación inline.
  void _throwForStatus(http.Response response) {
    if (response.statusCode == 401) {
      throw SyncAuthException('API key rechazada (401)');
    }
    if (response.statusCode != 200) {
      // ponytail: todo lo no-200 y no-401 es transitorio. Un 400 tampoco va a andar
      // reintentando, pero inventar una tercera categoría de error para un caso que
      // sólo aparece con un bug de payload no paga (research Open Question 1).
      throw SyncTransientException('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
