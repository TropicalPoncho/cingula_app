import '../entities/audio_asset.dart';

/// Contrato para acceder y sincronizar metadatos de audios.
abstract class AudioRepository {
  Future<List<AudioAsset>> fetchAll();
  Future<AudioAsset?> findById(int id);
}

