import '../../domain/entities/obra.dart';
import 'sync_meta.dart';

class ObraModel extends Obra {
  const ObraModel({
    required super.uuid,
    required super.name,
    super.visibility,
    super.ownerId,
    super.shareToken,
    super.coverLat,
    super.coverLon,
    super.coverMinLat,
    super.coverMaxLat,
    super.coverMinLon,
    super.coverMaxLon,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory ObraModel.fromMap(Map<String, Object?> m) {
    double? d(String k) => (m[k] as num?)?.toDouble();
    return ObraModel(
      uuid: m['uuid'] as String,
      name: m['name'] as String,
      visibility: (m['visibility'] as String?) ?? 'draft',
      ownerId: m['owner_id'] as String?,
      shareToken: m['share_token'] as String?,
      coverLat: d('cover_lat'),
      coverLon: d('cover_lon'),
      coverMinLat: d('cover_min_lat'),
      coverMaxLat: d('cover_max_lat'),
      coverMinLon: d('cover_min_lon'),
      coverMaxLon: d('cover_max_lon'),
      updatedAt: dateFromSeconds(m['updated_at']),
      deletedAt: dateFromSeconds(m['deleted_at']),
      logicalVersion: m['logical_version'] as int?,
    );
  }
}
