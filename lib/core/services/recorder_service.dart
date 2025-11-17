import 'dart:async';
import 'dart:developer' as developer;
import 'package:get_it/get_it.dart';
import 'package:cingula_app/core/services/log_service.dart';
import 'dart:math' as math;

import '../../domain/value_objects/coordinate.dart';
import '../../domain/entities/geo_trigger.dart';
import '../../domain/repositories/location_repository.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/repositories/audio_repository.dart';

/// Servicio simple para grabar un camino en campo y generar triggers a lo largo
/// del mismo asociados a un asset de audio.
class RecorderService {
  RecorderService({
    required LocationRepository locationRepository,
    required GeoPathRepository geoPathRepository,
    required GeoTriggerRepository geoTriggerRepository,
    required AudioRepository audioRepository,
  })  : _location = locationRepository,
        _geoPathRepo = geoPathRepository,
        _triggerRepo = geoTriggerRepository,
        _audioRepo = audioRepository;

  final LocationRepository _location;
  final GeoPathRepository _geoPathRepo;
  final GeoTriggerRepository _triggerRepo;
  final AudioRepository _audioRepo;

  StreamSubscription<Coordinate>? _sub;
  final List<Coordinate> _points = [];
  int? _currentPathId;
  // Enable verbose debug logging for recording lifecycle and DB ops.
  final bool _debugLogs = true;

  bool get isRecording => _sub != null;

  Future<int?> startRecording({
    required int audioAssetId,
    String name = 'Recorded path',
    double sampleDistanceMeters = 5.0,
    int secondsPerTrigger = 10,
  }) async {
    if (isRecording) return _currentPathId;

    // Ensure audio exists so we can compute number of triggers later.
    final audio = await _audioRepo.findById(audioAssetId);
    if (audio == null) {
      throw StateError('Audio asset not found: $audioAssetId');
    }

    // Create DB path (metadata) — geometry will be represented by triggers.
    if (_debugLogs) {
      developer.log('Creating path metadata name="$name" audioAssetId=$audioAssetId', name: 'RecorderService');
      GetIt.instance<LogService>().log('Creating path metadata name="$name" audioAssetId=$audioAssetId');
    }
    final pathId = await _geoPathRepo.createPath(
      name: name,
      audioAssetId: audioAssetId,
    );
    _currentPathId = pathId;

    // Subscribe to position stream. Use distanceFilter to reduce noise.
    _sub = _location.positionStream(distanceFilter: sampleDistanceMeters).listen(
      (coord) {
        try {
          // Append if first or sufficiently far from last saved point.
          if (_points.isEmpty || _distanceMeters(_points.last, coord) >= sampleDistanceMeters) {
            _points.add(coord);
          }
          // Log periodically to help debugging (every 25 points)
          if (_debugLogs && _points.length % 25 == 0) {
            final msg = 'Received coord (${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}) — buffer=${_points.length}';
            developer.log(msg, name: 'RecorderService');
            GetIt.instance<LogService>().log(msg);
          }
          // safety: avoid unbounded memory growth
          if (_points.length > 5000) {
            _points.removeRange(0, _points.length - 5000);
            if (_debugLogs) {
              developer.log('Pruned _points buffer to 5000 items', name: 'RecorderService');
              GetIt.instance<LogService>().log('Pruned _points buffer to 5000 items');
            }
          }
        } catch (e, st) {
          if (_debugLogs) {
            developer.log('Error in position handler: $e', name: 'RecorderService', error: e, stackTrace: st);
            GetIt.instance<LogService>().log('Error in position handler: $e');
          }
        }
      },
      onError: (err, st) {
        if (_debugLogs) {
          developer.log('Location stream error: $err', name: 'RecorderService', error: err, stackTrace: st as StackTrace?);
          GetIt.instance<LogService>().log('Location stream error: $err');
        }
      },
    );

    return pathId;
  }

  /// Stops recording and returns the list of created triggers for the path.
  Future<List<GeoTrigger>> stopRecording({int secondsPerTrigger = 10, double triggerRadiusMeters = 12.0}) async {
    if (!isRecording || _currentPathId == null) return <GeoTrigger>[];

  await _sub?.cancel();
    _sub = null;

    final pathId = _currentPathId!;

    // Load the audio duration to compute number of triggers
    final path = await _geoPathRepo.fetchById(pathId);
    if (path == null) {
      _points.clear();
      _currentPathId = null;
      return <GeoTrigger>[];
    }

    final audio = await _audioRepo.findById(path.audioAssetId);
    final durationMs = audio?.duration.inMilliseconds ?? (secondsPerTrigger * 1000);

    final totalLength = _totalLengthMeters(_points);
    final triggersCount = math.max(1, ((durationMs / 1000) / secondsPerTrigger).round());
    final spacing = (triggersCount > 0 && totalLength > 0) ? (totalLength / triggersCount) : 0.0;

    if (_debugLogs) {
      developer.log('stopRecording: pathId=$pathId points=${_points.length} totalLength=${totalLength.toStringAsFixed(2)}m durationMs=$durationMs triggersCount=$triggersCount spacing=${spacing.toStringAsFixed(2)}m', name: 'RecorderService');
    }

    // Walk points and place triggers approximately every `spacing` meters.
    var acc = 0.0;
    double nextAt = spacing;
    if (spacing == 0.0) nextAt = 0.0;

    if (_points.isEmpty) {
      _points.clear();
      _currentPathId = null;
      return <GeoTrigger>[];
    }

    final createdTriggerIds = <int>[];
    final Stopwatch totalInsertSw = Stopwatch()..start();
    if (spacing <= 0) {
      // Single trigger at first point
      final sw = Stopwatch()..start();
      final tId = await _triggerRepo.insertTrigger({
        'name': '${path.name} trigger',
        'description': 'Auto-generated from recorder',
        'latitude': _points.first.latitude,
        'longitude': _points.first.longitude,
        'radius_meters': triggerRadiusMeters,
        'audio_asset_id': path.audioAssetId,
        'geo_path_id': pathId,
      });
      sw.stop();
      createdTriggerIds.add(tId);
      if (_debugLogs) {
        final msg = 'Inserted trigger id=$tId in ${sw.elapsedMilliseconds}ms';
        developer.log(msg, name: 'RecorderService');
        GetIt.instance<LogService>().log(msg);
      }
    } else {
      for (var i = 0; i < _points.length - 1; i++) {
        final a = _points[i];
        final b = _points[i + 1];
        final seg = _distanceMeters(a, b);
        acc += seg;
        while (acc >= nextAt) {
          // place trigger at point b (approximation)
          final alongMeters = nextAt; // estimated distance along path where trigger is placed
          final offsetMs = (totalLength > 0)
              ? ((alongMeters / totalLength) * durationMs).round()
              : 0;

          final sw = Stopwatch()..start();
          final tId = await _triggerRepo.insertTrigger({
            'name': '${path.name} trigger',
            'description': 'Auto-generated from recorder',
            'latitude': b.latitude,
            'longitude': b.longitude,
            'radius_meters': triggerRadiusMeters,
            'audio_asset_id': path.audioAssetId,
            'geo_path_id': pathId,
            'offset_ms': offsetMs,
          });
          sw.stop();
          createdTriggerIds.add(tId);
          if (_debugLogs) {
            final msg = 'Inserted trigger id=$tId (offset_ms=$offsetMs) in ${sw.elapsedMilliseconds}ms';
            developer.log(msg, name: 'RecorderService');
            GetIt.instance<LogService>().log(msg);
          }
          nextAt += spacing;
        }
      }
    }
    totalInsertSw.stop();
    if (_debugLogs) {
      final msg = 'Total inserts: ${createdTriggerIds.length} time=${totalInsertSw.elapsedMilliseconds}ms';
      developer.log(msg, name: 'RecorderService');
      GetIt.instance<LogService>().log(msg);
    }

    // finalize: fetch created triggers for the path and return them
    final pathIdFinal = pathId;
    _points.clear();
    _currentPathId = null;

    // collect created triggers (fresh from repository)
    final created = await _triggerRepo.fetchByPathId(pathIdFinal);
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

  double _totalLengthMeters(List<Coordinate> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      sum += _distanceMeters(pts[i], pts[i + 1]);
    }
    return sum;
  }
}
