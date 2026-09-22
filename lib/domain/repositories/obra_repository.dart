import '../entities/obra.dart';

abstract class ObraRepository {
  Future<List<Obra>> fetchAll();
  Future<Obra?> findByUuid(String uuid);

  /// Obra nueva con visibility 'draft'; devuelve su uuid.
  Future<String> createDraft(String name);
}
