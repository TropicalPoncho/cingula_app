import '../../domain/entities/region.dart';
import '../../domain/value_objects/coordinate.dart';

class RegionModel extends Region {
  RegionModel({
    required super.id,
    required super.name,
    required super.center,
    required super.radiusMeters,
    super.sampleCoarseSeconds,
    super.sampleFineSeconds,
    super.coarseDistanceFilterMeters,
    super.fineDistanceFilterMeters,
    super.uuid,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory RegionModel.fromMap(Map<String, Object?> map) {
    return RegionModel(
      id: map['id'] as int,
      name: map['name'] as String,
      center: Coordinate(
        latitude: (map['center_lat'] as num).toDouble(),
        longitude: (map['center_lon'] as num).toDouble(),
      ),
      radiusMeters: (map['radius_meters'] as num).toDouble(),
      sampleCoarseSeconds: (map['sample_coarse_seconds'] as int?) ?? 30,
      sampleFineSeconds: (map['sample_fine_seconds'] as int?) ?? 2,
      coarseDistanceFilterMeters: (map['coarse_distance_filter_meters'] as int?) ?? 500,
      fineDistanceFilterMeters: (map['fine_distance_filter_meters'] as int?) ?? 5,
      uuid: map['uuid'] as String?,
      updatedAt: (map['updated_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch((map['updated_at'] as int) * 1000) : null,
      deletedAt: (map['deleted_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch((map['deleted_at'] as int) * 1000) : null,
      logicalVersion: map['logical_version'] as int?,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'center_lat': center.latitude,
        'center_lon': center.longitude,
        'radius_meters': radiusMeters,
        'sample_coarse_seconds': sampleCoarseSeconds,
        'sample_fine_seconds': sampleFineSeconds,
        'coarse_distance_filter_meters': coarseDistanceFilterMeters,
        'fine_distance_filter_meters': fineDistanceFilterMeters,
        'uuid': uuid,
        'updated_at': updatedAt != null ? updatedAt!.millisecondsSinceEpoch ~/ 1000 : null,
        'deleted_at': deletedAt != null ? deletedAt!.millisecondsSinceEpoch ~/ 1000 : null,
        'logical_version': logicalVersion,
      };
}
