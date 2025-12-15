import 'dart:convert';

import '../../domain/entities/geo_path.dart';

class GeoPathModel extends GeoPath {
  GeoPathModel({
    required super.id,
    required super.name,
    required super.audioAssetId,
    super.toleranceMeters,
    super.savedOffsetMs,
    super.uuid,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory GeoPathModel.fromMap(Map<String, Object?> map) {
    return GeoPathModel(
      id: (map['id'] as int),
      name: (map['name'] as String),
      audioAssetId: (map['audio_asset_id'] as int),
      toleranceMeters: ((map['tolerance_meters'] as num?)?.toDouble() ?? 10.0),
      savedOffsetMs: (map['saved_offset_ms'] as int?) ?? 0,
      uuid: map['uuid'] as String?,
      updatedAt: (map['updated_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch((map['updated_at'] as int) * 1000) : null,
      deletedAt: (map['deleted_at'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch((map['deleted_at'] as int) * 1000) : null,
      logicalVersion: map['logical_version'] as int?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      // keep points column for compatibility but write empty array
      'points': json.encode([]),
      'audio_asset_id': audioAssetId,
      'tolerance_meters': toleranceMeters,
      'saved_offset_ms': savedOffsetMs,
      'uuid': uuid,
      'updated_at': updatedAt != null ? updatedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'deleted_at': deletedAt != null ? deletedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'logical_version': logicalVersion,
    };
  }
}
