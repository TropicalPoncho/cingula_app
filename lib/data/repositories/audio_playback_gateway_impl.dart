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
    _logService.log('[Gateway] play() asset=${asset.id} title=${asset.title} currentAsset=${_currentAsset?.id}');
    if (_currentAsset?.id != asset.id) {
      _logService.log('[Gateway] Loading new asset/path: ${asset.localPath}');
      await _playerService.loadPath(asset.localPath);
      _currentAsset = asset;
    }
    _logService.log('[Gateway] Calling _playerService.play()');
    await _playerService.play();
    _logService.log('[Gateway] play() completed');
  }

  @override
  Future<void> stop() async {
    _logService.log('[Gateway] stop() called');
    await _playerService.stop();
    _currentAsset = null;
  }

  @override
  Future<void> playFrom(AudioAsset asset, Duration offset) async {
    _logService.log('[Gateway] playFrom() asset=${asset.id} offset=${offset.inSeconds}s currentAsset=${_currentAsset?.id}');
    if (_currentAsset?.id != asset.id) {
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
  }

  @override
  Future<void> pause() async {
    _logService.log('[Gateway] pause() called');
    await _playerService.pause();
  }

  @override
  Future<Duration?> currentPosition() async {
    return _playerService.currentPosition();
  }
}

