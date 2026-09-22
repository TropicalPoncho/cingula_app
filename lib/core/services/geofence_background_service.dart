import 'dart:async';

import 'package:geofence_service/geofence_service.dart' as gf;

import '../../domain/entities/geo_trigger.dart';
import '../../domain/value_objects/coordinate.dart';
import '../config/location_config.dart';

/// Adapter alrededor de geofence_service para mantener la app activa en
/// background y emitir coordenadas a la capa de dominio.
class GeofenceBackgroundService {
  GeofenceBackgroundService({gf.GeofenceService? service})
      : _service = (service ?? gf.GeofenceService.instance).setup(
          interval: LocationConfig.finePollingSeconds * 1000,
          accuracy: 50, // metros de tolerancia para disparar eventos
          loiteringDelayMs: 10 * 1000,
          statusChangeDelayMs: 2 * 1000,
          useActivityRecognition: false,
          allowMockLocations: true,
          printDevLog: false,
        );

  final gf.GeofenceService _service;
  bool _running = false;

  void _configureListeners({
    required void Function(Coordinate coordinate) onLocation,
    void Function(String log)? onLog,
  }) {
    _service.addLocationChangeListener((loc) {
      onLocation(
        Coordinate(
          latitude: loc.latitude,
          longitude: loc.longitude,
          accuracyMeters: loc.accuracy,
          timestamp: loc.timestamp,
        ),
      );
    });

    _service.addGeofenceStatusChangeListener((geofence, radius, status, loc) async {
      onLog?.call('Geofence status: ${geofence.id} -> $status');
    });

    _service.addStreamErrorListener((error) {
      onLog?.call('geofence_service error: $error');
    });
  }

  Future<void> start({
    required List<GeoTrigger> triggers,
    required void Function(Coordinate coordinate) onLocation,
    void Function(String log)? onLog,
    double? overrideTriggerRadiusMeters, // Usar el radio configurado en cada trigger; el activationRadius queda solo para debug visual.
  }) async {
    if (_running) return;
    _configureListeners(
      onLocation: onLocation,
      onLog: onLog,
    );

    final geofences = <gf.Geofence>[
      ...triggers.map(
        (t) {
          final radius = overrideTriggerRadiusMeters ?? t.radiusMeters;
          return gf.Geofence(
            id: 'trigger_${t.uuid}',
            latitude: t.latitude,
            longitude: t.longitude,
            radius: [
              gf.GeofenceRadius(
                id: 'trigger_r${radius.toInt()}',
                length: radius,
              ),
            ],
            data: {'type': 'trigger', 'triggerUuid': t.uuid},
          );
        },
      ),
    ];

    await _service.start(geofences);
    _running = true;
    onLog?.call('Geofence service started with ${geofences.length} geofences');
  }

  Future<void> stop() async {
    if (!_running) return;
    _service.clearAllListeners();
    await _service.stop();
    _running = false;
  }
}
