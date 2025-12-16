import 'dart:async';

import '../../core/services/geofence_background_service.dart';
import '../../core/utils/gps_filter.dart';
import '../../core/config/location_config.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../entities/audio_asset.dart';
import '../entities/geo_path.dart';
import '../entities/geo_trigger.dart';
import '../entities/region.dart';
import '../repositories/audio_playback_gateway.dart';
import '../repositories/audio_repository.dart';
import '../repositories/geo_path_repository.dart';
import '../repositories/geo_trigger_repository.dart';
import '../repositories/location_repository.dart';
import '../repositories/region_repository.dart';
import '../value_objects/coordinate.dart';

/// Caso de uso que observa la ubicación y dispara audios según la zona.
class MonitorUserLocationUseCase {
  MonitorUserLocationUseCase({
    required LocationRepository locationRepository,
    required GeoTriggerRepository geoTriggerRepository,
    required GeoPathRepository geoPathRepository,
    required RegionRepository regionRepository,
    required AudioRepository audioRepository,
    required AudioPlaybackGateway playbackGateway,
    GeofenceBackgroundService? geofenceBackgroundService,
  })  : _locationRepository = locationRepository,
        _geoTriggerRepository = geoTriggerRepository,
        _geoPathRepository = geoPathRepository,
        _regionRepository = regionRepository,
        _audioRepository = audioRepository,
        _playbackGateway = playbackGateway,
        _geofenceBackgroundService = geofenceBackgroundService ?? GeofenceBackgroundService();

  final LocationRepository _locationRepository;
  final GeoTriggerRepository _geoTriggerRepository;
  final GeoPathRepository _geoPathRepository;
  final RegionRepository _regionRepository;
  final AudioRepository _audioRepository;
  final AudioPlaybackGateway _playbackGateway;
  final GeofenceBackgroundService _geofenceBackgroundService;

  GeoTrigger? _activeTrigger;
  GeoPath? _activePath;
  Region? _activeRegion;
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
    void Function(Object? activeRegion, String samplingMode)? onStateChanged,
  }) async {
    if (_isRunning) return;

    onStatusUpdate?.call('Solicitando permisos de ubicación…');
    await _locationRepository.ensureServiceAndPermissions();

    // Mantener CPU despierta durante el monitoreo para evitar que el SO pause el servicio al apagar pantalla.
    await WakelockPlus.enable();

    // Pre-cargar geocercas desde repositorios
    final triggers = await _geoTriggerRepository.fetchAll();
    final regions = await _regionRepository.fetchAll();

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
      regions: regions,
      onLocation: (coordinate) async {
        await _handleCoordinate(
          coordinate,
          onAudioChanged: onAudioChanged,
          onStatusUpdate: onStatusUpdate,
          onLog: onLog,
        );
      },
      onRegionChange: (region) {
        _activeRegion = region;
        onStateChanged?.call(region, region != null ? 'geofence' : 'idle');
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
    _activeTrigger = null;
    _activePath = null;
    _activeRegion = null;
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
      // Triggers-first: buscar triggers (filtrando por región si aplica) y
      // si el trigger tiene `geoPathId` asociado, usar ese path para reproducir
      // y guardar progreso; en caso contrario reproducir el audio directo del trigger.
      List<GeoTrigger> triggers = await _geoTriggerRepository.fetchAll();
      if (_activeRegion != null) {
        // Filtrar: triggers SIN región asignada (null) O triggers de esta región
        triggers = triggers.where((t) => t.regionId == null || t.regionId == _activeRegion!.id).toList();
        onLog?.call('Filtrando triggers: ${triggers.length} candidatos (region_id=null o =${_activeRegion!.id})');
      }

      GeoTrigger? bestTrigger;
      double bestTriggerNorm = double.infinity;
      double bestTriggerDist = double.infinity;
      for (final t in triggers) {
        final effectiveRadius = t.radiusMeters;
        final d = t.distanceTo(filteredCoordinate);
        final norm = effectiveRadius > 0 ? (d / effectiveRadius) : double.infinity;
        onLog?.call('  Trigger id=${t.id} name=${t.name}: dist=${d.toStringAsFixed(1)}m radius=${effectiveRadius.toStringAsFixed(1)}m norm=${norm.toStringAsFixed(2)}');
        if (norm < bestTriggerNorm) {
          bestTrigger = t;
          bestTriggerNorm = norm;
          bestTriggerDist = d;
        }
      }

      final triggerCandidate = (bestTrigger != null && bestTriggerNorm <= 1.0);
      
      if (bestTrigger != null) {
        onLog?.call('Mejor trigger: id=${bestTrigger.id} norm=${bestTriggerNorm.toStringAsFixed(2)} dist=${bestTriggerDist.toStringAsFixed(1)}m ${triggerCandidate ? "\u2705 ACTIVADO" : "\u274c fuera de rango"}');
      } else {
        onLog?.call('No hay triggers en esta área');
      }

      if (!triggerCandidate) {
        onLog?.call('⛔ No hay trigger activo (norm > 1.0 o no hay triggers)');
        onLog?.call('Estado actual: activePath=${_activePath?.id} activeTrigger=${_activeTrigger?.id} outsideCount=$_outsideCount');
        // No hay ningún trigger: mantener/pause/stop como antes
        if (_activePath != null) {
          _outsideCount++;
          if (_outsideCount >= 3) {
            final position = await _playbackGateway.currentPosition();
            if (position != null) {
              // Limitar el offset al total del audio si se puede obtener.
              var saveMs = position.inMilliseconds;
              final asset = await _audioRepository.findById(_activePath!.audioAssetId);
              final totalMs = asset?.duration.inMilliseconds;
              if (totalMs != null && saveMs > totalMs) saveMs = totalMs;
              await _geoPathRepository.saveProgress(_activePath!.id, saveMs);
            }
            await _playbackGateway.pause();
            _activePath = null;
            onAudioChanged(null);
            onStatusUpdate?.call('Usuario salió del camino; reproducción pausada.');
            // Resetear filtro para que el reingreso no herede coordenadas lejanas
            // que retrasen la detección del trigger al volver al path.
            _gpsFilter.reset();
          }
        } else if (_activeTrigger != null) {
          _activeTrigger = null;
          await _playbackGateway.stop();
          onAudioChanged(null);
          onStatusUpdate?.call('Fuera de zonas con audio asignado.');
        }
        return;
      }

      // Tenemos un trigger a ejecutar - resetear contador de salida
      _outsideCount = 0;
      
      final match = bestTrigger;
      
      // Si el trigger ya estaba activo, no reiniciamos
      if (_activeTrigger?.id == match.id) {
        onLog?.call('Mismo trigger activo (id=${match.id}), manteniendo reproducción');
        final asset = await _audioRepository.findById(match.audioAssetId);
        if (asset != null) {
          onAudioChanged(asset); // Refresca UI con el nombre/obra aunque siga el mismo trigger
          onStatusUpdate?.call('Reproduciendo zona: ${match.name}');
        }
        return;
      }

      // Si el trigger está asociado a un path, intentamos obtenerlo y usarlo
      if (match.geoPathId != null) {
        final path = await _geoPathRepository.fetchById(match.geoPathId!);
        if (path == null) {
          onStatusUpdate?.call('Path asociado (id=${match.geoPathId}) no encontrado.');
          return;
        }

        // Path geometry is modelled by triggers; we resume playback using any
        // saved offset on the path if present, otherwise start from zero.
        onLog?.call('Trigger->Path match triggerId=${match.id} pathId=${path.id} (using saved offset ${path.savedOffsetMs}ms)');

        // Si ya estamos reproduciendo el mismo path, no hacer nada
        if (_activePath?.id == path.id) {
          onLog?.call('Mismo path activo (id=${path.id}), manteniendo reproducción');
          onStatusUpdate?.call('Reproduciendo camino: ${path.name}');
          return;
        }

        final asset = await _audioRepository.findById(path.audioAssetId);
        if (asset == null) {
          onStatusUpdate?.call('Audio ${path.audioAssetId} no encontrado.');
          return;
        }

    final totalMs = asset.duration.inMilliseconds;

    // Prefer the trigger-specific offset if present, otherwise fallback to path saved progress.
    final triggerOffsetMs = match.offsetMs;
    final savedMs = path.savedOffsetMs;
    final startOffset = (triggerOffsetMs > 0)
      ? Duration(milliseconds: triggerOffsetMs)
      : (savedMs > 0 ? Duration(milliseconds: savedMs) : Duration.zero);

    // Si el offset guardado quedó al final del audio, considerar el camino completado y no reproducir.
    if (totalMs > 0 && startOffset.inMilliseconds >= totalMs - 500) {
      onLog?.call('Camino completado (offset=${startOffset.inMilliseconds}ms >= total=${totalMs}ms), no se reproduce.');
      await _geoPathRepository.saveProgress(path.id, totalMs);
      _activePath = null;
      _activeTrigger = null;
      onAudioChanged(null);
      onStatusUpdate?.call('Camino completado: ${path.name}');
      return;
    }
    onLog?.call('Iniciando reproducción desde offset=${startOffset.inSeconds}s (triggerMs=$triggerOffsetMs savedMs=$savedMs)');
    await _playbackGateway.playFrom(asset, startOffset);
      _activePath = path;
      onLog?.call('Path activado: id=${path.id} offset=${startOffset.inMilliseconds}ms');
        _activeTrigger = null;
        onAudioChanged(asset);
      onStatusUpdate?.call('Reproduciendo camino: ${path.name}');
        return;
      }

      // Trigger sin path asociado: reproducir su audio directamente
      onLog?.call('Trigger match id=${match.id} dist=${bestTriggerDist.toStringAsFixed(1)}m radius=${match.radiusMeters}m');
      final asset = await _audioRepository.findById(match.audioAssetId);
      if (asset == null) {
        onStatusUpdate?.call('Audio ${match.audioAssetId} no encontrado en la base local.');
        return;
      }
      await _playbackGateway.play(asset);
      _activeTrigger = match;
      _activePath = null;
      onAudioChanged(asset);
      onStatusUpdate?.call('Reproduciendo zona: ${match.name}');
      return;
    } finally {
      _isProcessing = false;
    }
  }
}

