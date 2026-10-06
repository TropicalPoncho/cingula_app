// Tabla "Portales de la obra" (R1/D-18). `#` es el índice en el orden por nombre, no una posición
// persistida. Los nombres se renderizan como texto (T-12-24).
const COLS = ['#', 'Nombre', 'Radio', 'Offset', 'Posición'];

export default function PortalTable({ table, onSelect }) {
  if (!table) return null;
  return (
    <section>
      <h3 className="lbl sect">{table.title}</h3>
      <div className="tblwrap">
        <table className="tbl" aria-label={table.title}>
          <thead>
            <tr>
              {COLS.map((c) => (
                <th key={c} scope="col">{c}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {table.rows.map((r) => (
              <tr key={r.sel}>
                <td className="mono">{r.n}</td>
                <td>
                  <button type="button" className="tblbtn" title={r.name} onClick={() => onSelect(r.sel)}>{r.name}</button>
                </td>
                <td>{r.radius}</td>
                <td className="mono">{r.offset}</td>
                <td className="mono">{r.pos}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
