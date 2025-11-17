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
  });

  final int id;
  final String title;
  final String artist;
  final String description;
  final Duration duration;
  final String localPath;
  final Uri? remoteUrl;
}

