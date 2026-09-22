/// Recorrido o portal. La geometría son sus triggers.
class GeoPath {
  GeoPath({
    required this.uuid,
    required this.obraUuid,
    required this.name,
    this.kind = 'route', // 'route' | 'portal'
    this.audioUuid,
    this.grabacionUuid,
    this.toleranceMeters = 10.0,
    this.savedOffsetMs = 0,
    this.updatedAt,
    this.deletedAt,
    this.logicalVersion,
  });

  final String uuid, obraUuid, kind, name;
  final String? audioUuid, grabacionUuid;
  final double toleranceMeters;

  /// Viene de path_progress (solo local).
  int savedOffsetMs;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? logicalVersion;
}
