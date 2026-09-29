// Misma formula que lib/data/migration/cover.dart. El vector compartido lo vigila.
// Math.sign/abs: replica el redondeo de Dart (.5 se aleja del cero); Math.round a secas diverge en negativos.
const r6 = (x) => (Math.sign(x) * Math.round(Math.abs(x) * 1e6)) / 1e6;

export function computeCover(points) {
  if (!points.length) {
    return { centerLat: null, centerLon: null, minLat: null, maxLat: null, minLon: null, maxLon: null };
  }
  let sumLat = 0, sumLon = 0;
  let minLat = points[0].lat, maxLat = minLat;
  let minLon = points[0].lon, maxLon = minLon;
  for (const p of points) {
    sumLat += p.lat;
    sumLon += p.lon;
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  const n = points.length;
  return {
    centerLat: r6(sumLat / n), centerLon: r6(sumLon / n),
    minLat: r6(minLat), maxLat: r6(maxLat), minLon: r6(minLon), maxLon: r6(maxLon),
  };
}
export { r6 };
