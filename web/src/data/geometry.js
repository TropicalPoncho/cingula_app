// Geometría pura. Sin Leaflet: Leaflet usa `window` al cargar y este módulo también corre en Node (12-03).
// Siempre el export por defecto de polygon-clipping (ESM sólo lo tiene así y Node resuelve el CJS).
import polygonClipping from 'polygon-clipping';

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

// ponytail: polígono CIRCUNSCRITO de 24 lados (radio / cos(π/24)): el error es hacia afuera, ≈ 0,9 % del radio (≈ 0,17 m con r = 20 m),
// así el contorno nunca queda adentro de la zona real de activación y dos círculos que apenas se tocan quedan unidos. Upgrade = más vértices.
export const OUTLINE_VERTICES = 24;

// Unión de círculos `{ latitude, longitude, radius_meters }` -> { polygons: MultiPolygon [lat, lon] (orden de Leaflet), bounds } | null.
// Radio <= 0 o coordenadas no finitas se ignoran. Se calcula una vez por pull (buildModel), nunca por frame.
export function circlesOutline(circles) {
  const rings = [];
  for (const c of circles) {
    if (!Number.isFinite(c.latitude) || !Number.isFinite(c.longitude) || !(c.radius_meters > 0)) continue;
    const dLat = ((c.radius_meters / Math.cos(Math.PI / OUTLINE_VERTICES)) * 180) / (Math.PI * R);
    const dLon = dLat / Math.cos(rad(c.latitude));
    rings.push(Array.from({ length: OUTLINE_VERTICES }, (_, k) => {
      const a = (2 * Math.PI * k) / OUTLINE_VERTICES;
      return [c.longitude + dLon * Math.cos(a), c.latitude + dLat * Math.sin(a)]; // [x, y] = [lon, lat]
    }));
  }
  if (!rings.length) return null;

  let multi;
  try {
    multi = polygonClipping.union(...rings.map((r) => [r]));
  } catch {
    // ponytail: la unión (robust-predicates) es la vía normal; el respaldo deja costuras internas visibles pero nunca deja la web en blanco.
    multi = rings.map((r) => [r]);
  }

  let minLat = Infinity, maxLat = -Infinity, minLon = Infinity, maxLon = -Infinity;
  const polygons = multi.map((poly) => poly.map((ring) => {
    const pts = ring.map(([lon, lat]) => {
      minLat = Math.min(minLat, lat); maxLat = Math.max(maxLat, lat);
      minLon = Math.min(minLon, lon); maxLon = Math.max(maxLon, lon);
      return [lat, lon];
    });
    const [f, l] = [pts[0], pts.at(-1)];
    return pts.length > 1 && f[0] === l[0] && f[1] === l[1] ? pts.slice(0, -1) : pts; // sin el vértice de cierre repetido
  }));
  return { polygons, bounds: { minLat, maxLat, minLon, maxLon } };
}
