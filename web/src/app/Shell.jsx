import { clearKey } from './session.js';
import { navigate } from './router.jsx';

// La SyncPill la monta 12-02 y la nav Mapa/Obras/Artistas la monta 12-09.
export default function Shell({ children }) {
  return (
    <div className="app">
      <header className="hdr">
        <div className="brand">
          <span className="cg-portal-type">Cíngula</span>
          <span className="lbl">Web de lectura</span>
        </div>
        <div className="sp" />
        <button
          type="button"
          className="quiet"
          onClick={() => {
            clearKey();
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
