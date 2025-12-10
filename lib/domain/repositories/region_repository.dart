import '../entities/region.dart';
import '../value_objects/coordinate.dart';

/// Repositorio para acceder a regiones y encontrar la región que contiene una coordenada.
abstract class RegionRepository {
  Future<List<Region>> fetchAll();
  Future<Region?> findContaining(Coordinate coordinate);
  Future<int> createRegion({
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  });
}
