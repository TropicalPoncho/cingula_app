import 'dart:math' as math;
import '../value_objects/coordinate.dart';

/// Región geográfica de muestreo y prefiltrado de triggers.
class Region {
  const Region({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusMeters,
    this.sampleCoarseSeconds = 30,
    this.sampleFineSeconds = 2,
    this.coarseDistanceFilterMeters = 500,
    this.fineDistanceFilterMeters = 5,
  });

  final int id;
  final String name;
  final Coordinate center;
  final double radiusMeters;
  final int sampleCoarseSeconds;
  final int sampleFineSeconds;
  final int coarseDistanceFilterMeters;
  final int fineDistanceFilterMeters;

  bool contains(Coordinate c) {
    return _distanceMeters(center.latitude, center.longitude, c.latitude, c.longitude) <= radiusMeters;
  }

  double distanceTo(Coordinate c) => _distanceMeters(center.latitude, center.longitude, c.latitude, c.longitude);

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * math.pi / 180.0;
}
