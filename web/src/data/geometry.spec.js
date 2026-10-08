import { describe, it, expect, vi } from 'vitest';
import polygonClipping from 'polygon-clipping';
import { haversineM, medianRadius, findGaps, runs, corridorPx, circlesOutline, OUTLINE_VERTICES } from './geometry.js';

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

describe('circlesOutline (D-20)', () => {
  const MLAT = 1 / 111195; // grados de latitud por metro
  const c = (eastM, r = 12, lat = 0) => ({ latitude: lat, longitude: eastM * M, radius_meters: r });

  it('sin círculos -> null', () => {
    expect(circlesOutline([])).toBeNull();
  });

  it('un círculo: 1 polígono de OUTLINE_VERTICES vértices y bounds que contienen centro ± r (circunscrito)', () => {
    const o = circlesOutline([c(0)]);
    expect(o.polygons).toHaveLength(1);
    expect(o.polygons[0]).toHaveLength(1); // sin agujeros
    expect(o.polygons[0][0]).toHaveLength(OUTLINE_VERTICES);
    expect(o.bounds.minLat).toBeLessThanOrEqual(-12 * MLAT);
    expect(o.bounds.maxLat).toBeGreaterThanOrEqual(12 * MLAT);
    expect(o.bounds.minLon).toBeLessThanOrEqual(-12 * M);
    expect(o.bounds.maxLon).toBeGreaterThanOrEqual(12 * M);
    // y no se pasa más de ~1 % del radio
    expect(o.bounds.maxLat).toBeLessThan(12.2 * MLAT);
  });

  it('3 círculos solapados -> 1 polígono; con un hueco de 40 m > 12 + 12 -> 2 polígonos', () => {
    expect(circlesOutline([c(0), c(10), c(20)]).polygons).toHaveLength(1);
    const ts = [...Array.from({ length: 16 }, (_, i) => c(i * 10)), ...Array.from({ length: 16 }, (_, i) => c(190 + i * 10))];
    expect(circlesOutline(ts).polygons).toHaveLength(2);
  });

  it('100 círculos encadenados -> 1 polígono (bajo el timeout por defecto)', () => {
    const o = circlesOutline(Array.from({ length: 100 }, (_, i) => c(i * 10)));
    expect(o.polygons).toHaveLength(1);
  });

  it('radio <= 0 y coordenadas no finitas se ignoran; si todos lo son -> null', () => {
    expect(circlesOutline([c(0, 0), c(10, -5), { latitude: NaN, longitude: 0, radius_meters: 12 }, { latitude: 0, longitude: Infinity, radius_meters: 12 }])).toBeNull();
    expect(circlesOutline([c(0, 0), c(0)]).polygons).toHaveLength(1);
  });

  it('si la unión lanza, devuelve los círculos sin unir en vez de propagar el error', () => {
    const spy = vi.spyOn(polygonClipping, 'union').mockImplementation(() => { throw new Error('boom'); });
    try {
      const o = circlesOutline([c(0), c(10), c(200)]);
      expect(o.polygons).toHaveLength(3);
      expect(o.bounds.maxLon).toBeGreaterThan(200 * M);
    } finally {
      spy.mockRestore();
    }
  });
});
