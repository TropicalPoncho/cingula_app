class Cover {
  const Cover({
    this.centerLat,
    this.centerLon,
    this.minLat,
    this.maxLat,
    this.minLon,
    this.maxLon,
  });
  final double? centerLat, centerLon, minLat, maxLat, minLon, maxLon;
}

/// Media aritmetica del centro + caja min/max, todo redondeado a 6 decimales
/// alejandose del cero. La MISMA formula esta portada en backend/api/_lib/cover.js;
/// si una cambia, el vector compartido de vectors_test.dart / vectors.test.js falla.
double _r6(double x) => (x * 1e6).round() / 1e6;

Cover computeCover(List<({double lat, double lon})> points) {
  if (points.isEmpty) return const Cover();
  var sumLat = 0.0, sumLon = 0.0;
  var minLat = points.first.lat, maxLat = minLat;
  var minLon = points.first.lon, maxLon = minLon;
  for (final p in points) {
    sumLat += p.lat;
    sumLon += p.lon;
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  final n = points.length;
  return Cover(
    centerLat: _r6(sumLat / n),
    centerLon: _r6(sumLon / n),
    minLat: _r6(minLat),
    maxLat: _r6(maxLat),
    minLon: _r6(minLon),
    maxLon: _r6(maxLon),
  );
}
