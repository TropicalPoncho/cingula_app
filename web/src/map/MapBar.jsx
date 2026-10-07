// Barra del mapa (D-03, D-04, D-17): selector de recorrido, casillas de capas y segmentado de modo de paths.
// `rec` = '' (todos) | 'none' (sin recorrido) | uuid. `modo` = 'corr' | 'circ'.
const MODOS = [['corr', 'Corredor'], ['circ', 'Círculos']];
const SW = {
  cobertura: { borderTopStyle: 'dashed', borderTopColor: 'var(--text-secondary)' },
  paths: { borderTopColor: 'var(--c-azure)' },
  portales: { borderTopColor: 'var(--c-mint)', borderTopWidth: 4 },
};
const LABELS = { cobertura: 'Cobertura', paths: 'Paths', portales: 'Portales' };

export default function MapBar({ recorridos, rec, hasSinRecorrido, capas, modo, onRec, onCapas, onModo, disabled }) {
  return (
    <div className="mapbar">
      <div className="mcard">
        <label className="chk" htmlFor="map-rec">Recorrido</label>
        <select id="map-rec" className="sel" value={rec} disabled={disabled} onChange={(e) => onRec(e.target.value)}>
          <option value="">Todos los recorridos</option>
          {recorridos.map((r) => <option key={r.uuid} value={r.uuid}>{r.name}</option>)}
          {hasSinRecorrido && <option value="none">Sin recorrido</option>}
        </select>
      </div>
      <div className="mcard" role="group" aria-label="Capas">
        <span className="mlbl" aria-hidden="true">Capas</span>
        {Object.keys(LABELS).map((k) => (
          <label key={k} className="chk">
            <input type="checkbox" checked={capas[k]} disabled={disabled} onChange={(e) => onCapas({ ...capas, [k]: e.target.checked })} />
            <span className="sw" style={SW[k]} aria-hidden="true" />
            {LABELS[k]}
          </label>
        ))}
      </div>
      <div className="mcard" role="group" aria-label="Paths">
        <span className="mlbl" aria-hidden="true">Paths</span>
        <div className="seg">
          {MODOS.map(([v, text]) => (
            <button key={v} type="button" aria-pressed={modo === v} disabled={disabled} onClick={() => onModo(v)}>{text}</button>
          ))}
        </div>
      </div>
    </div>
  );
}
