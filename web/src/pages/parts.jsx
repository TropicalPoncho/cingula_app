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
