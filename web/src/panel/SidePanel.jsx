import { ChevronLeft, Maximize2, Minimize2, X } from 'lucide-react';
import { A } from '../app/router.jsx';
import EntityDetail from './EntityDetail.jsx';
import './panel.css';

function Crumbs({ crumbs, onSelect }) {
  return (
    <nav className="crumbs" aria-label="Ruta">
      {crumbs.map((c, i) => (
        <span className="crumbi" key={i}>
          {i > 0 && <span className="s" aria-hidden="true">/</span>}
          {i === crumbs.length - 1 ? (
            <span className="cur" title={c.label} aria-current="page">{c.label}</span>
          ) : c.href ? (
            <A className="crumb" href={c.href}>{c.label}</A>
          ) : (
            <button type="button" className="crumb" title={c.label} onClick={() => onSelect(c.sel)}>{c.label}</button>
          )}
        </span>
      ))}
    </nav>
  );
}

// Panel único (D-06): el chrome no conoce los tipos; el contenido lo decide buildView. Estado de
// ancho y de plegado lo posee quien lo monta (MapPage), el panel sólo avisa.
export default function SidePanel({ view, expanded, onExpand, onCollapse, onClose, onSelect }) {
  if (!view) return null;
  const Expand = expanded ? Minimize2 : Maximize2;
  return (
    <aside className={`panel${expanded ? ' exp' : ''}`} aria-label="Detalle del elemento seleccionado">
      <div className="phead">
        <Crumbs crumbs={view.crumbs} onSelect={onSelect} />
        <div className="ptools">
          <button
            type="button"
            className="ib"
            aria-label={expanded ? 'Volver al panel angosto' : 'Expandir a pantalla completa'}
            onClick={() => onExpand(!expanded)}
          >
            <Expand size={20} aria-hidden="true" />
          </button>
          <button type="button" className="ib" aria-label="Plegar panel" onClick={() => onCollapse(true)}>
            <ChevronLeft size={20} aria-hidden="true" />
          </button>
          <button type="button" className="ib" aria-label="Cerrar panel" onClick={onClose}>
            <X size={20} aria-hidden="true" />
          </button>
        </div>
      </div>
      <div className="pbody">
        <EntityDetail view={view} expanded={expanded} onSelect={onSelect} onExpand={onExpand} />
      </div>
    </aside>
  );
}
