import '../entities/geo_path.dart';
// GeoPathRepository works with path metadata only; geometry is modelled via triggers.

/// Interfaz para consultar caminos configurados y guardar progreso.
abstract class GeoPathRepository {
  Future<List<GeoPath>> fetchAll();
  /// Recupera un `GeoPath` por su id.
  Future<GeoPath?> fetchById(int id);

  Future<void> saveProgress(int pathId, int offsetMs);

  /// Crea un nuevo GeoPath (metadata) y devuelve el id insertado.
  Future<int> createPath({
    required String name,
    required int audioAssetId,
    double toleranceMeters = 10.0,
  });
  Future<int> deleteByAudioAssetId(int audioAssetId);
}
