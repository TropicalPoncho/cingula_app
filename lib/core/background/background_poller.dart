import 'dart:async';

import 'package:cingula_app/domain/repositories/geo_trigger_repository.dart';
import 'package:cingula_app/domain/repositories/location_repository.dart';
import 'package:cingula_app/domain/usecases/monitor_user_location_usecase.dart';
import 'package:cingula_app/domain/value_objects/coordinate.dart';

/// Servicio ligero que ejecuta checks periódicos y adapta el intervalo según
/// la distancia al trigger más cercano.
class BackgroundAdaptivePoller {
  BackgroundAdaptivePoller({
    required MonitorUserLocationUseCase monitorUseCase,
    required GeoTriggerRepository triggerRepository,
    required LocationRepository locationRepository,
    void Function(String log)? onLog,
  })  : _monitor = monitorUseCase,
        _triggerRepo = triggerRepository,
        _locationRepo = locationRepository,
        _onLog = onLog;

  final MonitorUserLocationUseCase _monitor;
  final GeoTriggerRepository _triggerRepo;
  final LocationRepository _locationRepo;
  final void Function(String log)? _onLog;

  Timer? _timer;
  Duration _currentInterval = const Duration(seconds: 30);
  double? _lastNearestDistanceMeters;
  bool _running = false;

  // Bounds and mapping parameters (tweakable)
  static const Duration minInterval = Duration(seconds: 5);
  static const Duration maxInterval = Duration(minutes: 5);

  bool get isRunning => _running;

  /// Arranca el poller. Lanza una comprobación inmediata y luego programa
  /// ejecuciones periódicas adaptativas.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _onLog?.call('BackgroundAdaptivePoller: starting');

    // Immediate execution. Protect against any exceptions (for example
    // permission prompts or service errors) so start() doesn't throw and
    // crash the app during initialization.
    try {
      await _tick();
    } catch (e) {
      _onLog?.call('BackgroundAdaptivePoller: start tick error: $e');
    }

    // Start periodic timer with the computed interval
    _scheduleTimer();
  }

  /// Detiene el poller.
  Future<void> stop() async {
    _onLog?.call('BackgroundAdaptivePoller: stopping');
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _onLog?.call('BackgroundAdaptivePoller: scheduling timer ${_currentInterval.inSeconds}s');
    _timer = Timer.periodic(_currentInterval, (_) async {
      await _tick();
      // After each tick we may have adjusted _currentInterval; if so, reschedule
      // so changes are applied promptly.
      if (!_running) return;
      // If interval changed during tick, reschedule
      // (we compare with a small tolerance to avoid churn)
      _timer?.cancel();
      _scheduleTimer();
    });
  }

  Future<void> _tick() async {
    try {
      _onLog?.call('BackgroundAdaptivePoller: tick — obtaining position');
      // Try ensure permissions & obtain current position
      await _locationRepo.ensureServiceAndPermissions();
      final Coordinate pos = await _locationRepo.currentPosition();

      // Find nearest trigger distance
      final triggers = await _triggerRepo.fetchAll();
      double nearest = double.infinity;
      for (final t in triggers) {
        final d = t.distanceTo(pos);
        if (d < nearest) nearest = d;
      }
      if (nearest == double.infinity) {
        _onLog?.call('BackgroundAdaptivePoller: no triggers available');
      } else {
        _onLog?.call('BackgroundAdaptivePoller: nearest trigger ~ ${nearest.toStringAsFixed(1)} m');
      }

      // Adapt interval according to distance
      _adjustInterval(nearest);

      // Execute the existing single-check usecase (this handles audio/paths)
      await _monitor.executeSingleCheck();
    } catch (e) {
      _onLog?.call('BackgroundAdaptivePoller: tick error: $e');
    }
  }

  void _adjustInterval(double nearestMeters) {
    // If there are no triggers, push to max interval
    if (nearestMeters == double.infinity) {
      _setInterval(maxInterval);
      _lastNearestDistanceMeters = null;
      return;
    }

    // Map distance to a target interval (coarse mapping)
    Duration target;
    if (nearestMeters <= 50) {
      target = const Duration(seconds: 5);
    } else if (nearestMeters <= 200) {
      target = const Duration(seconds: 10);
    } else if (nearestMeters <= 500) {
      target = const Duration(seconds: 20);
    } else if (nearestMeters <= 1000) {
      target = const Duration(seconds: 30);
    } else if (nearestMeters <= 2000) {
      target = const Duration(seconds: 60);
    } else {
      target = maxInterval;
    }

    // If we have a previous measurement, make the change smoother:
    if (_lastNearestDistanceMeters != null) {
      if (nearestMeters < _lastNearestDistanceMeters!) {
        // getting closer -> reduce interval moderately (towards min)
        final reduced = Duration(milliseconds: (_currentInterval.inMilliseconds * 0.6).round());
        if (reduced < target) {
          // be conservative: don't undershoot target mapping
          _setInterval(target);
        } else {
          _setInterval(_clampDuration(reduced));
        }
      } else if (nearestMeters > _lastNearestDistanceMeters!) {
        // getting further -> increase interval
        final increased = Duration(milliseconds: (_currentInterval.inMilliseconds * 1.5).round());
        if (increased > target) {
          _setInterval(target);
        } else {
          _setInterval(_clampDuration(increased));
        }
      } else {
        // same distance — slowly move towards mapped target
        final avgMs = ((_currentInterval.inMilliseconds + target.inMilliseconds) / 2).round();
        _setInterval(_clampDuration(Duration(milliseconds: avgMs)));
      }
    } else {
      // No previous measurement: use mapped target
      _setInterval(target);
    }

    _lastNearestDistanceMeters = nearestMeters;
  }

  void _setInterval(Duration d) {
    final clamped = _clampDuration(d);
    if (clamped == _currentInterval) return;
    _onLog?.call('BackgroundAdaptivePoller: interval changing from ${_currentInterval.inSeconds}s to ${clamped.inSeconds}s');
    _currentInterval = clamped;
  }

  Duration _clampDuration(Duration d) {
    if (d < minInterval) return minInterval;
    if (d > maxInterval) return maxInterval;
    return d;
  }
}
