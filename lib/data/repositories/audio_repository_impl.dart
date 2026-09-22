import '../../domain/entities/audio_asset.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/local/audio_local_data_source.dart';

/// Implementación que lee los audios desde SQLite.
class AudioRepositoryImpl implements AudioRepository {
  AudioRepositoryImpl({required AudioLocalDataSource localDataSource})
      : _localDataSource = localDataSource;

  final AudioLocalDataSource _localDataSource;

  @override
  Future<List<AudioAsset>> fetchAll() => _localDataSource.getAll();

  @override
  Future<AudioAsset?> findByUuid(String uuid) => _localDataSource.getByUuid(uuid);

  @override
  Future<String> insertLocalRecording({
    required String title,
    required String description,
    required String localPath,
    required Duration duration,
  }) {
    return _localDataSource.insertRecording(
      title: title,
      description: description,
      localPath: localPath,
      duration: duration,
    );
  }

  @override
  Future<void> updateDuration({required String uuid, required Duration duration}) {
    return _localDataSource.updateDuration(uuid: uuid, duration: duration);
  }
}
