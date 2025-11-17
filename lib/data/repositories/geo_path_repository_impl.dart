import '../../domain/entities/geo_path.dart';
import '../../domain/repositories/geo_path_repository.dart';
// Path geometry is modelled via GeoTriggers; no coordinate imports needed here.
import '../datasources/local/geo_path_local_data_source.dart';

/// Implementación en memoria apoyada en el data source local.
class GeoPathRepositoryImpl implements GeoPathRepository {
  GeoPathRepositoryImpl({required GeoPathLocalDataSource localDataSource})
      : _local = localDataSource;

  final GeoPathLocalDataSource _local;
  List<GeoPath>? _cache;

  @override
  Future<List<GeoPath>> fetchAll() async {
    _cache ??= await _local.getAll();
    return _cache!;
  }

  // findMatch removed: matching is performed against GeoTriggers instead.

  @override
  Future<GeoPath?> fetchById(int id) async {
    final paths = await fetchAll();
    try {
      return paths.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> createPath({required String name, required int audioAssetId, double toleranceMeters = 10.0}) async {
    final values = {
      'name': name,
      // keep points empty for compatibility
      'points': '[]',
      'audio_asset_id': audioAssetId,
      'tolerance_meters': toleranceMeters,
    };
    final id = await _local.insertPath(values);
    _cache = null;
    return id;
  }
  // updatePoints removed: geometry persisted as triggers.

  @override
  Future<void> saveProgress(int pathId, int offsetMs) async {
    await _local.saveProgress(pathId, offsetMs);
    // Invalidate cache so future reads get updated value
    _cache = null;
  }

  @override
  Future<int> deleteByAudioAssetId(int audioAssetId) async {
    final deleted = await _local.deleteByAudioAssetId(audioAssetId);
    _cache = null;
    return deleted;
  }
}
