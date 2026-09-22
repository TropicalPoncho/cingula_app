import '../../domain/entities/obra.dart';
import '../../domain/repositories/obra_repository.dart';
import '../datasources/local/obra_local_data_source.dart';

/// Implementación que lee/crea obras desde SQLite.
class ObraRepositoryImpl implements ObraRepository {
  ObraRepositoryImpl({required ObraLocalDataSource localDataSource})
      : _local = localDataSource;

  final ObraLocalDataSource _local;

  @override
  Future<List<Obra>> fetchAll() => _local.getAll();

  @override
  Future<Obra?> findByUuid(String uuid) => _local.findByUuid(uuid);

  @override
  Future<String> createDraft(String name) => _local.createDraft(name);
}
