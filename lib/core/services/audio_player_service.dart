import 'package:just_audio/just_audio.dart';

/// Encapsula JustAudio para facilitar pruebas y cambios futuros.
class AudioPlayerService {
  AudioPlayerService() : _player = AudioPlayer();

  final AudioPlayer _player;

  /// Prepara un asset local antes de iniciar reproducción.
  Future<void> loadAsset(String assetPath) async {
    await _player.setAudioSource(
      AudioSource.asset(assetPath),
    );
  }

  /// Reanuda o inicia la reproducción del asset cargado.
  Future<void> play() => _player.play();

  /// Pausa la reproducción.
  Future<void> pause() => _player.pause();

  /// Busca a la posición indicada (offset) en el asset cargado.
  Future<void> seek(Duration position) => _player.seek(position);

  /// Devuelve la posición actual del reproductor si está disponible.
  Future<Duration?> currentPosition() async => _player.position;

  /// Carga el asset y salta a `offset` si se indica, luego reproduce.
  Future<void> playFromAsset(String assetPath, Duration? offset) async {
    await loadAsset(assetPath);
    if (offset != null && offset > Duration.zero) {
      await seek(offset);
    }
    await play();
  }

  /// Detiene la reproducción sin liberar recursos.
  Future<void> stop() => _player.stop();

  /// Libera el reproductor al cerrar la app.
  Future<void> dispose() => _player.dispose();
}

