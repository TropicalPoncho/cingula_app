/// Unidad de publicación: agrupa paths (recorridos y portales).
class Obra {
  const Obra({
    required this.uuid,
    required this.name,
    this.visibility = 'draft',
    this.ownerId,
    this.shareToken,
    this.coverLat,
    this.coverLon,
    this.coverMinLat,
    this.coverMaxLat,
    this.coverMinLon,
    this.coverMaxLon,
    this.updatedAt,
    this.deletedAt,
    this.logicalVersion,
  });

  final String uuid;
  final String name;
  final String visibility;
  final String? ownerId, shareToken;
  final double? coverLat, coverLon, coverMinLat, coverMaxLat, coverMinLon, coverMaxLon;
  final DateTime? updatedAt, deletedAt;
  final int? logicalVersion;
}
