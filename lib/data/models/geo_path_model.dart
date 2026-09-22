import '../../domain/entities/geo_path.dart';
import 'sync_meta.dart';

class GeoPathModel extends GeoPath {
  GeoPathModel({
    required super.uuid,
    required super.obraUuid,
    required super.name,
    super.kind,
    super.audioUuid,
    super.grabacionUuid,
    super.toleranceMeters,
    super.savedOffsetMs,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  /// `saved_offset_ms` viene del LEFT JOIN con path_progress (0 si no hay fila).
  factory GeoPathModel.fromMap(Map<String, Object?> map) => GeoPathModel(
        uuid: map['uuid'] as String,
        obraUuid: map['obra_uuid'] as String,
        kind: (map['kind'] as String?) ?? 'route',
        name: map['name'] as String,
        audioUuid: map['audio_uuid'] as String?,
        grabacionUuid: map['grabacion_uuid'] as String?,
        toleranceMeters: (map['tolerance_meters'] as num?)?.toDouble() ?? 10.0,
        savedOffsetMs: (map['saved_offset_ms'] as int?) ?? 0,
        updatedAt: dateFromSeconds(map['updated_at']),
        deletedAt: dateFromSeconds(map['deleted_at']),
        logicalVersion: map['logical_version'] as int?,
      );

  /// SOLO columnas de `paths`: el progreso es local y no se sincroniza.
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'obra_uuid': obraUuid,
        'kind': kind,
        'name': name,
        'audio_uuid': audioUuid,
        'grabacion_uuid': grabacionUuid,
        'tolerance_meters': toleranceMeters,
        'updated_at': secondsFromDate(updatedAt),
        'deleted_at': secondsFromDate(deletedAt),
        'logical_version': logicalVersion,
      };
}
