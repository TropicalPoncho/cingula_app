import 'dart:async';

import '../../core/services/geofence_background_service.dart';
import '../../core/utils/gps_filter.dart';
import '../../core/config/location_config.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../entities/audio_asset.dart';
import '../entities/geo_path.dart';
import '../entities/geo_trigger.dart';
import '../repositories/audio_playback_gateway.dart';
import '../repositories/audio_repository.dart';
import '../repositories/geo_path_repository.dart';
import '../repositories/geo_trigger_repository.dart';
import '../repositories/location_repository.dart';
import '../value_objects/coordinate.dart';

/// Caso de uso que observa la ubicación y dispara audios según la zona.
class MonitorUserLocationUseCase {
  MonitorUserLocationUseCase({
    required LocationRepository locationRepository,
    required GeoTriggerRepository geoTriggerRepository,
    required GeoPathRepository geoPathRepository,
    required AudioRepository audioRepository,
    required AudioPlaybackGateway playbackGateway,
    GeofenceBackgroundService? geofenceBackgroundService,
  })  : _locationRepository = locationRepository,
        _geoTriggerRepository = geoTriggerRepository,
        _geoPathRepository = geoPathRepository,
        _audioRepository = audioRepository,
        _playbackGateway = playbackGateway,
        _geofenceBackgroundService = geofenceBackgroundService ?? GeofenceBackgroundService();

  final LocationRepository _locationRepository;
  final GeoTriggerRepository _geoTriggerRepository;
  final GeoPathRepository _geoPathRepository;
  final AudioRepository _audioRepository;
  final AudioPlaybackGateway _playbackGateway;
  final GeofenceBackgroundService _geofenceBackgroundService;

  // Todos los triggers pertenecen a un path (los sueltos se volvieron portales
  // en la migración v7); no hace falta trackear un trigger activo aparte del
  // path activo.
  GeoPath? _activePath;
  bool _isProcessing = false;
  int _outsideCount = 0;
  bool _isRunning = false;

  // Filtro GPS para mejorar precisión
  final WeightedMovingAverageFilter _gpsFilter = WeightedMovingAverageFilter(windowSize: 3);

  bool get isRunning => _isRunning;

  /// Inicia el streaming de coordenadas y reacciona con audio.
  Future<void> start({
    required void Function(AudioAsset? asset) onAudioChanged,
    void Function(String message)? onStatusUpdate,
    void Function(String log)? onLog,
  }) async {
    if (_isRunning) return;

    onStatusUpdate?.call('Solicitando permisos de ubicación…');
    await _locationRepository.ensureServiceAndPermissions();

    // Mantener CPU despierta durante el monitoreo para evitar que el SO pause el servicio al apagar pantalla.
    await WakelockPlus.enable();

    // Pre-cargar geocercas desde repositorios
    final triggers = await _geoTriggerRepository.fetchAll();

    // Lectura inicial (sin esperar a eventos) para reaccionar rápido
    try {
      final coordinate = await _locationRepository.currentPosition();
      await _handleCoordinate(
        coordinate,
        onAudioChanged: onAudioChanged,
        onStatusUpdate: onStatusUpdate,
        onLog: onLog,
      );
    } catch (_) {}

    await _geofenceBackgroundService.start(
      triggers: triggers,
      onLocation: (coordinate) async {
        await _handleCoordinate(
          coordinate,
          onAudioChanged: onAudioChanged,
          onStatusUpdate: onStatusUpdate,
          onLog: onLog,
        );
      },
      onLog: onLog,
      // Usar el radio específico de cada trigger; activarRadio solo para debug visual.
      overrideTriggerRadiusMeters: null,
    );

    _isRunning = true;
    onStatusUpdate?.call('Monitoreo geofence activo');
  }

  /// Detiene la observación continua y apaga la reproducción.
  Future<void> stop() async {
    if (!_isRunning) return;

    await _geofenceBackgroundService.stop();

    // Liberar wake lock cuando se detiene el monitoreo.
    await WakelockPlus.disable();

    // Resetear estados
    _activePath = null;
    _outsideCount = 0;
    _isProcessing = false;
    _isRunning = false;

    // Resetear filtro GPS
    _gpsFilter.reset();

    // Detener reproducción
    await _playbackGateway.stop();
  }

  /// Ejecuta la lógica una sola vez; usado por el worker en background.
  Future<void> executeSingleCheck() async {
    await _locationRepository.ensureServiceAndPermissions();
    final coordinate = await _locationRepository.currentPosition();
    await _handleCoordinate(
      coordinate,
      onAudioChanged: (_) {},
      onStatusUpdate: null,
      onLog: null,
    );
  }

  Future<void> _handleCoordinate(
    Coordinate coordinate, {
    required void Function(AudioAsset? asset) onAudioChanged,
    void Function(String message)? onStatusUpdate,
    void Function(String log)? onLog,
  }) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      // Filtrar coordenada para reducir ruido GPS
      final filteredCoordinate = _gpsFilter.filter(coordinate);

      // Emitir lectura detallada (mostrar original vs filtrada)
      onLog?.call('Lectura: lat=${coordinate.latitude.toStringAsFixed(6)}, lon=${coordinate.longitude.toStringAsFixed(6)}, accuracy=${coordinate.accuracyMeters?.toStringAsFixed(1)}m');
      if ((filteredCoordinate.latitude - coordinate.latitude).abs() > 0.00001 || (filteredCoordinate.longitude - coordinate.longitude).abs() > 0.00001) {
        onLog?.call('Filtrada: lat=${filteredCoordinate.latitude.toStringAsFixed(6)}, lon=${filteredCoordinate.longitude.toStringAsFixed(6)}');
      }

      // Ignorar lecturas con baja precisión (umbral configurable)
      if ((filteredCoordinate.accuracyMeters ?? double.infinity) > LocationConfig.accuracyThresholdMeters) {
        onLog?.call('Lectura ignorada por baja precisión (accuracy > ${LocationConfig.accuracyThresholdMeters}m).');
        return;
      }
      // Todo trigger pertenece a un path (D-28: los sueltos son portales).
      final triggers = await _geoTriggerRepository.fetchAll();

      GeoTrigger? bestTrigger;
      double bestTriggerNorm = double.infinity;
      double bestTriggerDist = double.infinity;
      for (final t in triggers) {
        final effectiveRadius = t.radiusMeters;
        final d = t.distanceTo(filteredCoordinate);
        final norm = effectiveRadius > 0 ? (d / effectiveRadius) : double.infinity;
        onLog?.call('  Trigger uuid=${t.uuid} name=${t.name}: dist=${d.toStringAsFixed(1)}m radius=${effectiveRadius.toStringAsFixed(1)}m norm=${norm.toStringAsFixed(2)}');
        if (norm < bestTriggerNorm) {
          bestTrigger = t;
          bestTriggerNorm = norm;
          bestTriggerDist = d;
        }
      }

      final triggerCandidate = (bestTrigger != null && bestTriggerNorm <= 1.0);

      if (bestTrigger != null) {
        onLog?.call('Mejor trigger: uuid=${bestTrigger.uuid} norm=${bestTriggerNorm.toStringAsFixed(2)} dist=${bestTriggerDist.toStringAsFixed(1)}m ${triggerCandidate ? "✅ ACTIVADO" : "❌ fuera de rango"}');
      } else {
        onLog?.call('No hay triggers en esta área');
      }

      if (!triggerCandidate) {
        onLog?.call('⛔ No hay trigger activo (norm > 1.0 o no hay triggers)');
        onLog?.call('Estado actual: activePath=${_activePath?.uuid} outsideCount=$_outsideCount');
        // No hay ningún trigger: mantener/pause/stop como antes
        if (_activePath != null) {
          _outsideCount++;
          if (_outsideCount >= 3) {
            // Un portal arranca siempre en 0 y no tiene progreso que guardar
            // (es el comportamiento que hoy tienen los triggers sueltos).
            if (_activePath!.kind != 'portal') {
              final position = await _playbackGateway.currentPosition();
              if (position != null) {
                // Limitar el offset al total del audio si se puede obtener.
                var saveMs = position.inMilliseconds;
                final audioUuid = _activePath!.audioUuid;
                final asset = audioUuid != null ? await _audioRepository.findByUuid(audioUuid) : null;
                final totalMs = asset?.duration.inMilliseconds;
                if (totalMs != null && saveMs > totalMs) saveMs = totalMs;
                await _geoPathRepository.saveProgress(_activePath!.uuid, saveMs);
              }
            }
            await _playbackGateway.pause();
            _activePath = null;
            onAudioChanged(null);
            onStatusUpdate?.call('Usuario salió del camino; reproducción pausada.');
            // Resetear filtro para que el reingreso no herede coordenadas lejanas
            // que retrasen la detección del trigger al volver al path.
            _gpsFilter.reset();
          }
        }
        return;
      }

      // Tenemos un trigger a ejecutar - resetear contador de salida
      _outsideCount = 0;

      final match = bestTrigger;

      final path = await _geoPathRepository.fetchByUuid(match.pathUuid);
      if (path == null) {
        onStatusUpdate?.call('Path asociado (uuid=${match.pathUuid}) no encontrado.');
        return;
      }

      // Si ya estamos reproduciendo el mismo path, no hacer nada.
      if (_activePath?.uuid == path.uuid) {
        onLog?.call('Mismo path activo (uuid=${path.uuid}), manteniendo reproducción');
        onStatusUpdate?.call('Reproduciendo camino: ${path.name}');
        return;
      }

      final audioUuid = path.audioUuid;
      if (audioUuid == null) {
        onStatusUpdate?.call('Path "${path.name}" no tiene audio asignado.');
        return;
      }

      final asset = await _audioRepository.findByUuid(audioUuid);
      if (asset == null) {
        onStatusUpdate?.call('Audio $audioUuid no encontrado.');
        return;
      }

      final totalMs = asset.duration.inMilliseconds;
      final isPortal = path.kind == 'portal';

      // Un portal arranca siempre en 0 (D-03: es el comportamiento que hoy
      // tienen los triggers sueltos). Un route prefiere el progreso guardado;
      // si se reseteó a 0 arranca desde el inicio ignorando el offset del trigger.
      final triggerOffsetMs = match.offsetMs;
      final savedMs = path.savedOffsetMs;
      final effectiveOffsetMs = isPortal
          ? 0
          : (savedMs == 0 ? 0 : (triggerOffsetMs > 0 ? triggerOffsetMs : savedMs));
      final startOffset = Duration(milliseconds: effectiveOffsetMs);

      // Si el offset guardado quedó al final del audio, considerar el camino completado y no reproducir.
      // No aplica a portales: siempre arrancan en 0.
      if (!isPortal && totalMs > 0 && startOffset.inMilliseconds >= totalMs - 500) {
        onLog?.call('Camino completado (offset=${startOffset.inMilliseconds}ms >= total=${totalMs}ms), no se reproduce.');
        await _geoPathRepository.saveProgress(path.uuid, totalMs);
        _activePath = null;
        onAudioChanged(null);
        onStatusUpdate?.call('Camino completado: ${path.name}');
        return;
      }
      onLog?.call('Iniciando reproducción desde offset=${startOffset.inSeconds}s (triggerMs=$triggerOffsetMs savedMs=$savedMs isPortal=$isPortal)');
      await _playbackGateway.playFrom(asset, startOffset);
      _activePath = path;
      onLog?.call('Path activado: uuid=${path.uuid} offset=${startOffset.inMilliseconds}ms');
      onAudioChanged(asset);
      onStatusUpdate?.call('Reproduciendo camino: ${path.name}');
      return;
    } finally {
      _isProcessing = false;
    }
  }
}
