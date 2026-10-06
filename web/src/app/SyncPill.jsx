import { useEffect, useState } from 'react';
import { TriangleAlert, RefreshCw } from 'lucide-react';
import { useStore, refresh, retryNow } from '../data/store.js';
import { pillState } from './syncState.js';

const DOT = { mint: 'var(--c-mint)', ambar: 'var(--c-ambar)', ink: 'var(--ink-200)' };

// Estado de sync del header (WEB-07, D-13): la pill dice la verdad aunque el popover esté cerrado.
export default function SyncPill() {
  const snap = useStore();
  const [open, setOpen] = useState(false);
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000); // la hora relativa se recalcula cada 30 s
    return () => clearInterval(id);
  }, []);

  const v = pillState(snap, now);
  const onButton = snap.status === 'error' ? retryNow : refresh;

  return (
    <div className="syncwrap">
      <button type="button" className="pill" aria-haspopup="dialog" aria-expanded={open} onClick={() => setOpen(!open)}>
        <span className="dot" style={{ background: DOT[v.tone] }} />
        {v.alert && <TriangleAlert size={16} aria-hidden="true" />}
        <span>{v.text}</span>
        {v.cursorText && <span className="mono dim">{v.cursorText}</span>}
      </button>
      {open && (
        <div className="pop" role="dialog" aria-label="Detalle del estado de sync">
          <div className="lbl">Estado de sync</div>
          {v.rows.map((r) => (
            <div className="r" key={r.label}>
              <span className="lbl">{r.label}</span>
              <span className={r.mono ? 'mono' : undefined}>{r.value}</span>
            </div>
          ))}
          {v.errors.length > 0 && (
            <div className="perr" role="alert">
              <span className="lbl">Errores</span>
              {v.errors.map((e, i) => <span className="mono" key={i}>{e}</span>)}
            </div>
          )}
          <div className="popfoot">
            <span className="dim">{v.note}</span>
            <button type="button" className="btn" disabled={v.button.disabled} onClick={onButton}>
              <RefreshCw size={16} aria-hidden="true" /> {v.button.label}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
