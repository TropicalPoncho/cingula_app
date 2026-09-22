import 'package:flutter/foundation.dart';

import '../../domain/entities/audio_asset.dart';
import '../../domain/usecases/monitor_user_location_usecase.dart';
import '../../core/services/log_service.dart';

/// ChangeNotifier que expone estados de monitoreo y reproducción a la UI.
class PlaybackNotifier extends ChangeNotifier {
  PlaybackNotifier({
    required MonitorUserLocationUseCase monitorUseCase,
    required LogService logService,
  })  : _monitorUseCase = monitorUseCase,
        _logService = logService;

  final MonitorUserLocationUseCase _monitorUseCase;
  final LogService _logService;

  AudioAsset? _currentAsset;
  bool _isMonitoring = false;
  String? _statusMessage;
  String? _errorMessage;
  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);

  AudioAsset? get currentAsset => _currentAsset;
  bool get isMonitoring => _isMonitoring;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  Future<void> startMonitoring() async {
    if (_monitorUseCase.isRunning) {
      _isMonitoring = true;
      _statusMessage ??= 'Monitoreo activo';
      notifyListeners();
      return;
    }
    if (_isMonitoring) return;
    _errorMessage = null;
    _statusMessage = 'Iniciando monitoreo…';
    _isMonitoring = true; // Optimista para que el switch/btn refleje inmediatamente
    notifyListeners();

    try {
      await _monitorUseCase.start(
        onAudioChanged: _handleAudioChanged,
        onStatusUpdate: _handleStatusUpdate,
        onLog: _addLog,
      );
      _statusMessage = 'Monitoreo activo';
    } catch (error) {
      _errorMessage = error.toString();
      _statusMessage = 'Ocurrió un problema al iniciar.';
      _isMonitoring = false;
    } finally {
      notifyListeners();
    }
  }

  void _addLog(String? log) {
    if (log == null) return;
    _logs.insert(0, '${DateTime.now().toIso8601String()} - $log');
    // keep only recent 200 entries
    if (_logs.length > 200) _logs.removeRange(200, _logs.length);
    // También enviar a LogService para que aparezca en la UI de diagnóstico
    _logService.log(log);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring && !_monitorUseCase.isRunning) return;
    _statusMessage = 'Deteniendo…';
    notifyListeners();
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

