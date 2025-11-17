import 'package:flutter/foundation.dart';

import '../../domain/entities/audio_asset.dart';
import '../../domain/usecases/monitor_user_location_usecase.dart';

/// ChangeNotifier que expone estados de monitoreo y reproducción a la UI.
class PlaybackNotifier extends ChangeNotifier {
  PlaybackNotifier({required MonitorUserLocationUseCase monitorUseCase})
      : _monitorUseCase = monitorUseCase;

  final MonitorUserLocationUseCase _monitorUseCase;

  AudioAsset? _currentAsset;
  bool _isMonitoring = false;
  String? _statusMessage;
  String? _errorMessage;
  final List<String> _logs = [];
  Object? _activeRegion;
  String _samplingMode = 'coarse';

  List<String> get logs => List.unmodifiable(_logs);

  Object? get activeRegion => _activeRegion;
  String get samplingMode => _samplingMode;

  AudioAsset? get currentAsset => _currentAsset;
  bool get isMonitoring => _isMonitoring;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _errorMessage = null;
    _statusMessage = 'Iniciando monitoreo…';
    notifyListeners();

    try {
      await _monitorUseCase.start(
        onAudioChanged: _handleAudioChanged,
        onStatusUpdate: _handleStatusUpdate,
        onLog: _addLog,
        onStateChanged: _handleStateChanged,
      );
      _isMonitoring = true;
    } catch (error) {
      _errorMessage = error.toString();
      _statusMessage = 'Ocurrió un problema al iniciar.';
    } finally {
      notifyListeners();
    }
  }

  void _handleStateChanged(Object? region, String mode) {
    _activeRegion = region;
    _samplingMode = mode;
    notifyListeners();
  }

  void _addLog(String? log) {
    if (log == null) return;
    _logs.insert(0, '${DateTime.now().toIso8601String()} - $log');
    // keep only recent 200 entries
    if (_logs.length > 200) _logs.removeRange(200, _logs.length);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    await _monitorUseCase.stop();
    _isMonitoring = false;
    _currentAsset = null;
    _statusMessage = 'Monitoreo detenido';
    notifyListeners();
  }

  void _handleAudioChanged(AudioAsset? asset) {
    _currentAsset = asset;
    if (asset == null) {
      _statusMessage = 'Fuera de zonas con audio.';
    } else {
      _statusMessage = 'Reproduciendo: ${asset.title}';
    }
    notifyListeners();
  }

  void _handleStatusUpdate(String message) {
    _statusMessage = message;
    notifyListeners();
  }
}

