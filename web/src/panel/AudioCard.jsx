// Tarjeta de audio de 3 estados (WEB-06 por D-11, UI-SPEC "AudioCard"). Sólo metadata: la clave de
// storage y el checksum no existen en el modelo (T-12-23) y acá no se reproduce nada (R7, Fase 13).
export default function AudioCard({ audio }) {
  if (!audio) return null;
  const { label, state, title, description, kind, duration, emptyText } = audio;
  if (state === 'none') {
    return (
      <section className="card">
        <span className="lbl">{label}</span>
        <p className="dim cardnone">{emptyText}</p>
      </section>
    );
  }
  return (
    <section className="card">
      <span className="lbl">{label}</span>
      <h4 className="cardt" title={title}>{title}</h4>
      {description && <p className="cardd">{description}</p>}
      <p className="cardm mono">
        {kind}
        {duration && ` · ${duration}`}
      </p>
      {state === 'nofile' ? (
        <div className="empty">
          <div>
            <strong className="emptyt">Sin archivo todavía</strong>
            <p className="emptyd">{emptyText}</p>
          </div>
        </div>
      ) : (
        <>
          <p className="cardfile">
            <span className="dot" style={{ background: 'var(--c-mint)' }} /> Archivo en el servidor
          </p>
          {/* Espacio reservado para el reproductor de la Fase 13 (STOR-04): sin controles ni barras decorativas. */}
          <div className="player-slot" aria-hidden="true" />
        </>
      )}
    </section>
  );
}
