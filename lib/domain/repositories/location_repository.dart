import '../value_objects/coordinate.dart';

/// Abstracción sobre la API de geolocalización del dispositivo.
abstract class LocationRepository {
  Future<void> ensureServiceAndPermissions();
  Stream<Coordinate> positionStream({double distanceFilter});
  Future<Coordinate> currentPosition();
}

