import { useEffect } from 'react';
import { useLocation, matchRoute, navigate } from './router.jsx';
import { getKey } from './session.js';
import { useStore, load } from '../data/store.js';
import Shell from './Shell.jsx';
import Acceso from '../pages/Acceso.jsx';
import MapPage from '../pages/MapPage.jsx';
import Obras from '../pages/Obras.jsx';
import Artistas from '../pages/Artistas.jsx';

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
  const { uuid } = route.params; // sólo /obras/:uuid y /artistas/:uuid lo traen
  return (
    <Shell>
      {name === 'mapa' && <MapPage />}
      {(name === 'obras' || name === 'obra') && <Obras uuid={uuid} />}
      {(name === 'artistas' || name === 'artista') && <Artistas uuid={uuid} />}
    </Shell>
  );
}
