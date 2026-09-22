import '../../domain/entities/geo_trigger.dart';
import '../../domain/repositories/geo_trigger_repository.dart';
import '../../domain/value_objects/coordinate.dart';
import '../datasources/local/geo_trigger_local_data_source.dart';

/// Implementación que calcula coincidencias en memoria para rapidez.
class GeoTriggerRepositoryImpl implements GeoTriggerRepository {
  GeoTriggerRepositoryImpl({required GeoTriggerLocalDataSource localDataSource})
      : _localDataSource = localDataSource;

  final GeoTriggerLocalDataSource _localDataSource;
  List<GeoTrigger>? _cache;

  @override
  Future<List<GeoTrigger>> fetchAll() async {
    _cache ??= await _localDataSource.getAll();
    return _cache!;
  }

  @override
  Future<GeoTrigger?> findMatch(Coordinate coordinate) async {
    final triggers = await fetchAll();
    for (final trigger in triggers) {
      if (trigger.contains(coordinate)) {
        return trigger;
      }
    }
    return null;
  }

  @override
  Future<String> insertTrigger(Map<String, Object?> values) async {
    final uuid = await _localDataSource.insertTrigger(values);
    _cache = null;
    return uuid;
  }

  @override
  Future<List<GeoTrigger>> fetchByPathUuid(String pathUuid) =>
      _localDataSource.fetchByPathUuid(pathUuid);

  @override
  Future<int> deleteByPathUuid(String pathUuid) async {
    final deleted = await _localDataSource.deleteByPathUuid(pathUuid);
    _cache = null;
    return deleted;
  }

  @override
  Future<int> deleteOrphaned() async {
    final deleted = await _localDataSource.deleteOrphaned();
    _cache = null;
    return deleted;
  }
}
