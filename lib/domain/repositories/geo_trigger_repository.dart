import '../entities/geo_trigger.dart';
import '../value_objects/coordinate.dart';

/// Interfaz para consultar zonas geográficas y ubicar la coincidencia vigente.
abstract class GeoTriggerRepository {
  Future<List<GeoTrigger>> fetchAll();
  Future<List<GeoTrigger>> fetchByPathId(int pathId);
  Future<int> deleteByAudioAssetId(int audioAssetId);
  Future<GeoTrigger?> findMatch(Coordinate coordinate);

  /// Inserta un trigger nuevo y devuelve el id.
  Future<int> insertTrigger(Map<String, Object?> values);
}

