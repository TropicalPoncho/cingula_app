// Barra del mapa (D-03, D-04): selector de recorrido y casillas de capas. Controles nativos.
// `rec` = '' (todos) | 'none' (sin recorrido) | uuid. 12-08 agrega el segmentado Corredor/Círculos acá.
const SW = {
  cobertura: { borderTopStyle: 'dashed', borderTopColor: 'var(--text-secondary)' },
  paths: { borderTopColor: 'var(--c-azure)' },
  portales: { borderTopColor: 'var(--c-mint)', borderTopWidth: 4 },
};
const LABELS = { cobertura: 'Cobertura', paths: 'Paths', portales: 'Portales' };

export default function MapBar({ recorridos, rec, hasSinRecorrido, capas, onRec, onCapas, disabled }) {
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
    </div>
  );
}
