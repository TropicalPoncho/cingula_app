import { describe, it, expect } from 'vitest';
import { plural, rel, fms, mmss, latlon, meters } from './format.js';

describe('format', () => {
  it('plural', () => {
    expect(plural(1, 'obra', 'obras')).toBe('1 obra');
    expect(plural(0, 'obra', 'obras')).toBe('0 obras');
    expect(plural(2, 'portal', 'portales')).toBe('2 portales');
  });
  it('fms: separador de miles con espacio', () => {
    expect(fms(1200)).toBe('+1 200 ms');
    expect(fms(950)).toBe('+950 ms');
    expect(fms(1234567)).toBe('+1 234 567 ms');
  });
  it('mmss', () => {
    expect(mmss(75)).toBe('01:15');
    expect(mmss(5)).toBe('00:05');
  });
  it('rel', () => {
    expect(rel(12_000)).toBe('12 s');
    expect(rel(3 * 60_000)).toBe('3 min');
    expect(rel(2 * 3600_000)).toBe('2 h');
    expect(rel(-5)).toBe('0 s');
  });
  it('latlon: 5 decimales; meters', () => {
    expect(latlon(-42.08, -71.62)).toBe('-42.08000, -71.62000');
    expect(meters(1234)).toBe('1 234 m');
  });
});
