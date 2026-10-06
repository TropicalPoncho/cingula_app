import { useModel, useStore, load } from '../data/store.js';
import { plural } from '../app/format.js';

// Home (D-07). El lienzo Leaflet lo agrega 12-07 alrededor de esta leyenda y de estos estados (E1).
export default function MapPage() {
  const { status, lastPullAt, errors } = useStore();
  const { counts } = useModel();

  if (lastPullAt == null) {
    if (status === 'error') {
      const code = errors.at(-1)?.status ?? 'sin respuesta';
      return (
        <div className="mapstate">
          <div className="perr" role="alert">
            <span className="lbl">No se pudo leer el servidor.</span>
            <span>GET /sync/pull → {code}. Revisá tu conexión y reintentá.</span>
            <button type="button" className="btn" onClick={load}>Reintentar lectura</button>
          </div>
        </div>
      );
    }
    return <div className="mapstate"><p>Leyendo el servidor…</p></div>;
  }

  if (counts.obras === 0) {
    return (
      <div className="mapstate">
        <p>Todavía no hay obras en el servidor.</p>
        <p className="dim">Cuando el celular sincronice la primera obra, va a aparecer acá.</p>
      </div>
    );
  }

  return (
    <div className="legend">
      {plural(counts.obras, 'obra', 'obras')} · {plural(counts.paths, 'path', 'paths')} ·{' '}
      {plural(counts.triggers, 'trigger', 'triggers')} · {plural(counts.portales, 'portal', 'portales')}
    </div>
  );
}
