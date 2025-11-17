import 'dart:convert';

import '../../domain/entities/geo_path.dart';

class GeoPathModel extends GeoPath {
  GeoPathModel({
    required super.id,
    required super.name,
    required super.audioAssetId,
    super.toleranceMeters,
    super.savedOffsetMs,
  });

  factory GeoPathModel.fromMap(Map<String, Object?> map) {
    return GeoPathModel(
      id: (map['id'] as int),
      name: (map['name'] as String),
      audioAssetId: (map['audio_asset_id'] as int),
      toleranceMeters: ((map['tolerance_meters'] as num?)?.toDouble() ?? 10.0),
      savedOffsetMs: (map['saved_offset_ms'] as int?) ?? 0,
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
    };
  }
}
