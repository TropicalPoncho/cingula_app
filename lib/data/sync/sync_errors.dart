/// Error terminal: reintentarlo no lo va a arreglar. Hoy sólo lo produce un 401
/// (la API key compilada en el build está mal). Ver D-03 del 02-CONTEXT.md.
class SyncAuthException implements Exception {
  SyncAuthException(this.message);
  final String message;
  @override
  String toString() => 'SyncAuthException: $message';
}

/// Error transitorio: la fila sigue pendiente y se reintenta con backoff.
class SyncTransientException implements Exception {
  SyncTransientException(this.message);
  final String message;
  @override
  String toString() => 'SyncTransientException: $message';
}
