import '../../domain/entities/audio_asset.dart';
import 'sync_meta.dart';

/// Fila de `audios` (+ `audio_local` vía JOIN) -> dominio.
class AudioAssetModel extends AudioAsset {
  AudioAssetModel({
    required super.uuid,
    required super.title,
    required super.description,
    required super.duration,
    required super.localPath,
    super.kind,
    super.remoteUrl,
    super.storageKey,
    super.checksum,
    super.updatedAt,
    super.deletedAt,
    super.logicalVersion,
  });

  factory AudioAssetModel.fromMap(Map<String, Object?> map) {
    final remoteUrl = map['remote_url'] as String?;
    return AudioAssetModel(
      uuid: map['uuid'] as String,
      kind: (map['kind'] as String?) ?? 'grabacion',
      title: map['title'] as String,
      description: (map['description'] as String?) ?? '',
      duration: Duration(seconds: (map['duration_seconds'] as int?) ?? 0),
      // audio_local puede faltar (audio sin archivo en este dispositivo)
      localPath: (map['local_path'] as String?) ?? '',
      remoteUrl: remoteUrl == null || remoteUrl.isEmpty ? null : Uri.parse(remoteUrl),
      storageKey: map['storage_key'] as String?,
      checksum: map['checksum'] as String?,
      updatedAt: dateFromSeconds(map['updated_at']),
      deletedAt: dateFromSeconds(map['deleted_at']),
      logicalVersion: map['logical_version'] as int?,
    );
  }

  /// SOLO columnas de `audios` (lo que se sincroniza).
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'kind': kind,
        'title': title,
        'description': description,
        'duration_seconds': duration.inSeconds,
        'storage_key': storageKey,
        'checksum': checksum,
        'updated_at': secondsFromDate(updatedAt),
        'deleted_at': secondsFromDate(deletedAt),
        'logical_version': logicalVersion,
      };

  /// Columnas de `audio_local` (solo local).
  Map<String, Object?> toLocalMap() => {
        'audio_uuid': uuid,
        'local_path': localPath,
        'remote_url': remoteUrl?.toString(),
      };
}
