import '../../domain/entities/geo_trigger.dart';
import 'sync_meta.dart';

/// Traduce registros de `triggers` a la entidad de dominio.
class GeoTriggerModel extends GeoTrigger {
  GeoTriggerModel({
    required super.uuid,
    required super.pathUuid,
    required super.name,
    required super.description,
    required super.latitude,
    required super.longitude,
    required super.radiusMeters,
    super.position,
    super.offsetMs,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory GeoTriggerModel.fromMap(Map<String, Object?> map) => GeoTriggerModel(
        uuid: map['uuid'] as String,
        pathUuid: map['path_uuid'] as String,
        position: (map['position'] as int?) ?? 0,
        name: map['name'] as String,
        description: (map['description'] as String?) ?? '',
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        radiusMeters: (map['radius_meters'] as num).toDouble(),
        offsetMs: (map['offset_ms'] as int?) ?? 0,
        updatedAt: dateFromSeconds(map['updated_at']),
        deletedAt: dateFromSeconds(map['deleted_at']),
        logicalVersion: map['logical_version'] as int?,
      );

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'path_uuid': pathUuid,
        'position': position,
        'name': name,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'offset_ms': offsetMs,
        'updated_at': secondsFromDate(updatedAt),
        'deleted_at': secondsFromDate(deletedAt),
        'logical_version': logicalVersion,
      };
}
