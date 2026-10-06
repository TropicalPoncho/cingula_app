// Tira de cobertura (D-17): un cuadro por trigger en orden y un cuadro ámbar punteado por cada hueco.
// Los huecos vienen calculados del modelo (`view.strip`); acá sólo se dibujan.
export default function CoverageStrip({ strip }) {
  if (!strip) return null;
  return (
    <section>
      <h3 className="lbl sect">Cobertura del path</h3>
      <div className="strip" role="img" aria-label={strip.ariaLabel}>
        {strip.cells.map((c, i) => (
          <i key={i} className={c.gap ? 'sg gap' : 'sg'} title={c.gap ? `Hueco de ≈ ${c.meters} m` : undefined} />
        ))}
      </div>
      {strip.note && <p className="dim stripnote">{strip.note}</p>}
    </section>
  );
}
