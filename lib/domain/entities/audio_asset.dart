/// Entidad que describe un audio disponible para reproducción geolocalizada.
class AudioAsset {
  const AudioAsset({
    required this.id,
    required this.title,
    required this.artist,
    required this.description,
    required this.duration,
    required this.localPath,
    this.remoteUrl,
    this.uuid,
    this.updatedAt,
    this.deletedAt,
    this.logicalVersion,
  });

  final int id;
  final String title;
  final String artist;
  final String description;
  final Duration duration;
  final String localPath;
  final Uri? remoteUrl;

  /// Metadatos de sincronización
  final String? uuid;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? logicalVersion;
}

