import { useId } from 'react';
import { Layers, X } from 'lucide-react';
import { usePopover } from '../app/usePopover.js';

// Filtros del mapa detrás de UN botón (D-22, supersede la barra fija de D-04): tarjeta no modal con recorrido,
// capas y modo de paths, y un chip con el filtro de recorrido activo (también `Sin recorrido`: esconde obras).
// `rec` = '' (todos) | 'none' (sin recorrido) | uuid YA VALIDADO contra el modelo por MapPage (T-12-28/T-12-41).
// `modo` = 'corr' | 'circ'.
const MODOS = [['corr', 'Corredor'], ['circ', 'Círculos']];
const SW = {
  cobertura: { borderTopStyle: 'dashed', borderTopColor: 'var(--text-secondary)' },
  paths: { borderTopColor: 'var(--c-azure)' },
  portales: { borderTopColor: 'var(--c-mint)', borderTopWidth: 4 },
};
const LABELS = { cobertura: 'Cobertura', paths: 'Paths', portales: 'Portales' };
const TITLE = 'Capas y filtros';

export default function MapBar({ recorridos, rec, hasSinRecorrido, capas, modo, onRec, onCapas, onModo, disabled }) {
  const { open, setOpen, wrap, button } = usePopover();
  const cardId = useId();
  // El nombre sale del modelo, nunca del texto de la URL.
  const chip = rec === 'none' ? 'Sin recorrido' : recorridos.find((r) => r.uuid === rec)?.name;

  return (
    <div className="mapbar" ref={wrap}>
      <div className="mfilt">
        <button
          type="button" className="mbtn" ref={button} title={TITLE} aria-label={TITLE}
          aria-haspopup="dialog" aria-expanded={open} aria-controls={cardId} onClick={() => setOpen(!open)}
        >
          <Layers size={20} aria-hidden="true" />
        </button>
        {chip && (
          <span className="mchip">
            <span className="mchip-t" title={chip}>{chip}</span>
            <button
              type="button" className="mchip-x" aria-label="Quitar filtro de recorrido"
              onClick={() => { onRec(''); button.current.focus(); }}
            >
              <X size={20} aria-hidden="true" />
            </button>
          </span>
        )}
      </div>
      {open && (
        <div id={cardId} className="mmenu" role="dialog" aria-label={TITLE}>
          <div className="mgrp">
            <label className="lbl" htmlFor="map-rec">Recorrido</label>
            <select id="map-rec" className="sel" value={rec} disabled={disabled} onChange={(e) => onRec(e.target.value)}>
              <option value="">Todos los recorridos</option>
              {recorridos.map((r) => <option key={r.uuid} value={r.uuid}>{r.name}</option>)}
              {hasSinRecorrido && <option value="none">Sin recorrido</option>}
            </select>
          </div>
          <div className="mgrp" role="group" aria-label="Capas">
            <span className="lbl" aria-hidden="true">Capas</span>
            {Object.keys(LABELS).map((k) => (
              <label key={k} className="chk">
                <input type="checkbox" checked={capas[k]} disabled={disabled} onChange={(e) => onCapas({ ...capas, [k]: e.target.checked })} />
                <span className="sw" style={SW[k]} aria-hidden="true" />
                {LABELS[k]}
              </label>
            ))}
          </div>
          <div className="mgrp" role="group" aria-label="Paths">
            <span className="lbl" aria-hidden="true">Paths</span>
            <div className="seg">
              {MODOS.map(([v, text]) => (
                <button key={v} type="button" aria-pressed={modo === v} disabled={disabled} onClick={() => onModo(v)}>{text}</button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
