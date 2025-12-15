import 'dart:async';

import 'package:geofence_service/geofence_service.dart' as gf;

import '../../domain/entities/geo_trigger.dart';
import '../../domain/entities/region.dart';
import '../../domain/value_objects/coordinate.dart';
import '../config/location_config.dart';

/// Adapter alrededor de geofence_service para mantener la app activa en
/// background y emitir coordenadas/estados de región a la capa de dominio.
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
    required void Function(Region? region) onRegionChange,
    void Function(String log)? onLog,
    required List<Region> regions,
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
      final data = geofence.data;
      final type = data is Map ? data['type'] as String? : null;
      final regionId = data is Map ? data['regionId'] as int? : null;
      if (type != 'region') return;
      if (status == gf.GeofenceStatus.ENTER || status == gf.GeofenceStatus.DWELL) {
        Region? found;
        for (final r in regions) {
          if (r.id == regionId) {
            found = r;
            break;
          }
        }
        onRegionChange(found);
      }
      if (status == gf.GeofenceStatus.EXIT) {
        onRegionChange(null);
      }
      onLog?.call('Geofence status: ${geofence.id} -> $status');
    });

    _service.addStreamErrorListener((error) {
      onLog?.call('geofence_service error: $error');
    });
  }

  Future<void> start({
    required List<GeoTrigger> triggers,
    required List<Region> regions,
    required void Function(Coordinate coordinate) onLocation,
    required void Function(Region? region) onRegionChange,
    void Function(String log)? onLog,
    double? overrideTriggerRadiusMeters,
  }) async {
    if (_running) return;
    _configureListeners(
      onLocation: onLocation,
      onRegionChange: onRegionChange,
      onLog: onLog,
      regions: regions,
    );

    final geofences = <gf.Geofence>[
      ...regions.map(
        (r) => gf.Geofence(
          id: 'region_${r.id}',
          latitude: r.center.latitude,
          longitude: r.center.longitude,
          radius: [
            gf.GeofenceRadius(
              id: 'region_r${r.radiusMeters.toInt()}',
              length: r.radiusMeters,
            ),
          ],
          data: {'type': 'region', 'regionId': r.id},
        ),
      ),
      ...triggers.map(
        (t) {
          final radius = overrideTriggerRadiusMeters ?? t.radiusMeters;
          return gf.Geofence(
            id: 'trigger_${t.id}',
            latitude: t.latitude,
            longitude: t.longitude,
            radius: [
              gf.GeofenceRadius(
                id: 'trigger_r${radius.toInt()}',
                length: radius,
              ),
            ],
            data: {'type': 'trigger', 'triggerId': t.id, 'audioId': t.audioAssetId},
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
