import 'dart:math' as math;

import '../value_objects/coordinate.dart';

/// Zona geográfica dentro de un path.
class GeoTrigger {
  const GeoTrigger({
    required this.uuid,
    required this.pathUuid,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.position = 0,
    this.offsetMs = 0,
    this.updatedAt,
    this.deletedAt,
    this.logicalVersion,
  });

  final String uuid, pathUuid;
  final int position;
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  /// Desde dónde reproducir el audio del path (0 = inicio).
  final int offsetMs;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? logicalVersion;

  /// Determina si la coordenada recibida cae dentro del radio configurado.
  bool contains(Coordinate coordinate) {
    final distance = _distanceInMeters(
      latitude,
      longitude,
      coordinate.latitude,
      coordinate.longitude,
    );
    return distance <= radiusMeters;
  }

  /// Devuelve la distancia (en metros) desde el centro del trigger hasta la coordenada.
  double distanceTo(Coordinate coordinate) {
    return _distanceInMeters(
      latitude,
      longitude,
      coordinate.latitude,
      coordinate.longitude,
    );
  }

  double _distanceInMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * math.pi / 180;
}
