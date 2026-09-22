import 'package:just_audio/just_audio.dart';

import '../../core/services/audio_player_service.dart';
import '../../core/services/log_service.dart';
import '../../domain/entities/audio_asset.dart';
import '../../domain/repositories/audio_playback_gateway.dart';

/// Controla la interacción con el reproductor y memoriza el audio activo.
class AudioPlaybackGatewayImpl implements AudioPlaybackGateway {
  AudioPlaybackGatewayImpl({
    required AudioPlayerService playerService,
    required LogService logService,
  })  : _playerService = playerService,
        _logService = logService;

  final AudioPlayerService _playerService;
  final LogService _logService;
  AudioAsset? _currentAsset;

  @override
  AudioAsset? get currentAsset => _currentAsset;

  @override
  Future<void> play(AudioAsset asset) async {
    _logService.log('[Gateway] play() asset=${asset.uuid} title=${asset.title} currentAsset=${_currentAsset?.uuid}');
    try {
      if (_currentAsset?.uuid != asset.uuid) {
        _logService.log('[Gateway] Loading new asset/path: ${asset.localPath}');
        await _playerService.loadPath(asset.localPath);
        _currentAsset = asset;
      }
      _logService.log('[Gateway] Calling _playerService.play()');
      await _playerService.play();
      _logService.log('[Gateway] play() completed');
    } on PlayerException catch (e) {
      _logService.log('[Gateway] PlayerException: ${e.message}');
      // Mantener estado coherente si falla la carga
      _currentAsset = null;
    }
  }

  @override
  Future<void> stop() async {
    _logService.log('[Gateway] stop() called');
    await _playerService.stop();
    _currentAsset = null;
  }

  @override
  Future<void> playFrom(AudioAsset asset, Duration offset) async {
    _logService.log('[Gateway] playFrom() asset=${asset.uuid} offset=${offset.inSeconds}s currentAsset=${_currentAsset?.uuid}');
    try {
      if (_currentAsset?.uuid != asset.uuid) {
        _logService.log('[Gateway] Loading new asset/path: ${asset.localPath}');
        await _playerService.loadPath(asset.localPath);
        _currentAsset = asset;
      }
      if (offset > Duration.zero) {
        _logService.log('[Gateway] Seeking to ${offset.inSeconds}s');
        await _playerService.seek(offset);
      }
      _logService.log('[Gateway] Calling _playerService.play()');
      await _playerService.play();
      _logService.log('[Gateway] playFrom() completed');
    } on PlayerException catch (e) {
      _logService.log('[Gateway] PlayerException: ${e.message}');
      _currentAsset = null;
    }
  }

  @override
  Future<void> pause() async {
    _logService.log('[Gateway] pause() called');
    try {
      await _playerService.pause();

      // En algunos dispositivos/estados el pause puede no detener el audio;
      // si seguimos en estado "playing" forzamos un stop.
      if (_playerService.isPlaying) {
        _logService.log('[Gateway] pause() had no effect, forcing stop()');
        await _playerService.stop();
      }
    } on PlayerException catch (e) {
      _logService.log('[Gateway] PlayerException on pause: ${e.message}; forcing stop()');
      await _playerService.stop();
    } catch (e) {
      _logService.log('[Gateway] pause() error: $e; forcing stop()');
      await _playerService.stop();
    }
  }

  @override
  Future<Duration?> currentPosition() async {
    return _playerService.currentPosition();
  }
}

