import '../entities/geo_path.dart';

/// Interfaz para consultar caminos configurados y guardar progreso.
/// La geometría se modela con triggers.
abstract class GeoPathRepository {
  Future<List<GeoPath>> fetchAll();
  Future<GeoPath?> fetchByUuid(String uuid);

  /// Solo path_progress (local): no encola outbox.
  Future<void> saveProgress(String pathUuid, int offsetMs);

  Future<void> updateAudio({required String pathUuid, required String audioUuid});

  /// Crea un path y devuelve su uuid. Sin [obraUuid] crea una obra draft con el nombre del path.
  Future<String> createPath({
    required String name,
    String? audioUuid,
    String? obraUuid,
    String kind = 'route',
    double toleranceMeters = 10.0,
  });
  Future<int> deleteByAudioUuid(String audioUuid);
  Future<int> deleteByUuid(String pathUuid);
}
