import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Encapsula JustAudio para facilitar pruebas y cambios futuros.
class AudioPlayerService {
  AudioPlayerService() : _player = AudioPlayer();

  // Asset de respaldo para evitar fallos cuando falta el archivo configurado.
  static const String _fallbackAsset = 'assets/audio/mil_puertas.wav';

  final AudioPlayer _player;

  /// Prepara un asset o archivo local antes de iniciar reproducción.
  Future<void> loadPath(String path) async {
    final isAsset = _looksLikeAsset(path);
    try {
      if (isAsset) {
        await _player.setAudioSource(AudioSource.asset(path));
      } else {
        // Asegura que el archivo exista antes de cargarlo.
        if (!await File(path).exists()) {
          // PlayerException espera un code numérico en versiones actuales de just_audio.
          throw PlayerException(404, 'Audio file not found at $path', null);
        }

        // setFilePath maneja internamente rutas con espacios y UTF-8.
        // Intentar cargar; si falla por condición temporal (archivo aún cerrándose), reintentar una vez.
        try {
          await _player.setFilePath(path);
        } on PlayerException {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await _player.setFilePath(path);
        }
      }
    } on PlayerException catch (e) {
      // Si el asset no existe, intentamos un respaldo para no romper la sesión.
      if (isAsset && path != _fallbackAsset) {
        try {
          await _player.setAudioSource(AudioSource.asset(_fallbackAsset));
          return;
        } on PlayerException {
          // Si el fallback falla, re-lanzamos el error original con contexto.
        }
      }
      throw PlayerException(e.code, 'Audio load failed for "$path": ${e.message}', e.index);
    }
  }

  /// Reanuda o inicia la reproducción del asset cargado.
  Future<void> play() => _player.play();

  /// Pausa la reproducción.
  Future<void> pause() => _player.pause();

  /// Busca a la posición indicada (offset) en el asset cargado.
  Future<void> seek(Duration position) => _player.seek(position);

  /// Devuelve la posición actual del reproductor si está disponible.
  Future<Duration?> currentPosition() async => _player.position;

  /// Carga el path (asset o archivo) y salta a `offset` si se indica, luego reproduce.
  Future<void> playFromPath(String path, Duration? offset) async {
    await loadPath(path);
    if (offset != null && offset > Duration.zero) {
      await seek(offset);
    }
    await play();
  }

  /// Detiene la reproducción sin liberar recursos.
  Future<void> stop() => _player.stop();

  /// Libera el reproductor al cerrar la app.
  Future<void> dispose() => _player.dispose();

  /// Indica si el reproductor sigue marcando estado de reproducción activo.
  bool get isPlaying => _player.playing;

  bool _looksLikeAsset(String path) {
    // Heurística simple: assets se definen dentro de la carpeta de assets del proyecto.
    return path.startsWith('assets/') || path.startsWith('packages/');
  }
}

