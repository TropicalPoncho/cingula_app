import { useEffect, useState } from 'react';
import { TriangleAlert } from 'lucide-react';
import { useStore } from '../data/store.js';
import { rel } from './format.js';

// Estado de sync del header (WEB-07, D-13). El popover y la matriz completa (desactualizado, sin
// conexión, reintentos) los agrega 12-04.
export default function SyncPill() {
  const { status, cursor, read, lastPullAt } = useStore();
  const [, tick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => tick((n) => n + 1), 30_000); // la hora relativa se recalcula cada 30 s
    return () => clearInterval(id);
  }, []);

  const ago = lastPullAt == null ? '' : rel(Date.now() - lastPullAt);
  let dot = 'var(--ink-200)';
  let text = `Leyendo… ${read} filas`;
  if (status === 'ready') {
    dot = 'var(--c-mint)';
    text = `Sync al día · pull hace ${ago}`;
  } else if (status === 'error') {
    dot = 'var(--c-ambar)';
    text = lastPullAt == null ? 'Error de pull · sin datos' : `Error de pull · datos de hace ${ago}`;
  }

  return (
    <button type="button" className="pill">
      <span className="dot" style={{ background: dot }} />
      {status === 'error' && <TriangleAlert size={16} aria-hidden="true" />}
      <span>{text}</span>
      {cursor != null && <span className="mono dim">cursor {cursor}</span>}
    </button>
  );
}
