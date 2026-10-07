// Geometría pura. Sin Leaflet: Leaflet usa `window` al cargar y este módulo también corre en Node (12-03).
const R = 6371000; // mismo R que L.CRS.Earth
const rad = (d) => (d * Math.PI) / 180;

export function haversineM(a, b) {
  const dLat = rad(b.latitude - a.latitude);
  const dLon = rad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function median(xs) {
  const s = [...xs].sort((x, y) => x - y);
  const n = s.length;
  if (!n) return 0;
  return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
}

// ponytail: un solo ancho de corredor por path (mediana de radios, OI-10); radios mixtos >10 % se dibujan con el ancho mediano. Upgrade: ancho por tramo.
export const medianRadius = (ts) => median(ts.map((t) => t.radius_meters));

// `ts` ya ordenados por (position, uuid). Hueco = distancia > r_a + r_b (regla de la UI-SPEC).
export function findGaps(ts) {
  const gaps = [];
  for (let i = 0; i + 1 < ts.length; i++) {
    const meters = haversineM(ts[i], ts[i + 1]);
    if (meters > ts[i].radius_meters + ts[i + 1].radius_meters) gaps.push({ from: i, to: i + 1, meters });
  }
  return gaps;
}

// Tramos continuos (cortados en cada hueco): un polyline por tramo.
export function runs(ts, gaps) {
  const cut = new Set(gaps.map((g) => g.from));
  const out = [];
  let cur = [];
  ts.forEach((t, i) => {
    cur.push(t);
    if (cut.has(i)) {
      out.push(cur);
      cur = [];
    }
  });
  if (cur.length) out.push(cur);
  return out;
}

// Ancho en px de un corredor de diámetro 2·r metros a esa latitud y zoom.
export const corridorPx = (radiusM, latDeg, zoom) =>
  (2 * radiusM) / ((156543.03392 * Math.cos(rad(latDeg))) / 2 ** zoom);
