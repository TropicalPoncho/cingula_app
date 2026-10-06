import { describe, it, expect } from 'vitest';
import { getKey, setKey, clearKey } from './session.js';

describe('session', () => {
  it('sin clave devuelve null', () => {
    expect(getKey()).toBeNull();
  });

  it('set/get/clear', () => {
    setKey('abc');
    expect(getKey()).toBe('abc');
    clearKey();
    expect(getKey()).toBeNull();
  });

  it('guarda sólo en sessionStorage (almacenamiento persistente vacío)', () => {
    setKey('abc');
    expect(sessionStorage.getItem('cingula.key')).toBe('abc');
    expect(localStorage.length).toBe(0);
    expect(location.href).not.toContain('abc');
  });
});
