// GeoPath now represents only metadata (id, name, audioAssetId, tolerance, offset).
// The actual sequence/geometry of the path is modelled by a collection of
// GeoTriggers that reference `geo_path_id`.

/// Representa un camino (lista de coordenadas) asociado a un audio.
class GeoPath {
  GeoPath({
    required this.id,
    required this.name,
    required this.audioAssetId,
    this.toleranceMeters = 10.0,
    this.savedOffsetMs = 0,
    this.uuid,
    this.updatedAt,
    this.deletedAt,
    this.logicalVersion,
  });

  final int id;
  final String name;
  final int audioAssetId;
  final double toleranceMeters;
  int savedOffsetMs;

  /// Metadatos de sincronización
  final String? uuid;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? logicalVersion;
}
