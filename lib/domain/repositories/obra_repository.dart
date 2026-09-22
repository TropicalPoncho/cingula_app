import '../entities/obra.dart';

abstract class ObraRepository {
  Future<List<Obra>> fetchAll();
  Future<Obra?> findByUuid(String uuid);

  /// Obra nueva con visibility 'draft'; devuelve su uuid.
  Future<String> createDraft(String name);

  /// Recalcula la cobertura (cover_lat/lon/min/max) desde los triggers de sus paths.
  /// Solo escribe si algún valor cambió (D-16/D-29).
  Future<void> refreshCover(String obraUuid);
}
