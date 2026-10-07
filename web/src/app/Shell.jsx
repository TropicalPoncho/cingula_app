import { clearKey } from './session.js';
import { A, navigate, useLocation } from './router.jsx';
import SyncPill from './SyncPill.jsx';
import { resetStore } from '../data/store.js';

const SECTIONS = [['/', 'Mapa'], ['/obras', 'Obras'], ['/artistas', 'Artistas']];

export default function Shell({ children }) {
  const path = useLocation().split('?')[0];
  // Activa = la sección que contiene la ruta (/obras/:uuid cuenta como Obras).
  const on = (href) => (href === '/' ? path === '/' : path === href || path.startsWith(`${href}/`));
  return (
    <div className="app">
      <header className="hdr">
        <div className="brand">
          <span className="cg-portal-type">Cíngula</span>
          <span className="lbl">Web de lectura</span>
        </div>
        <nav className="nav" aria-label="Secciones">
          {SECTIONS.map(([href, label]) => (
            <A key={href} href={href} className={`nl${on(href) ? ' on' : ''}`} aria-current={on(href) ? 'page' : undefined}>
              {label}
            </A>
          ))}
        </nav>
        <div className="sp" />
        <SyncPill />
        <button
          type="button"
          className="quiet"
          onClick={() => {
            clearKey();
            resetStore();
            navigate('/acceso');
          }}
        >
          Salir de la web
        </button>
      </header>
      <main className="shell-main">{children}</main>
    </div>
  );
}
