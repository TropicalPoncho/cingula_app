import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:cingula_app/core/services/log_service.dart';
import 'dart:math' as math;
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/foundation.dart';

import '../../domain/value_objects/coordinate.dart';
import '../utils/gps_filter.dart';
import '../../domain/entities/geo_trigger.dart';
import '../../domain/repositories/location_repository.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/repositories/audio_repository.dart';
import 'notification_service.dart';

class RecordingStatus {
  const RecordingStatus({
    this.isRecording = false,
    this.startedAt,
    this.label,
    this.withMic = false,
  });

  final bool isRecording;
  final DateTime? startedAt;
  final String? label;
  final bool withMic;
}

/// Servicio simple para grabar un camino en campo y generar triggers a lo largo
/// del mismo asociados a un asset de audio.
class RecorderService {
  RecorderService({
    required LocationRepository locationRepository,
    required GeoPathRepository geoPathRepository,
    required GeoTriggerRepository geoTriggerRepository,
    required AudioRepository audioRepository,
    required NotificationService notificationService,
  })  : _location = locationRepository,
        _geoPathRepo = geoPathRepository,
        _triggerRepo = geoTriggerRepository,
        _audioRepo = audioRepository,
        _notificationService = notificationService;

  final LocationRepository _location;
  final GeoPathRepository _geoPathRepo;
  final GeoTriggerRepository _triggerRepo;
  final AudioRepository _audioRepo;
  final NotificationService _notificationService;

  // Instancia del filtro de GPS para suavizar la grabación
  final WeightedMovingAverageFilter _gpsFilter = WeightedMovingAverageFilter(windowSize: 3);

  // Grabación de micrófono
  final AudioRecorder _micRecorder = AudioRecorder();
  String? _recordingPath;
  DateTime? _recordingStart;

  StreamSubscription<Coordinate>? _sub;
  int? _currentPathId;
  int? _currentAudioAssetId;
  double _triggerSpacing = 10.0;
  double _triggerRadius = 12.0;
  String _pathName = 'Recorded path';
  double _totalDistance = 0.0;
  Coordinate? _lastTriggerPosition;
  int _triggerCount = 0;
  final bool _debugLogs = true;

  bool get isRecording => _sub != null;
  final ValueNotifier<RecordingStatus> recordingStatus = ValueNotifier(const RecordingStatus());

  Future<int?> startRecording({
    required int audioAssetId,
    String name = 'Recorded path',
    double sampleDistanceMeters = 5.0,
    double spacingMeters = 10.0,
    double triggerRadiusMeters = 12.0,
  }) async {
    if (isRecording) return _currentPathId;

    // Mantener CPU despierta durante la grabación para evitar que el SO pause servicios con pantalla apagada.
    await WakelockPlus.enable();

    final audio = await _audioRepo.findById(audioAssetId);
    if (audio == null) {
      throw StateError('Audio asset not found: $audioAssetId');
    }

    _currentAudioAssetId = audioAssetId;
    _triggerSpacing = spacingMeters;
    _triggerRadius = triggerRadiusMeters;
    _pathName = name;
    _totalDistance = 0.0;
    _lastTriggerPosition = null;
    _triggerCount = 0;

    // Resetear el filtro al iniciar una nueva grabación para evitar datos viejos
    _gpsFilter.reset();

    if (_debugLogs) {
      developer.log('Creating path name="$name" audioAssetId=$audioAssetId spacing=${spacingMeters}m', name: 'RecorderService');
      GetIt.instance<LogService>().log('Iniciando grabación: $name (spacing: ${spacingMeters}m)');
    }

    final pathId = await _geoPathRepo.createPath(
      name: name,
      audioAssetId: audioAssetId,
    );
    _currentPathId = pathId;

    // Crear primer trigger en posición actual
    try {
      var startPos = await _location.currentPosition();
      
      // Aplicar filtro a la posición inicial
      startPos = _gpsFilter.filter(startPos);

      await _createTrigger(startPos, pathId, audioAssetId, 0);
      _lastTriggerPosition = startPos;
      if (_debugLogs) {
        GetIt.instance<LogService>().log('Trigger inicial creado en (${startPos.latitude.toStringAsFixed(6)}, ${startPos.longitude.toStringAsFixed(6)})');
      }
    } catch (e) {
      if (_debugLogs) {
        developer.log('Error creando trigger inicial: $e', name: 'RecorderService');
        GetIt.instance<LogService>().log('Error al crear trigger inicial: $e');
      }
    }

    // Suscribirse al stream de ubicación
    _sub = _location.positionStream(distanceFilter: sampleDistanceMeters).listen(
      (coord) async {
        try {
          // Aplicar filtro de GPS para suavizar la ruta grabada
          final filteredCoord = _gpsFilter.filter(coord);

          if (_lastTriggerPosition != null) {
            final distance = _distanceMeters(_lastTriggerPosition!, filteredCoord);
            _totalDistance += distance;

            // Crear trigger si recorrimos suficiente distancia
            if (distance >= _triggerSpacing) {
              final audioDuration = audio.duration.inMilliseconds;
              final offsetMs = audioDuration > 0
                  ? ((_totalDistance / (_triggerSpacing * (_triggerCount + 1))) * audioDuration).round().clamp(0, audioDuration)
                  : 0;

              await _createTrigger(filteredCoord, _currentPathId!, _currentAudioAssetId!, offsetMs);
              _lastTriggerPosition = filteredCoord;

              if (_debugLogs && _triggerCount % 5 == 0) {
                GetIt.instance<LogService>().log('Triggers creados: $_triggerCount (distancia: ${_totalDistance.toStringAsFixed(1)}m)');
              }
            }
          }
        } catch (e, st) {
          if (_debugLogs) {
            developer.log('Error en stream handler: $e', name: 'RecorderService', error: e, stackTrace: st);
            GetIt.instance<LogService>().log('Error procesando ubicación: $e');
          }
        }
      },
      onError: (err, st) {
        if (_debugLogs) {
          developer.log('Location stream error: $err', name: 'RecorderService', error: err, stackTrace: st as StackTrace?);
          GetIt.instance<LogService>().log('Error en stream de ubicación: $err');
        }
      },
    );

    return pathId;
  }

  Future<void> _createTrigger(Coordinate position, int pathId, int audioAssetId, int offsetMs) async {
    try {
      final tId = await _triggerRepo.insertTrigger({
        'name': '$_pathName trigger ${_triggerCount + 1}',
        'description': 'Auto-generated',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'radius_meters': _triggerRadius,
        'audio_asset_id': audioAssetId,
        'geo_path_id': pathId,
        'offset_ms': offsetMs,
      });
      _triggerCount++;
      if (_debugLogs) {
        developer.log('Trigger #$_triggerCount creado (id=$tId, offset=${offsetMs}ms)', name: 'RecorderService');
      }
    } catch (e) {
      if (_debugLogs) {
        developer.log('Error insertando trigger: $e', name: 'RecorderService');
      }
    }
  }

  /// Stops recording and returns the list of created triggers for the path.
  Future<List<GeoTrigger>> stopRecording({
    required double spacingMeters,
    double triggerRadiusMeters = 12.0,
  }) async {
    if (!isRecording || _currentPathId == null) return <GeoTrigger>[];

    final pathId = _currentPathId!;
    final audioId = _currentAudioAssetId;
    Duration? recordedDuration;
    List<GeoTrigger> created = const <GeoTrigger>[];

    try {
      await _sub?.cancel();
      _sub = null;

      // Finalizar grabación de micrófono (si está activa)
      try {
        final isRec = await _micRecorder.isRecording();
        if (isRec) {
          await _micRecorder.stop();
          if (_recordingStart != null) {
            recordedDuration = DateTime.now().difference(_recordingStart!);
          }
        }
      } catch (e) {
        if (_debugLogs) {
          developer.log('Error al detener grabación de micrófono: $e', name: 'RecorderService');
        }
      }

      // Liberar wakelock al terminar la grabación para evitar dejar la app fija en pantalla encendida.
      try {
        await WakelockPlus.disable();
      } catch (e) {
        if (_debugLogs) {
          developer.log('Error desactivando wakelock: $e', name: 'RecorderService');
        }
      }

      // Limpiar notificación persistente si se estaba grabando micrófono.
      try {
        await _notificationService.clearRecordingNotification();
      } catch (e) {
        if (_debugLogs) {
          developer.log('Error limpiando notificación de grabación: $e', name: 'RecorderService');
        }
      }

      if (_debugLogs) {
        developer.log('stopRecording: pathId=$pathId triggers creados=$_triggerCount', name: 'RecorderService');
        GetIt.instance<LogService>().log('Grabación finalizada: $_triggerCount triggers creados');
      }

      // Actualizar duración del audio grabado una vez detenida la captura
      if (recordedDuration != null && audioId != null) {
        try {
          await _audioRepo.updateDuration(id: audioId, duration: recordedDuration);
        } catch (e) {
          if (_debugLogs) {
            developer.log('Error actualizando duración del audio grabado: $e', name: 'RecorderService');
          }
        }
      }

      // Retornar todos los triggers del path
      created = await _triggerRepo.fetchByPathId(pathId);
    } catch (e, st) {
      if (_debugLogs) {
        developer.log('Error en stopRecording: $e', name: 'RecorderService', error: e, stackTrace: st);
        GetIt.instance<LogService>().log('Error al frenar la grabación: $e');
      }
    } finally {
      _currentPathId = null;
      _currentAudioAssetId = null;
      _totalDistance = 0.0;
      _lastTriggerPosition = null;
      _recordingPath = null;
      _recordingStart = null;
      _triggerCount = 0;
      _gpsFilter.reset();
      recordingStatus.value = const RecordingStatus();
    }

    return created;
  }

  double _distanceMeters(Coordinate a, Coordinate b) {
    const R = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);
    final dsin = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(dsin), math.sqrt(1 - dsin));
    return R * c;
  }

  double _toRad(double deg) => deg * math.pi / 180;

  /// Inicia grabación de path creando además un audio grabado por micrófono
  /// y vinculándolo al path recién creado.
  Future<int?> startRecordingWithMic({
    String name = 'Recorded path',
    double sampleDistanceMeters = 5.0,
    double spacingMeters = 10.0,
    double triggerRadiusMeters = 12.0,
  }) async {
    if (isRecording) return _currentPathId;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      throw StateError('Permiso de micrófono denegado');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final recDir = Directory(p.join(appDir.path, 'recordings'));
    if (!await recDir.exists()) {
      await recDir.create(recursive: true);
    }

    _recordingPath = p.join(recDir.path, 'path_${DateTime.now().millisecondsSinceEpoch}.m4a');
    _recordingStart = DateTime.now();

    await _micRecorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _recordingPath!,
    );

    final audioId = await _audioRepo.insertLocalRecording(
      title: name,
      description: 'Grabado en campo',
      localPath: _recordingPath!,
      duration: Duration.zero,
    );

    recordingStatus.value = RecordingStatus(
      isRecording: true,
      startedAt: _recordingStart,
      label: name,
      withMic: true,
    );

    try {
      await _notificationService.showRecordingNotification(
        title: 'Grabando audio',
        body: name,
      );
    } catch (e) {
      if (_debugLogs) {
        developer.log('No se pudo mostrar notificación de grabación: $e', name: 'RecorderService');
      }
    }

    try {
      return await startRecording(
        audioAssetId: audioId,
        name: name,
        sampleDistanceMeters: sampleDistanceMeters,
        spacingMeters: spacingMeters,
        triggerRadiusMeters: triggerRadiusMeters,
      );
    } catch (e) {
      // Si falla el path, detener micrófono y limpiar notificación.
      try {
        await _micRecorder.stop();
        await _notificationService.clearRecordingNotification();
      } catch (_) {}
      recordingStatus.value = const RecordingStatus();
      rethrow;
    }
  }
}
