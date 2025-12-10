import '../../domain/value_objects/coordinate.dart';

/// Filtro simple de Kalman para suavizar lecturas GPS y reducir ruido.
/// Mejora la precisión promediando lecturas con peso hacia las más precisas.
class GPSFilter {
  Coordinate? _lastFiltered;
  double _q = 0.00001; // Process noise covariance
  double _r = 0.001; // Measurement noise covariance
  double _p = 1.0; // Estimation error covariance
  double _k = 0.0; // Kalman gain

  /// Filtra una nueva coordenada usando Kalman simple.
  /// Retorna la coordenada suavizada.
  Coordinate filter(Coordinate measurement) {
    if (_lastFiltered == null) {
      _lastFiltered = measurement;
      return measurement;
    }

    // Predicción
    _p = _p + _q;

    // Actualización
    _k = _p / (_p + _r);

    // Coordenadas filtradas
    final filteredLat = _lastFiltered!.latitude + _k * (measurement.latitude - _lastFiltered!.latitude);
    final filteredLon = _lastFiltered!.longitude + _k * (measurement.longitude - _lastFiltered!.longitude);

    _p = (1 - _k) * _p;

    _lastFiltered = Coordinate(
      latitude: filteredLat,
      longitude: filteredLon,
      accuracyMeters: measurement.accuracyMeters,
      timestamp: measurement.timestamp,
    );

    return _lastFiltered!;
  }

  /// Resetea el filtro (útil al reiniciar monitoreo)
  void reset() {
    _lastFiltered = null;
    _p = 1.0;
    _k = 0.0;
  }

  /// Ajusta la sensibilidad del filtro.
  /// - smoothness: 0.0 (sin filtro) a 1.0 (muy suave)
  void setSmoothness(double smoothness) {
    final clamped = smoothness.clamp(0.0, 1.0);
    _q = 0.00001 * (1 - clamped);
    _r = 0.001 + (0.1 * clamped);
  }
}

/// Filtro de media móvil ponderada por precisión.
/// Da más peso a lecturas con mejor accuracy.
class WeightedMovingAverageFilter {
  final List<Coordinate> _buffer = [];
  final int _windowSize;

  WeightedMovingAverageFilter({int windowSize = 5}) : _windowSize = windowSize;

  Coordinate filter(Coordinate measurement) {
    _buffer.add(measurement);
    if (_buffer.length > _windowSize) {
      _buffer.removeAt(0);
    }

    if (_buffer.length == 1) {
      return measurement;
    }

    // Calcular pesos inversamente proporcionales al accuracy (mejor accuracy = más peso)
    double totalWeight = 0.0;
    double weightedLat = 0.0;
    double weightedLon = 0.0;

    for (final coord in _buffer) {
      final accuracy = coord.accuracyMeters ?? 100.0;
      final weight = 1.0 / (accuracy + 1.0); // +1 para evitar división por cero
      totalWeight += weight;
      weightedLat += coord.latitude * weight;
      weightedLon += coord.longitude * weight;
    }

    return Coordinate(
      latitude: weightedLat / totalWeight,
      longitude: weightedLon / totalWeight,
      accuracyMeters: measurement.accuracyMeters,
      timestamp: measurement.timestamp,
    );
  }

  void reset() {
    _buffer.clear();
  }
}
