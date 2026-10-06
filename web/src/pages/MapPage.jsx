import { useMemo, useState } from 'react';
import { useModel, useStore, load } from '../data/store.js';
import { plural } from '../app/format.js';
import { useQuery, setParams } from '../app/router.jsx';
import { buildView } from '../panel/buildView.js';
import SidePanel from '../panel/SidePanel.jsx';
import MapView from '../map/MapView.jsx';
import MapBar from '../map/MapBar.jsx';

// Velos de estado (E1) y leyenda de conteos de lo visible. Van sobre el mapa base, que siempre está.
function MapOverlay({ counts, total }) {
  const { lastPullAt, status, errors } = useStore();

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

  if (total === 0) {
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

// Home (D-07). `sel`, `x` y `rec` viajan en la URL por replaceState (D-05): el panel nunca crea historial.
// El panel va ANTES del área del mapa en el DOM (orden de Tab: header, panel, mapa).
export default function MapPage() {
  const { lastPullAt } = useStore();
  const model = useModel();
  const q = useQuery();
  const sel = q.get('sel');
  const expanded = q.get('x') === '1';
  const [capas, setCapas] = useState({ cobertura: true, paths: true, portales: true });
  const [fitTarget, setFitTarget] = useState(null);
  // Plegado = el `sel` que estaba abierto al plegar: elegir otro elemento lo despliega solo, sin efectos.
  const [fold, setFold] = useState(null);
  const collapsed = fold !== null && fold === sel;

  // Sin datos no hay vista: un deep link no puede parpadear "ya no existe" mientras se lee.
  const ready = lastPullAt != null;
  const view = useMemo(() => (ready ? buildView(model, sel, 'map') : null), [ready, model, sel]);

  // `rec` de la URL se compara contra el modelo (T-12-28): uno desconocido equivale a `Todos`.
  const rec = q.get('rec');
  const recorrido = rec && rec !== 'none' ? (model.byId.recorrido.get(rec) ?? null) : null;
  const recVal = rec === 'none' ? 'none' : recorrido ? rec : '';
  const obras = useMemo(
    () => (recVal === 'none' ? model.obras.filter((o) => !o.recorrido) : recorrido ? recorrido.obras : model.obras),
    [model, recVal, recorrido],
  );
  const counts = useMemo(() => ({
    obras: obras.length,
    paths: obras.reduce((n, o) => n + o.routes.length, 0),
    triggers: obras.reduce((n, o) => n + o.routes.reduce((m, p) => m + p.triggers.length, 0), 0),
    portales: obras.reduce((n, o) => n + o.portals.length, 0),
  }), [obras]);
  const hasSinRecorrido = model.obras.some((o) => !o.recorrido);

  // Selección desde el mapa: el elemento ya está a la vista, no se re-encuadra. Elegir algo despliega el panel plegado.
  const select = (s) => {
    setFold(null);
    setParams({ sel: s });
  };
  // Desde un enlace del panel el elemento puede quedar fuera de la parte visible: se encuadra [DEFAULT UI-SPEC].
  const selectFromPanel = (s) => {
    select(s);
    setFitTarget({ sel: s });
  };
  // 12-08 devuelve acá el foco al marcador del mapa que abrió el panel.
  const close = () => {
    setFold(null);
    setParams({ sel: null, x: null });
  };
  // D-04 + D-10 en una sola interacción: elegir un recorrido filtra y abre su panel; Todos / Sin recorrido
  // quitan el filtro y cierran el panel si era el de un recorrido.
  const onRec = (v) => {
    setFold(null);
    if (v && v !== 'none') {
      setParams({ rec: v, sel: `recorrido:${v}`, x: null });
      return;
    }
    const closing = sel?.startsWith('recorrido:');
    setParams({ rec: v || null, sel: closing ? null : sel, x: closing ? null : q.get('x') });
  };

  return (
    <div className="mapcols">
      <SidePanel
        view={view}
        expanded={expanded}
        collapsed={collapsed}
        onSelect={selectFromPanel}
        onExpand={(on) => setParams({ x: on ? 1 : null })}
        onCollapse={(on) => setFold(on ? sel : null)}
        onClose={close}
      />
      <div className="mapwrap">
        <MapView
          model={model} obras={obras} capas={capas} sel={sel}
          fitKey={ready ? `rec:${recVal}` : null} fitTarget={fitTarget} onSelect={select}
        />
        <MapBar
          recorridos={model.recorridos} rec={recVal} hasSinRecorrido={hasSinRecorrido}
          capas={capas} onRec={onRec} onCapas={setCapas} disabled={!ready}
        />
        <MapOverlay counts={counts} total={model.counts.obras} />
      </div>
    </div>
  );
}
