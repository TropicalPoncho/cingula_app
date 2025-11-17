/// Representa una posición GPS simplificada para uso en dominio.
class Coordinate {
  const Coordinate({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? timestamp;
}

