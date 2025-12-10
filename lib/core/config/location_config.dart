import 'package:shared_preferences/shared_preferences.dart';

/// Parámetros configurables para el muestreo y filtrado de ubicación.
/// Pueden persistirse usando SharedPreferences desde la UI de diagnóstico.
class LocationConfig {
  static const _kCoarsePollingSeconds = 'loc_coarsePollingSeconds';
  static const _kFinePollingSeconds = 'loc_finePollingSeconds';
  static const _kCoarseDistanceFilter = 'loc_coarseDistanceFilterMeters';
  static const _kFineDistanceFilter = 'loc_fineDistanceFilterMeters';
  static const _kAccuracyThreshold = 'loc_accuracyThresholdMeters';
  static const _kPathToleranceDefault = 'loc_pathToleranceDefaultMeters';
  static const _kMinDistanceFilter = 'loc_minDistanceFilterMeters';
  static const _kActivationRadius = 'loc_activationRadiusMeters';

  /// Polling coarse (segundos) usado cuando no hay regiones activas.
  static int coarsePollingSeconds = 30;

  /// Intervalo objetivo (segundos) para muestreo fino dentro de una región.
  static int finePollingSeconds = 2;

  /// Distance filter por defecto para muestreo coarse (metros).
  static int coarseDistanceFilterMeters = 500;

  /// Distance filter por defecto para muestreo fino (metros).
  static int fineDistanceFilterMeters = 5;

  /// Umbral de precisión (accuracy) en metros; lecturas con valor mayor serán ignoradas.
  static double accuracyThresholdMeters = 20.0;

  /// Tolerancia por defecto para paths si no está definida en el path.
  static double pathToleranceDefaultMeters = 10.0;

  /// Valor mínimo recomendado para distanceFilter; algunos dispositivos ignoran valores muy pequeños.
  static int minDistanceFilterMeters = 1;

  /// Radio de activación visible en el mapa (metros) - para debugging/testing.
  static double activationRadiusMeters = 15.0;

  /// Cargar valores persistidos (si los hay) desde SharedPreferences.
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      coarsePollingSeconds = prefs.getInt(_kCoarsePollingSeconds) ?? coarsePollingSeconds;
      finePollingSeconds = prefs.getInt(_kFinePollingSeconds) ?? finePollingSeconds;
      coarseDistanceFilterMeters = prefs.getInt(_kCoarseDistanceFilter) ?? coarseDistanceFilterMeters;
      fineDistanceFilterMeters = prefs.getInt(_kFineDistanceFilter) ?? fineDistanceFilterMeters;
      accuracyThresholdMeters = prefs.getDouble(_kAccuracyThreshold) ?? accuracyThresholdMeters;
      pathToleranceDefaultMeters = prefs.getDouble(_kPathToleranceDefault) ?? pathToleranceDefaultMeters;
      minDistanceFilterMeters = prefs.getInt(_kMinDistanceFilter) ?? minDistanceFilterMeters;
      activationRadiusMeters = prefs.getDouble(_kActivationRadius) ?? activationRadiusMeters;
    } catch (_) {
      // Silenciar errores de preferencias; usar valores por defecto.
    }
  }

  /// Guardar solo los valores actuales en SharedPreferences.
  static Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCoarsePollingSeconds, coarsePollingSeconds);
    await prefs.setInt(_kFinePollingSeconds, finePollingSeconds);
    await prefs.setInt(_kCoarseDistanceFilter, coarseDistanceFilterMeters);
    await prefs.setInt(_kFineDistanceFilter, fineDistanceFilterMeters);
    await prefs.setDouble(_kAccuracyThreshold, accuracyThresholdMeters);
    await prefs.setDouble(_kPathToleranceDefault, pathToleranceDefaultMeters);
    await prefs.setInt(_kMinDistanceFilter, minDistanceFilterMeters);
  }

  /// Helpers individuales para cambiar y persistir un solo valor.
  static Future<void> setCoarsePollingSeconds(int v) async {
    coarsePollingSeconds = v;
    await saveToPrefs();
  }

  static Future<void> setFinePollingSeconds(int v) async {
    finePollingSeconds = v;
    await saveToPrefs();
  }

  static Future<void> setCoarseDistanceFilterMeters(int v) async {
    coarseDistanceFilterMeters = v;
    await saveToPrefs();
  }

  static Future<void> setFineDistanceFilterMeters(int v) async {
    fineDistanceFilterMeters = v;
    await saveToPrefs();
  }

  static Future<void> setAccuracyThresholdMeters(double v) async {
    accuracyThresholdMeters = v;
    await saveToPrefs();
  }

  static Future<void> setPathToleranceDefaultMeters(double v) async {
    pathToleranceDefaultMeters = v;
    await saveToPrefs();
  }

  static Future<void> saveActivationRadius(double v) async {
    activationRadiusMeters = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kActivationRadius, v);
  }
}
