import '../entities/audio_asset.dart';

/// Contrato para acceder y sincronizar metadatos de audios.
abstract class AudioRepository {
  Future<List<AudioAsset>> fetchAll();
  Future<AudioAsset?> findById(int id);

  /// Inserta un nuevo audio grabado localmente y retorna su id.
  Future<int> insertLocalRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  });

  /// Actualiza la duración de un audio ya almacenado (útil al cerrar la grabación).
  Future<void> updateDuration({required int id, required Duration duration});
}

