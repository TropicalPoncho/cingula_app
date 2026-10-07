import { useModel, useStore } from '../data/store.js';
import { plural } from '../app/format.js';
import { A } from '../app/router.jsx';
import { BackToList, ListGate, NotFound, Vis } from './parts.jsx';
import '../panel/panel.css'; // .facts / .fact / .row / .plist / .dtitle: el detalle comparte el vocabulario del panel

// Todo texto del servidor (nombre, bio) se renderiza como texto (T-12-33). El usuario vinculado al artista
// no existe en el modelo (lista blanca de 12-02): esta página no tiene dónde mostrarlo (T-12-31).
function Detail({ a }) {
  const facts = [['Nombre', a.name], ['Obras', String(a.obras.length)], ...(a.bio ? [['Bio', a.bio]] : [])];
  return (
    <>
      <span className="lbl">ARTISTA</span>
      <h2 className="dtitle" title={a.name}>{a.name}</h2>
      <p className="sub">Los créditos de cada recorrido se calculan con los artistas de sus obras.</p>
      <dl className="facts">
        {facts.map(([k, v]) => (
          <div className="fact" key={k}>
            <dt className="lbl">{k}</dt>
            <dd><span className="fv">{v}</span></dd>
          </div>
        ))}
      </dl>
      {a.obras.length > 0 && (
        <section>
          <h3 className="lbl sect">APARECE EN</h3>
          <ul className="plist">
            {a.obras.map((o) => (
              <li key={o.uuid}>
                <A className="row" href={`/obras/${encodeURIComponent(o.uuid)}`} title={o.name}>
                  <span className="rt">
                    <span className="t">{o.name}</span>
                    <span className="u">{o.recorrido?.name ?? 'Sin recorrido'}</span>
                  </span>
                  <Vis value={o.visibility} />
                </A>
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  );
}

// D-09 / WEB-03: listado de artistas y, por cada uno, las obras vivas en las que figura.
export default function Artistas({ uuid }) {
  const model = useModel();
  const ready = useStore().lastPullAt != null;
  const current = uuid ? model.byId.artista.get(uuid) : model.artistas[0]; // sin uuid: el primero [DEFAULT OI-09]

  return (
    <div className="page">
      <div className="toolbar">
        <h1>Artistas</h1>
        {ready && <span className="dim">{plural(model.artistas.length, 'artista', 'artistas')}</span>}
      </div>
      <div className={`split${uuid ? ' has-sel' : ''}`}>
        <div className="listpane">
          <ListGate total={model.artistas.length} emptyText="Todavía no hay artistas en el servidor.">
            <div role="list" aria-label="Listado de artistas">
              {model.artistas.map((a) => {
                const sub = plural(a.obras.length, 'obra', 'obras');
                const on = current?.uuid === a.uuid;
                return (
                  <div role="listitem" key={a.uuid}>
                    <A className={`ent${on ? ' on' : ''}`} href={`/artistas/${encodeURIComponent(a.uuid)}`} title={`${a.name} · ${sub}`} aria-current={on ? 'true' : undefined}>
                      <span className="et"><span className="t">{a.name}</span><span className="u">{sub}</span></span>
                    </A>
                  </div>
                );
              })}
            </div>
          </ListGate>
        </div>
        <section className="detpane" aria-label="Detalle">
          {ready && uuid && !current && <NotFound text="No encontramos este artista." href="/artistas" />}
          {current && (
            <>
              {uuid && <BackToList href="/artistas" />}
              <Detail a={current} />
            </>
          )}
        </section>
      </div>
    </div>
  );
}
