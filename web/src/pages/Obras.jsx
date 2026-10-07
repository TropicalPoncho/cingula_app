import { useMemo } from 'react';
import { useModel, useStore } from '../data/store.js';
import { plural } from '../app/format.js';
import { A, navigate, setParams, useQuery } from '../app/router.jsx';
import { buildView } from '../panel/buildView.js';
import { Crumbs } from '../panel/SidePanel.jsx';
import EntityDetail from '../panel/EntityDetail.jsx';
import { BackToList, ListGate, NotFound, Vis } from './parts.jsx';

const VIS_OPTIONS = [['', 'Todas'], ['public', 'Pública'], ['private', 'Privada'], ['draft', 'Borrador']];
const noop = () => {};

// Filtros de la URL comparados contra valores conocidos (T-12-32): uno desconocido equivale a "todos".
function useFilters(model) {
  const q = useQuery();
  const r = q.get('rec');
  const v = q.get('vis');
  return {
    rec: r === 'none' || model.byId.recorrido.has(r) ? r : '',
    vis: VIS_OPTIONS.some(([k]) => k && k === v) ? v : '',
  };
}

// Los filtros viajan con la obra abierta: se reconstruyen desde los valores ya validados.
const search = ({ rec, vis }) => {
  const u = new URLSearchParams();
  if (rec) u.set('rec', rec);
  if (vis) u.set('vis', vis);
  const s = u.toString();
  return s ? `?${s}` : '';
};

// D-08 / WEB-04: listado filtrable + el MISMO detalle expandido del panel del mapa (`pageObras`).
export default function Obras({ uuid }) {
  const model = useModel();
  const ready = useStore().lastPullAt != null; // sin datos no hay "no existe": un deep link no parpadea mientras se lee
  const filters = useFilters(model);
  const obras = useMemo(
    () =>
      model.obras.filter(
        (o) =>
          (filters.rec === 'none' ? !o.recorrido : !filters.rec || o.recorrido?.uuid === filters.rec) &&
          (!filters.vis || o.visibility === filters.vis),
      ),
    [model, filters.rec, filters.vis],
  );
  const hasSinRecorrido = model.obras.some((o) => !o.recorrido);
  const qs = search(filters);

  // Sin uuid en la URL: la primera obra filtrada [DEFAULT OI-09].
  const current = uuid ? model.byId.obra.get(uuid) : obras[0];
  const view = current ? buildView(model, `obra:${current.uuid}`, 'pageObras') : null;
  // Enlaces del detalle. Los recorridos viven en el panel del mapa (D-10): se abren allá.
  const onSelect = (s) => {
    const type = s.slice(0, s.indexOf(':'));
    const id = s.slice(s.indexOf(':') + 1);
    if (type === 'recorrido') navigate(`/?${new URLSearchParams({ rec: id, sel: s })}`);
    else if (type === 'obra') navigate(`/obras/${encodeURIComponent(id)}${qs}`);
    else setParams({ sel: s });
  };

  return (
    <div className="page">
      <div className="toolbar">
        <h1>Obras</h1>
        <div className="fld">
          <label className="lbl" htmlFor="f-rec">Recorrido</label>
          <select id="f-rec" className="sel" value={filters.rec} onChange={(e) => setParams({ rec: e.target.value || null })}>
            <option value="">Todos</option>
            {model.recorridos.map((r) => <option key={r.uuid} value={r.uuid}>{r.name}</option>)}
            {hasSinRecorrido && <option value="none">Sin recorrido</option>}
          </select>
        </div>
        <div className="fld">
          <label className="lbl" htmlFor="f-vis">Visibilidad</label>
          <select id="f-vis" className="sel" value={filters.vis} onChange={(e) => setParams({ vis: e.target.value || null })}>
            {VIS_OPTIONS.map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          </select>
        </div>
        {ready && <span className="dim">{plural(obras.length, 'obra', 'obras')}</span>}
      </div>
      <div className={`split${uuid ? ' has-sel' : ''}`}>
        <div className="listpane">
          <ListGate total={model.obras.length} emptyText="Todavía no hay obras en el servidor.">
            <div role="list" aria-label="Listado de obras">
              {obras.map((o) => {
                const sub = [o.recorrido?.name ?? 'Sin recorrido', o.artistas.map((a) => a.name).join(', ')].filter(Boolean).join(' · ');
                const on = current?.uuid === o.uuid;
                return (
                  <div role="listitem" key={o.uuid}>
                    <A className={`ent${on ? ' on' : ''}`} href={`/obras/${encodeURIComponent(o.uuid)}${qs}`} title={`${o.name} · ${sub}`} aria-current={on ? 'true' : undefined}>
                      <span className="et"><span className="t">{o.name}</span><span className="u">{sub}</span></span>
                      <Vis value={o.visibility} />
                    </A>
                  </div>
                );
              })}
            </div>
            {!obras.length && <p className="dim">Ninguna obra coincide con los filtros.</p>}
          </ListGate>
        </div>
        <section className="detpane" aria-label="Detalle">
          {ready && uuid && !current && <NotFound text="No encontramos esta obra." href={`/obras${qs}`} />}
          {view && (
            <>
              {uuid && <BackToList href={`/obras${qs}`} />}
              <Crumbs crumbs={view.crumbs} onSelect={onSelect} />
              <EntityDetail view={view} expanded onSelect={onSelect} onExpand={noop} />
            </>
          )}
        </section>
      </div>
    </div>
  );
}
