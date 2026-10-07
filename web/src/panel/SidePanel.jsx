import { useEffect } from 'react';
import { ChevronLeft, ChevronRight, Maximize2, Minimize2, X } from 'lucide-react';
import { A } from '../app/router.jsx';
import EntityDetail from './EntityDetail.jsx';
import './panel.css';

export function Crumbs({ crumbs, onSelect }) {
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

const announce = (view) =>
  view && !view.stale ? `Seleccionado: ${view.typeLabel[0]}${view.typeLabel.slice(1).toLowerCase()} ${view.title}` : '';

// Panel único (D-06): el chrome no conoce los tipos; el contenido lo decide buildView. El estado de
// ancho (`expanded`, en la URL) y de plegado (`collapsed`) lo posee quien lo monta (MapPage); el
// panel sólo avisa. Un único <aside> para todos los estados: el ancho transiciona sin remontar.
export default function SidePanel({ view, expanded, collapsed, onExpand, onCollapse, onClose, onSelect }) {
  const open = !!view;
  const folded = open && !view.stale && !!collapsed;
  const wide = open && !view.stale && !!expanded;

  // Esc: expandido -> compacto; compacto -> cierra. Con el panel plegado no actúa; tampoco si el
  // foco está en un diálogo abierto (popover de sync) que ya lo usa para cerrarse.
  useEffect(() => {
    if (!open || folded) return undefined;
    const onKey = (e) => {
      if (e.key !== 'Escape' || e.defaultPrevented || e.target.closest?.('[role="dialog"], dialog[open]')) return;
      if (wide) onExpand(false);
      else onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, folded, wide, onExpand, onClose]);

  const Expand = wide ? Minimize2 : Maximize2;
  return (
    <>
      <div className="sr-only" aria-live="polite">{announce(view)}</div>
      {open && (
        <aside
          className={`panel${wide && !folded ? ' exp' : ''}${folded ? ' rail' : ''}`}
          aria-label="Detalle del elemento seleccionado"
        >
          {view.stale ? (
            <div className="pbody">
              <div className="perr" role="status">
                <span>Este elemento ya no existe en el servidor.</span>
                <button type="button" className="btn" onClick={onClose}>Cerrar aviso</button>
              </div>
            </div>
          ) : folded ? (
            <>
              <button type="button" className="ib" aria-label="Abrir panel" onClick={() => onCollapse(false)}>
                <ChevronRight size={20} aria-hidden="true" />
              </button>
              <span className="vt" title={`${view.typeLabel} · ${view.title}`}>{view.typeLabel} · {view.title}</span>
            </>
          ) : (
            <>
              <div className="phead">
                <Crumbs crumbs={view.crumbs} onSelect={onSelect} />
                <div className="ptools">
                  <button
                    type="button"
                    className="ib"
                    aria-label={wide ? 'Volver al panel angosto' : 'Expandir a pantalla completa'}
                    onClick={() => onExpand(!wide)}
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
                <EntityDetail view={view} expanded={wide} onSelect={onSelect} onExpand={onExpand} />
              </div>
            </>
          )}
        </aside>
      )}
    </>
  );
}
