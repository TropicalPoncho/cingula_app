import 'dart:async';

import '../entities/audio_asset.dart';
import '../entities/geo_trigger.dart';
import '../entities/geo_path.dart';
import '../repositories/audio_playback_gateway.dart';
import '../repositories/audio_repository.dart';
import '../repositories/geo_trigger_repository.dart';
import '../repositories/geo_path_repository.dart';
import '../repositories/region_repository.dart';
import '../entities/region.dart';
import '../../core/config/location_config.dart';
import '../repositories/location_repository.dart';
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
  })  : _locationRepository = locationRepository,
        _geoTriggerRepository = geoTriggerRepository,
        _geoPathRepository = geoPathRepository,
        _regionRepository = regionRepository,
        _audioRepository = audioRepository,
        _playbackGateway = playbackGateway;

  final LocationRepository _locationRepository;
  final GeoTriggerRepository _geoTriggerRepository;
  final GeoPathRepository _geoPathRepository;
  final RegionRepository _regionRepository;
  final AudioRepository _audioRepository;
  final AudioPlaybackGateway _playbackGateway;

  StreamSubscription<Coordinate>? _positionSubscription;
  StreamSubscription<Coordinate>? _fineSubscription;
  GeoTrigger? _activeTrigger;
  GeoPath? _activePath;
  Region? _activeRegion;
  bool _isProcessing = false;
  int _outsideCount = 0;
  int _regionOutsideCount = 0;
  Timer? _coarseTimer;

  bool get isRunning => _positionSubscription != null;

  /// Inicia el streaming de coordenadas y reacciona con audio.
  Future<void> start({
    required void Function(AudioAsset? asset) onAudioChanged,
    void Function(String message)? onStatusUpdate,
    void Function(String log)? onLog,
    void Function(Object? activeRegion, String samplingMode)? onStateChanged,
  }) async {
    if (_positionSubscription != null) return;

    onStatusUpdate?.call('Solicitando permisos de ubicación…');
    await _locationRepository.ensureServiceAndPermissions();
    onStatusUpdate?.call('Monitoreando ubicación del usuario…');

    // Start in coarse polling mode: poll currentPosition at region's coarse interval.
    _startCoarsePolling(onAudioChanged: onAudioChanged, onStatusUpdate: onStatusUpdate, onLog: onLog, onStateChanged: onStateChanged);
  }

  void _startCoarsePolling({required void Function(AudioAsset? asset) onAudioChanged, void Function(String message)? onStatusUpdate, void Function(String log)? onLog, void Function(Object? activeRegion, String samplingMode)? onStateChanged}) {
    // Use configurable coarse interval; can be tuned in lib/core/config/location_config.dart
    final defaultCoarse = Duration(seconds: LocationConfig.coarsePollingSeconds);
    _coarseTimer?.cancel();
  _coarseTimer = Timer.periodic(defaultCoarse, (_) async {
      try {
        await _locationRepository.ensureServiceAndPermissions();
        final coordinate = await _locationRepository.currentPosition();
        // First: check if coordinate is inside any region
        final region = await _regionRepository.findContaining(coordinate);
        onLog?.call('Coarse: found ${region != null ? 'a region' : 'no regions'} for coordinate');
        if (region == null) {
          onLog?.call('Coarse: fuera de regiones');
          onStateChanged?.call(null, 'coarse');
          return;
        }
        onLog?.call('Entró/está en región id=${region.id} name=${region.name} dist=${region.distanceTo(coordinate).toStringAsFixed(1)}m');
        onStateChanged?.call(region, 'coarse');
        // Enter region: switch to fine subscription using region parameters
        _activeRegion = region;
        _coarseTimer?.cancel();
        _subscribeFine(region, onAudioChanged: onAudioChanged, onStatusUpdate: onStatusUpdate, onLog: onLog, onStateChanged: onStateChanged);
      } catch (e) {
        onLog?.call('Coarse polling error: $e');
      }
    });
    // trigger an immediate tick
    _coarseTimer?.tick;
  }

  void _subscribeFine(Region region, {required void Function(AudioAsset? asset) onAudioChanged, void Function(String message)? onStatusUpdate, void Function(String log)? onLog, void Function(Object? activeRegion, String samplingMode)? onStateChanged}) {
    _fineSubscription?.cancel();
    onLog?.call('Subscribing to fine-grained positionStream with distanceFilter=${region.fineDistanceFilterMeters}m and sampleFineSeconds=${region.sampleFineSeconds}s');
    onLog?.call('Subscribing to fine-grained positionStream with distanceFilter=${region.fineDistanceFilterMeters}m and sampleFineSeconds=${region.sampleFineSeconds}s');
    onStateChanged?.call(region, 'fine');
  final fineFilter = region.fineDistanceFilterMeters > 0 ? region.fineDistanceFilterMeters : LocationConfig.fineDistanceFilterMeters;
  final distanceFilter = fineFilter.clamp(LocationConfig.minDistanceFilterMeters, 1000000);
  _fineSubscription = _locationRepository.positionStream(distanceFilter: distanceFilter.toDouble()).listen((coordinate) async {
      await _handleCoordinate(
        coordinate,
        onAudioChanged: onAudioChanged,
        onStatusUpdate: onStatusUpdate,
        onLog: onLog,
      );
      // also check if we left the region
      if (!region.contains(coordinate)) {
        _regionOutsideCount++;
        if (_regionOutsideCount >= 3) {
          onLog?.call('Salida de región id=${region.id} tras $_regionOutsideCount lecturas fuera');
          onStateChanged?.call(null, 'coarse');
          _activeRegion = null;
          _regionOutsideCount = 0;
          await _fineSubscription?.cancel();
          _fineSubscription = null;
          // resume coarse polling
          _startCoarsePolling(onAudioChanged: onAudioChanged, onStatusUpdate: onStatusUpdate, onLog: onLog);
        }
      } else {
        _regionOutsideCount = 0;
      }
    }, onError: (e) {
      onLog?.call('Fine subscription error: $e');
    });
  }

  /// Detiene la observación continua y apaga la reproducción.
  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeTrigger = null;
    _activePath = null;
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
      // Emitir lectura detallada
      onLog?.call('Lectura: lat=${coordinate.latitude.toStringAsFixed(6)}, lon=${coordinate.longitude.toStringAsFixed(6)}, accuracy=${coordinate.accuracyMeters?.toStringAsFixed(1)}m, time=${coordinate.timestamp}');

      // Ignorar lecturas con baja precisión (umbral configurable)
      if ((coordinate.accuracyMeters ?? double.infinity) > LocationConfig.accuracyThresholdMeters) {
        onLog?.call('Lectura ignorada por baja precisión (accuracy > ${LocationConfig.accuracyThresholdMeters}m).');
        return;
      }
      // Triggers-first: buscar triggers (filtrando por región si aplica) y
      // si el trigger tiene `geoPathId` asociado, usar ese path para reproducir
      // y guardar progreso; en caso contrario reproducir el audio directo del trigger.
      List<GeoTrigger> triggers = await _geoTriggerRepository.fetchAll();
      if (_activeRegion != null) {
        triggers = triggers.where((t) => t.regionId == _activeRegion!.id).toList();
      }

      GeoTrigger? bestTrigger;
      double bestTriggerNorm = double.infinity;
      double bestTriggerDist = double.infinity;
      for (final t in triggers) {
        final d = t.distanceTo(coordinate);
        final norm = t.radiusMeters > 0 ? (d / t.radiusMeters) : double.infinity;
        if (norm < bestTriggerNorm) {
          bestTrigger = t;
          bestTriggerNorm = norm;
          bestTriggerDist = d;
        }
      }

      final triggerCandidate = (bestTrigger != null && bestTriggerNorm <= 1.0);

      if (!triggerCandidate) {
        // No hay ningún trigger: mantener/pause/stop como antes
        if (_activePath != null) {
          _outsideCount++;
          if (_outsideCount >= 3) {
            final position = await _playbackGateway.currentPosition();
            if (position != null) {
              await _geoPathRepository.saveProgress(_activePath!.id, position.inMilliseconds);
            }
            await _playbackGateway.pause();
            _activePath = null;
            onAudioChanged(null);
            onStatusUpdate?.call('Usuario salió del camino; reproducción pausada.');
          }
        } else if (_activeTrigger != null) {
          _activeTrigger = null;
          await _playbackGateway.stop();
          onAudioChanged(null);
          onStatusUpdate?.call('Fuera de zonas con audio asignado.');
        }
        return;
      }

      // Tenemos un trigger a ejecutar
  final match = bestTrigger;
      // Si el trigger ya estaba activo, no reiniciamos
      if (_activeTrigger?.id == match.id) return;

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
        if (_activePath?.id == path.id) return;

  final asset = await _audioRepository.findById(path.audioAssetId);
        if (asset == null) {
          onStatusUpdate?.call('Audio ${path.audioAssetId} no encontrado.');
          return;
        }

    // Prefer the trigger-specific offset if present, otherwise fallback to path saved progress.
    final triggerOffsetMs = match.offsetMs;
    final savedMs = path.savedOffsetMs;
    final startOffset = (triggerOffsetMs > 0)
      ? Duration(milliseconds: triggerOffsetMs)
      : (savedMs > 0 ? Duration(milliseconds: savedMs) : Duration.zero);
    await _playbackGateway.playFrom(asset, startOffset);
        _activePath = path;
        _activeTrigger = null;
        onAudioChanged(asset);
        onStatusUpdate?.call('Reproduciendo camino asociado al trigger: ${match.name}');
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

