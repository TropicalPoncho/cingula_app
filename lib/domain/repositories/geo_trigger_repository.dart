import '../entities/geo_trigger.dart';
import '../value_objects/coordinate.dart';

/// Interfaz para consultar zonas geográficas y ubicar la coincidencia vigente.
abstract class GeoTriggerRepository {
  Future<List<GeoTrigger>> fetchAll();
  Future<List<GeoTrigger>> fetchByPathUuid(String pathUuid);
  Future<int> deleteByPathUuid(String pathUuid);
  Future<int> deleteOrphaned();
  Future<GeoTrigger?> findMatch(Coordinate coordinate);

  /// Inserta un trigger nuevo y devuelve el uuid.
  Future<String> insertTrigger(Map<String, Object?> values);
}
