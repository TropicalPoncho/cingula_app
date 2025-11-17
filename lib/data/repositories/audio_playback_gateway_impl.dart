import '../../core/services/audio_player_service.dart';
import '../../domain/entities/audio_asset.dart';
import '../../domain/repositories/audio_playback_gateway.dart';

/// Controla la interacción con el reproductor y memoriza el audio activo.
class AudioPlaybackGatewayImpl implements AudioPlaybackGateway {
  AudioPlaybackGatewayImpl({required AudioPlayerService playerService})
      : _playerService = playerService;

  final AudioPlayerService _playerService;
  AudioAsset? _currentAsset;

  @override
  AudioAsset? get currentAsset => _currentAsset;

  @override
  Future<void> play(AudioAsset asset) async {
    if (_currentAsset?.id != asset.id) {
      await _playerService.loadAsset(asset.localPath);
      _currentAsset = asset;
    }
    await _playerService.play();
  }

  @override
  Future<void> stop() async {
    await _playerService.stop();
    _currentAsset = null;
  }

  @override
  Future<void> playFrom(AudioAsset asset, Duration offset) async {
    if (_currentAsset?.id != asset.id) {
      await _playerService.loadAsset(asset.localPath);
      _currentAsset = asset;
    }
    if (offset > Duration.zero) {
      await _playerService.seek(offset);
    }
    await _playerService.play();
  }

  @override
  Future<void> pause() async {
    await _playerService.pause();
  }

  @override
  Future<Duration?> currentPosition() async {
    return _playerService.currentPosition();
  }
}

