/// API endpoints and base URLs for sync and future HTTP clients.
/// Base URL can be overridden at compile time with
/// `--dart-define=CINGULA_API_BASE_URL=https://api.example.com`.
class ApiConfig {
  ApiConfig._();

  static const String _defaultBaseUrl = String.fromEnvironment(
    'CINGULA_API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Mutable base URL for runtime overrides (e.g. debug panel input).
  static String baseUrl = _defaultBaseUrl;

  /// Token compartido con el backend. Se fija en tiempo de compilación con
  /// `--dart-define=CINGULA_SYNC_API_KEY=<token>` (D-02: sin login, sin rotación).
  /// Vacío = la app no puede autenticar y el backend va a responder 401.
  static const String _defaultApiKey = String.fromEnvironment(
    'CINGULA_SYNC_API_KEY',
    defaultValue: '',
  );

  /// Mutable para overrides en runtime desde el panel de debug (mismo patrón que [baseUrl]).
  static String apiKey = _defaultApiKey;

  static Uri syncPushUri({String? overrideBase}) {
    return _buildUri('/sync/push', overrideBase: overrideBase);
  }

  static Uri syncStateUri({String? overrideBase}) {
    return _buildUri('/sync/state', overrideBase: overrideBase);
  }

  static Uri syncChangesUri({String? overrideBase, String? cursor}) {
    final base = _stripTrailingSlash(overrideBase ?? baseUrl);
    final path = '/sync/changes';
    if (cursor == null || cursor.isEmpty) {
      return Uri.parse('$base$path');
    }
    return Uri.parse('$base$path?cursor=${Uri.encodeQueryComponent(cursor)}');
  }

  static Uri _buildUri(String path, {String? overrideBase}) {
    final base = _stripTrailingSlash(overrideBase ?? baseUrl);
    return Uri.parse('$base$path');
  }

  static String _stripTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
