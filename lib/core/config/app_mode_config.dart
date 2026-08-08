import 'package:shared_preferences/shared_preferences.dart';

/// Modo de la app: panel de debug vs. dashboard de usuario final (UI-01).
/// Persistido con SharedPreferences, mismo patrón que [LocationConfig].
class AppModeConfig {
  static const _kIsDebugMode = 'app_isDebugMode';

  /// Default: modo debug (D-08). El usuario vive hoy en el panel de debug
  /// para grabar y diagnosticar; pasa a modo usuario solo si lo activa.
  static bool isDebugMode = true;

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isDebugMode = prefs.getBool(_kIsDebugMode) ?? true;
    } catch (_) {
      // Silenciar errores de preferencias; usar el default (debug).
    }
  }

  static Future<void> setDebugMode(bool value) async {
    isDebugMode = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsDebugMode, value);
    } catch (_) {
      // Silenciar: el cambio ya aplicó en memoria para esta sesión.
    }
  }
}
