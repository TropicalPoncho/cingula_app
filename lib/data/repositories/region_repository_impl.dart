import '../../domain/entities/region.dart';
import '../../domain/repositories/region_repository.dart';
import '../../domain/value_objects/coordinate.dart';
import '../datasources/local/region_local_data_source.dart';

class RegionRepositoryImpl implements RegionRepository {
  RegionRepositoryImpl({required RegionLocalDataSource localDataSource}) : _local = localDataSource;

  final RegionLocalDataSource _local;
  List<Region>? _cache;

  @override
  Future<List<Region>> fetchAll() async {
    _cache ??= await _local.getAll();
    return _cache!;
  }

  @override
  Future<Region?> findContaining(Coordinate coordinate) async {
    final regions = await fetchAll();
    for (final r in regions) {
      if (r.contains(coordinate)) return r;
    }
    return null;
  }

  @override
  Future<int> createRegion({
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final id = await _local.insertRegion({
      'name': name,
      'center_lat': latitude,
      'center_lon': longitude,
      'radius_meters': radiusMeters,
      'sample_coarse_seconds': 30,
      'sample_fine_seconds': 2,
      'coarse_distance_filter_meters': 500,
      'fine_distance_filter_meters': 5,
    });
    _cache = null; // invalidar cache
    return id;
  }
}
