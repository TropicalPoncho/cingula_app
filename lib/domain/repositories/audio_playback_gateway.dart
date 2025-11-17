import '../entities/audio_asset.dart';

/// Permite iniciar y detener la reproducción usando un servicio de audio concreto.
abstract class AudioPlaybackGateway {
  AudioAsset? get currentAsset;

  Future<void> play(AudioAsset asset);
  Future<void> stop();

  /// Reproduce desde un offset dado (si es soportado por la implementación).
  Future<void> playFrom(AudioAsset asset, Duration offset);

  /// Pausa la reproducción sin liberar el recurso.
  Future<void> pause();

  /// Devuelve la posición actual de reproducción si está disponible.
  Future<Duration?> currentPosition();
}

