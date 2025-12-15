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
    // Configuración Android optimizada para precisión
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: distanceFilter.round(),
      forceLocationManager: true, // Fuerza GPS directo
      intervalDuration: const Duration(seconds: 1), // Actualización cada 1s cuando se mueve
      // Mantén el stream vivo con pantalla apagada usando notificación foreground.
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Cingula está monitoreando tu ubicación en segundo plano.',
        notificationTitle: 'Cingula en ejecución',
        enableWakeLock: true,
        setOngoing: true,
      ),
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
    // Usar configuración específica de Android para forzar GPS de alta precisión
    final position = await _geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        forceLocationManager: true, // Fuerza GPS en lugar de FusedLocationProvider (Android 12+)
        timeLimit: const Duration(seconds: 10), // Espera hasta 10s por lectura precisa
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Cingula está obteniendo tu posición.',
          notificationTitle: 'Cingula activa',
          enableWakeLock: true,
          setOngoing: true,
        ),
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
