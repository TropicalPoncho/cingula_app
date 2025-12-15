import '../../domain/entities/geo_trigger.dart';

/// Traduce registros de geozonas a la entidad de dominio.
class GeoTriggerModel extends GeoTrigger {
  GeoTriggerModel({
    required super.id,
    required super.name,
    required super.description,
    required super.latitude,
    required super.longitude,
    required super.radiusMeters,
    required super.audioAssetId,
    super.regionId,
    super.geoPathId,
    super.offsetMs,
    super.uuid,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory GeoTriggerModel.fromMap(Map<String, Object?> map) {
    return GeoTriggerModel(
      id: map['id'] as int,
      name: map['name'] as String,
      description: map['description'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: (map['radius_meters'] as num).toDouble(),
      audioAssetId: map['audio_asset_id'] as int,
      regionId: (map['region_id'] as int?),
      geoPathId: (map['geo_path_id'] as int?),
      offsetMs: (map['offset_ms'] as int?) ?? 0,
      uuid: map['uuid'] as String?,
      updatedAt: (map['updated_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch((map['updated_at'] as int) * 1000) : null,
      deletedAt: (map['deleted_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch((map['deleted_at'] as int) * 1000) : null,
      logicalVersion: map['logical_version'] as int?,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
    'audio_asset_id': audioAssetId,
    'region_id': regionId,
    'geo_path_id': geoPathId,
    'offset_ms': offsetMs,
        'uuid': uuid,
        'updated_at': updatedAt != null ? updatedAt!.millisecondsSinceEpoch ~/ 1000 : null,
        'deleted_at': deletedAt != null ? deletedAt!.millisecondsSinceEpoch ~/ 1000 : null,
        'logical_version': logicalVersion,
      };
}

