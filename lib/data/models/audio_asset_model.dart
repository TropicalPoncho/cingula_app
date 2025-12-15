import '../../domain/entities/audio_asset.dart';

/// Mapea filas SQLite al modelo de dominio de audio.
class AudioAssetModel extends AudioAsset {
  AudioAssetModel({
    required super.id,
    required super.title,
    required super.artist,
    required super.description,
    required super.duration,
    required super.localPath,
    super.remoteUrl,
    super.uuid,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory AudioAssetModel.fromMap(Map<String, Object?> map) {
    final seconds = map['duration_seconds'] as int;
    final remoteUrl = map['remote_url'] as String?;
    final updatedAtSec = map['updated_at'] as int?;
    final deletedAtSec = map['deleted_at'] as int?;
    return AudioAssetModel(
      id: map['id'] as int,
      title: map['title'] as String,
      artist: map['artist'] as String,
      description: map['description'] as String,
      duration: Duration(seconds: seconds),
      localPath: map['local_path'] as String,
      remoteUrl:
          remoteUrl == null || remoteUrl.isEmpty ? null : Uri.parse(remoteUrl),
      uuid: map['uuid'] as String?,
      updatedAt: updatedAtSec != null ? DateTime.fromMillisecondsSinceEpoch(updatedAtSec * 1000) : null,
      deletedAt: deletedAtSec != null ? DateTime.fromMillisecondsSinceEpoch(deletedAtSec * 1000) : null,
      logicalVersion: map['logical_version'] as int?,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'description': description,
        'duration_seconds': duration.inSeconds,
        'local_path': localPath,
        'remote_url': remoteUrl?.toString(),
        'uuid': uuid,
        'updated_at': updatedAt != null ? updatedAt!.millisecondsSinceEpoch ~/ 1000 : null,
        'deleted_at': deletedAt != null ? deletedAt!.millisecondsSinceEpoch ~/ 1000 : null,
        'logical_version': logicalVersion,
      };
}
