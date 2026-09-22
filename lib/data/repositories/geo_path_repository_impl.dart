import '../../domain/entities/geo_path.dart';
import '../../domain/repositories/geo_path_repository.dart';
import '../../domain/repositories/obra_repository.dart';
import '../datasources/local/geo_path_local_data_source.dart';

/// Implementación en memoria apoyada en el data source local.
class GeoPathRepositoryImpl implements GeoPathRepository {
  GeoPathRepositoryImpl({
    required GeoPathLocalDataSource localDataSource,
    required ObraRepository obraRepository,
  })  : _local = localDataSource,
        _obras = obraRepository;

  final GeoPathLocalDataSource _local;
  final ObraRepository _obras;
  List<GeoPath>? _cache;

  @override
  Future<List<GeoPath>> fetchAll() async {
    _cache ??= await _local.getAll();
    return _cache!;
  }

  @override
  Future<GeoPath?> fetchByUuid(String uuid) async {
    final paths = await fetchAll();
    try {
      return paths.firstWhere((p) => p.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> createPath({
    required String name,
    String? audioUuid,
    String? obraUuid,
    String kind = 'route',
    double toleranceMeters = 10.0,
  }) async {
    // D-22: si no se eligió ninguna obra, se crea una draft con el nombre del path.
    final resolvedObraUuid = obraUuid ?? await _obras.createDraft(name);
    final uuid = await _local.insertPath({
      'obra_uuid': resolvedObraUuid,
      'kind': kind,
      'name': name,
      'audio_uuid': audioUuid,
      'tolerance_meters': toleranceMeters,
    });
    _cache = null;
    return uuid;
  }

  @override
  Future<void> saveProgress(String pathUuid, int offsetMs) async {
    await _local.saveProgress(pathUuid, offsetMs);
    _cache = null;
  }

  @override
  Future<void> updateAudio({required String pathUuid, required String audioUuid}) async {
    await _local.updateAudio(pathUuid: pathUuid, audioUuid: audioUuid);
    _cache = null;
  }

  @override
  Future<int> deleteByAudioUuid(String audioUuid) async {
    final deleted = await _local.deleteByAudioUuid(audioUuid);
    _cache = null;
    return deleted;
  }

  @override
  Future<int> deleteByUuid(String pathUuid) async {
    final deleted = await _local.deleteByUuid(pathUuid);
    _cache = null;
    return deleted;
  }
}
