/// Audio disponible para reproducción geolocalizada.
class AudioAsset {
  const AudioAsset({
    required this.uuid,
    required this.title,
    required this.description,
    required this.duration,
    required this.localPath,
    this.kind = 'grabacion', // 'grabacion' | 'final'
    this.remoteUrl,
    this.storageKey,
    this.checksum,
    this.updatedAt,
    this.deletedAt,
    this.logicalVersion,
  });

  final String uuid;
  final String kind;
  final String title;
  final String description;
  final Duration duration;

  /// Viene de audio_local (solo local, nunca se sincroniza).
  final String localPath;
  final Uri? remoteUrl;
  final String? storageKey, checksum;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? logicalVersion;
}
