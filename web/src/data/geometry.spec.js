import { describe, it, expect } from 'vitest';
import { haversineM, medianRadius, findGaps, runs, corridorPx } from './geometry.js';

const at = (lon, r = 12) => ({ latitude: 0, longitude: lon, radius_meters: r });
const M = 1 / 111195; // grados de lon por metro en el ecuador

describe('geometry', () => {
  it('haversineM: 1° de latitud ≈ 111195 m (±1 m)', () => {
    expect(Math.abs(haversineM({ latitude: 0, longitude: 0 }, { latitude: 1, longitude: 0 }) - 111195)).toBeLessThan(1);
  });

  it('findGaps: 10 m con radio 12 no es hueco; 40 m sí (distancia > r_a + r_b)', () => {
    expect(findGaps([at(0), at(10 * M)])).toEqual([]);
    const g = findGaps([at(0), at(10 * M), at(50 * M)]);
    expect(g).toHaveLength(1);
    expect(g[0]).toMatchObject({ from: 1, to: 2 });
    expect(g[0].meters).toBeCloseTo(40, 0);
  });

  it('findGaps: el umbral es la suma de radios, no un valor fijo', () => {
    expect(findGaps([at(0, 30), at(40 * M, 30)])).toEqual([]);
    expect(findGaps([at(0, 5), at(40 * M, 5)])).toHaveLength(1);
  });

  it('runs corta los tramos en cada hueco', () => {
    const ts = [at(0), at(10 * M), at(50 * M), at(60 * M)];
    const out = runs(ts, findGaps(ts));
    expect(out.map((r) => r.length)).toEqual([2, 2]);
    expect(runs(ts, [])).toHaveLength(1);
    expect(runs([], [])).toEqual([]);
  });

  it('medianRadius', () => {
    expect(medianRadius([at(0, 10), at(0, 30), at(0, 12)])).toBe(12);
    expect(medianRadius([at(0, 10), at(0, 20)])).toBe(15);
    expect(medianRadius([])).toBe(0);
  });

  it('corridorPx(12, -42, 16) ≈ 13,5 (±0,1)', () => {
    expect(Math.abs(corridorPx(12, -42, 16) - 13.5)).toBeLessThan(0.1);
  });
});
