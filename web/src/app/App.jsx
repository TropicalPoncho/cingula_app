import { useEffect } from 'react';
import { useLocation, matchRoute, navigate } from './router.jsx';
import { getKey } from './session.js';
import { useStore, load } from '../data/store.js';
import Shell from './Shell.jsx';
import Acceso from '../pages/Acceso.jsx';

export default function App() {
  const route = matchRoute(useLocation().split('?')[0]);
  const name = route?.name;
  const authed = getKey() !== null;
  const { status } = useStore();

  // Guard: sin clave sólo existe /acceso; ruta desconocida vuelve al mapa.
  useEffect(() => {
    if (name !== 'acceso' && !authed) navigate('/acceso', { replace: true });
    else if (!route) navigate('/', { replace: true });
  });

  // Con clave presente, una sola lectura del servidor por pestaña.
  useEffect(() => {
    if (authed && name !== 'acceso' && status === 'idle') load();
  }, [authed, name, status]);

  if (name === 'acceso') return <Acceso />;
  if (!authed || !route) return null;
  // El contenido del home (mapa) lo agrega 12-02; Obras/Artistas, 12-09.
  return <Shell />;
}
