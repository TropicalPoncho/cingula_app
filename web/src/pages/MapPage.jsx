import { useMemo, useState } from 'react';
import { useModel, useStore, load } from '../data/store.js';
import { plural } from '../app/format.js';
import { useQuery, setParams } from '../app/router.jsx';
import { buildView } from '../panel/buildView.js';
import SidePanel from '../panel/SidePanel.jsx';

// Contenido del área del mapa. El lienzo Leaflet lo agrega 12-07 alrededor de esta leyenda y de
// estos estados (E1).
function MapArea({ counts }) {
  const { status, lastPullAt, errors } = useStore();

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

// Home (D-07). `sel` y `x` viajan en la URL por replaceState (D-05): el panel nunca crea historial.
// El panel va ANTES del área del mapa en el DOM (orden de Tab: header, panel, mapa).
export default function MapPage() {
  const { lastPullAt } = useStore();
  const model = useModel();
  const q = useQuery();
  const sel = q.get('sel');
  const expanded = q.get('x') === '1';
  // Plegado = el `sel` que estaba abierto al plegar: elegir otro elemento lo despliega solo, sin efectos.
  const [fold, setFold] = useState(null);
  const collapsed = fold !== null && fold === sel;

  // Sin datos no hay vista: un deep link no puede parpadear "ya no existe" mientras se lee.
  const ready = lastPullAt != null;
  const view = useMemo(() => (ready ? buildView(model, sel, 'map') : null), [ready, model, sel]);

  // Único punto de selección (panel y, desde 12-07, mapa): elegir algo despliega el panel plegado.
  const select = (s) => {
    setFold(null);
    setParams({ sel: s });
  };
  // 12-08 devuelve acá el foco al marcador del mapa que abrió el panel.
  const close = () => {
    setFold(null);
    setParams({ sel: null, x: null });
  };

  return (
    <div className="mapcols">
      <SidePanel
        view={view}
        expanded={expanded}
        collapsed={collapsed}
        onSelect={select}
        onExpand={(on) => setParams({ x: on ? 1 : null })}
        onCollapse={(on) => setFold(on ? sel : null)}
        onClose={close}
      />
      <div className="mapwrap">
        <MapArea counts={model.counts} />
      </div>
    </div>
  );
}
