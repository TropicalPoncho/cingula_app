import { useStore, retryNow } from '../data/store.js';
import { A } from '../app/router.jsx';
import { visOf } from '../panel/buildView.js';
import './pages.css';

// Visibilidad de una obra: punto + etiqueta (mismo mapa que el detalle, `visOf`).
export function Vis({ value }) {
  const v = visOf(value);
  return (
    <span className="vis">
      <span className="dot" style={{ background: v.dot }} />
      <span className={v.mono ? 'mono' : undefined}>{v.label}</span>
    </span>
  );
}

// 3 filas esqueleto: bloques --surface-raised sin shimmer (el DS no define esqueletos).
function Skeleton() {
  return (
    <div aria-hidden="true">
      {[0, 1, 2].map((i) => <div key={i} className="ent skel" />)}
    </div>
  );
}

// Primera lectura fallida y sin datos: mismo copy que el velo del mapa, dentro del listado.
function ReadError() {
  const { errors } = useStore();
  const code = errors.at(-1)?.status ?? 'sin respuesta';
  return (
    <div className="perr" role="alert">
      <span className="lbl">No se pudo leer el servidor.</span>
      <span>GET /sync/pull → {code}. Revisá tu conexión y reintentá.</span>
      <button type="button" className="btn" onClick={retryNow}>Reintentar lectura</button>
    </div>
  );
}

// Estados de página (E4/E5) del listado: cargando, error sin datos, vacío (`total` = sin filtros) o el contenido.
export function ListGate({ total, emptyText, children }) {
  const { lastPullAt, status } = useStore();
  if (lastPullAt == null) return status === 'error' ? <ReadError /> : <Skeleton />;
  if (total === 0) return <p className="dim">{emptyText}</p>;
  return children;
}

// uuid de la URL que no existe en el modelo (T-12-32): mensaje fijo, el texto de la URL nunca se renderiza.
export function NotFound({ text, href }) {
  return (
    <div className="notfound">
      <p>{text}</p>
      <A className="btn" href={href}>Volver al listado</A>
    </div>
  );
}

// < 900 px el detalle reemplaza al listado (CSS) y esto es el camino de vuelta; en escritorio no se ve.
export const BackToList = ({ href }) => <A className="btn backlist" href={href}>Volver al listado</A>;
