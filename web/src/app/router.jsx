// Router propio (D-19): 6 rutas, sin librería. El estado de UI del mapa va por replaceState (D-05).
import { useSyncExternalStore } from 'react';

const subs = new Set();
const notify = () => subs.forEach((f) => f());
addEventListener('popstate', notify);

const subscribe = (f) => (subs.add(f), () => subs.delete(f));
const snapshot = () => location.pathname + location.search;

export const useLocation = () => useSyncExternalStore(subscribe, snapshot);

export const useQuery = () => new URLSearchParams(useLocation().split('?')[1] ?? '');

// replaceState no dispara popstate: por eso navigate notifica a mano.
export function navigate(to, { replace = false } = {}) {
  history[replace ? 'replaceState' : 'pushState'](null, '', to);
  notify();
}

// El panel del mapa nunca crea entradas de historial: siempre replaceState. Valor null borra el param.
export function setParams(patch) {
  const u = new URL(location.href);
  for (const [k, v] of Object.entries(patch)) v == null ? u.searchParams.delete(k) : u.searchParams.set(k, v);
  navigate(u.pathname + u.search, { replace: true });
}

const ROUTES = [
  [/^\/$/, 'mapa'],
  [/^\/acceso\/?$/, 'acceso'],
  [/^\/obras\/?$/, 'obras'],
  [/^\/obras\/([^/]+)\/?$/, 'obra'],
  [/^\/artistas\/?$/, 'artistas'],
  [/^\/artistas\/([^/]+)\/?$/, 'artista'],
];

export function matchRoute(pathname) {
  for (const [re, name] of ROUTES) {
    const m = re.exec(pathname);
    if (m) return { name, params: m[1] ? { uuid: decodeURIComponent(m[1]) } : {} };
  }
  return null;
}

const plainLeftClick = (e) =>
  e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey && !e.defaultPrevented;

export const A = ({ href, onClick, ...rest }) => (
  <a
    href={href}
    onClick={(e) => {
      onClick?.(e);
      if (plainLeftClick(e)) (e.preventDefault(), navigate(href));
    }}
    {...rest}
  />
);
