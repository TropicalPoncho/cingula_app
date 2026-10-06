import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { matchRoute, navigate, setParams, useLocation } from './router.jsx';

describe('matchRoute', () => {
  it.each([
    ['/', { name: 'mapa', params: {} }],
    ['/acceso', { name: 'acceso', params: {} }],
    ['/obras', { name: 'obras', params: {} }],
    ['/obras/abc-1', { name: 'obra', params: { uuid: 'abc-1' } }],
    ['/artistas', { name: 'artistas', params: {} }],
    ['/artistas/xyz', { name: 'artista', params: { uuid: 'xyz' } }],
  ])('%s', (path, expected) => {
    expect(matchRoute(path)).toEqual(expected);
  });

  it('ruta desconocida -> null', () => {
    expect(matchRoute('/recorridos')).toBeNull();
    expect(matchRoute('/obras/a/b')).toBeNull();
  });
});

describe('navigate / setParams', () => {
  it('navigate notifica a los suscriptores (useLocation)', () => {
    const { result } = renderHook(() => useLocation());
    act(() => navigate('/obras?x=1'));
    expect(result.current).toBe('/obras?x=1');
    act(() => navigate('/', { replace: true }));
    expect(result.current).toBe('/');
  });

  it('setParams escribe y borra params sin aumentar history.length', () => {
    navigate('/', { replace: true });
    const before = history.length;
    const spy = vi.spyOn(history, 'pushState');
    setParams({ rec: 'r1', modo: 'circ' });
    expect(location.search).toBe('?rec=r1&modo=circ');
    setParams({ modo: null });
    expect(location.search).toBe('?rec=r1');
    expect(history.length).toBe(before);
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
    navigate('/', { replace: true });
  });
});
