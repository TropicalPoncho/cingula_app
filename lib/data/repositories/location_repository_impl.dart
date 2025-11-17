import 'package:geolocator/geolocator.dart';

import '../../domain/repositories/location_repository.dart';
import '../../domain/value_objects/coordinate.dart';

/// Delegado sobre Geolocator para mantener la capa de dominio limpia.
class LocationRepositoryImpl implements LocationRepository {
  LocationRepositoryImpl({GeolocatorPlatform? geolocator})
      : _geolocator = geolocator ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _geolocator;

  @override
  Future<void> ensureServiceAndPermissions() async {
    final serviceEnabled = await _geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const PermissionDeniedException(
        'Permiso de ubicacion denegado',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDefinitionsNotFoundException(
        'Permiso de ubicacion denegado permanentemente',
      );
    }
  }

  @override
  Stream<Coordinate> positionStream({double distanceFilter = 25}) {
    final settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: distanceFilter.round(),
    );
    return _geolocator
        .getPositionStream(locationSettings: settings)
        .map((position) => Coordinate(
              latitude: position.latitude,
              longitude: position.longitude,
              accuracyMeters: position.accuracy,
              timestamp: position.timestamp,
            ));
  }

  @override
  Future<Coordinate> currentPosition() async {
    final position = await _geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    );
    return Coordinate(
      latitude: position.latitude,
      longitude: position.longitude,
  accuracyMeters: position.accuracy,
  timestamp: position.timestamp,
    );
  }
}
