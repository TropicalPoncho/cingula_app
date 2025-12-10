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
  Future<AudioAsset?> findById(int id) => _localDataSource.getById(id);

  @override
  Future<int> insertLocalRecording({
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
  Future<void> updateDuration({required int id, required Duration duration}) {
    return _localDataSource.updateDuration(id: id, duration: duration);
  }
}

