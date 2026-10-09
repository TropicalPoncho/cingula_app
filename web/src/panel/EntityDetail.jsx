import { ArrowLeft, Maximize2 } from 'lucide-react';
import { A } from '../app/router.jsx';
import AudioCard from './AudioCard.jsx';
import CoverageStrip from './CoverageStrip.jsx';
import PortalTable from './PortalTable.jsx';

const COMPACT_ROWS = 4;

// Contenido genérico de una vista de `buildView`: sirve a los 5 tipos y a la página Obras (D-18).
// Todo texto del servidor se renderiza como texto (T-12-22): nada de HTML crudo en `panel/`.
function FactValue({ fact, onSelect }) {
  if (!fact.links) return fact.value;
  return fact.links.map((l, i) => (
    <span key={i}>
      {i > 0 && ' · '}
      {l.href ? (
        <A className="lnk" href={l.href}>{l.label}</A>
      ) : (
        <button type="button" className="lnk" onClick={() => onSelect(l.sel)}>{l.label}</button>
      )}
    </span>
  ));
}

function Facts({ facts, onSelect }) {
  return (
    <dl className="facts">
      {facts.map((f) => (
        <div className="fact" key={f.label}>
          <dt className="lbl">{f.label}</dt>
          <dd className={f.mono ? 'mono' : undefined} title={f.title}>
            {f.dot && <span className="dot" style={{ background: f.dot }} />}
            <span className="fv"><FactValue fact={f} onSelect={onSelect} /></span>
          </dd>
        </div>
      ))}
    </dl>
  );
}

function Row({ r, onSelect }) {
  return (
    <li>
      <button type="button" className="row" title={`${r.label} · ${r.sub}`} onClick={() => onSelect(r.sel)}>
        <span className="rt">
          <span className="t">{r.label}</span>
          <span className="u">{r.sub}</span>
        </span>
      </button>
    </li>
  );
}

// Vecinos en el path (alternativa no espacial al mapa): Anterior / Siguiente con la distancia en m.
function Neighbors({ neighbors, onSelect }) {
  if (!neighbors) return null;
  return (
    <section>
      <h3 className="lbl sect">Vecinos en el path</h3>
      <ul className="plist">
        {[neighbors.prev, neighbors.next].filter(Boolean).map((r) => (
          <Row key={r.sel} r={r} onSelect={onSelect} />
        ))}
      </ul>
    </section>
  );
}

function Lists({ lists, limit, onSelect, onExpand }) {
  return lists.map((l) => {
    const shown = limit ? l.rows.slice(0, limit) : l.rows;
    const more = l.rows.length - shown.length;
    return (
      <section key={l.title}>
        <h3 className="lbl sect">{l.title}</h3>
        <ul className="plist">
          {shown.map((r) => (
            <Row key={r.sel} r={r} onSelect={onSelect} />
          ))}
        </ul>
        {more > 0 && (
          <button type="button" className="lnk more" onClick={() => onExpand(true)}>+{more} más</button>
        )}
      </section>
    );
  });
}

export default function EntityDetail({ view, expanded, onSelect, onExpand }) {
  // La tabla reemplaza a la lista del mismo título en el expandido (UI-SPEC: lista sólo en compacto).
  const lists = view.table ? view.lists.filter((l) => l.title !== view.table.title) : view.lists;
  const note = view.note && <p className="dim note">{view.note}</p>;
  return (
    <>
      <div className="trow">
        {view.back && (
          <button
            type="button" className="ib" aria-label={`Volver a ${view.back.label}`} title={`Volver a ${view.back.label}`}
            onClick={() => onSelect(view.back.sel)}
          >
            <ArrowLeft size={20} aria-hidden="true" />
          </button>
        )}
        <span className="lbl">{view.typeLabel}</span>
      </div>
      <h2 className={expanded ? 'dtitle' : 'ptitle'} title={view.title}>{view.title}</h2>
      <p className="sub">{view.subtitle}</p>
      {expanded ? (
        <div className="dgrid">
          <div>
            <Facts facts={view.facts} onSelect={onSelect} />
            {view.description && <p className="desc">{view.description}</p>}
            {view.type === 'portal' && <AudioCard audio={view.audio} />}
          </div>
          <div>
            {view.type === 'path' && <AudioCard audio={view.audio} />}
            <CoverageStrip strip={view.strip} />
            {view.type === 'path' && !view.strip && <p className="dim note">0 triggers</p>}
            {note}
            <Lists lists={lists} onSelect={onSelect} onExpand={onExpand} />
            <Neighbors neighbors={view.neighbors} onSelect={onSelect} />
            <PortalTable table={view.table} onSelect={onSelect} />
          </div>
        </div>
      ) : (
        <>
          <Facts facts={view.facts} onSelect={onSelect} />
          {note}
          <Lists lists={view.lists} limit={COMPACT_ROWS} onSelect={onSelect} onExpand={onExpand} />
          <Neighbors neighbors={view.neighbors} onSelect={onSelect} />
          <button type="button" className="btn btn-p full" onClick={() => onExpand(true)}>
            <Maximize2 size={16} aria-hidden="true" /> Ver detalle completo
          </button>
        </>
      )}
    </>
  );
}
