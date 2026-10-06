import { useEffect, useRef, useState } from 'react';
import { TriangleAlert, RefreshCw } from 'lucide-react';
import { useStore, refresh, retryNow } from '../data/store.js';
import { pillState } from './syncState.js';

const DOT = { mint: 'var(--c-mint)', ambar: 'var(--c-ambar)', ink: 'var(--ink-200)' };

// Estado de sync del header (WEB-07, D-13): la pill dice la verdad aunque el popover esté cerrado.
export default function SyncPill() {
  const snap = useStore();
  const [open, setOpen] = useState(false);
  const [now, setNow] = useState(Date.now);
  const wrap = useRef(null);
  const pill = useRef(null);
  const seenError = useRef(null);

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000); // la hora relativa se recalcula cada 30 s
    return () => clearInterval(id);
  }, []);

  // Esc o clic afuera cierran el popover (no modal) y devuelven el foco a la pill.
  useEffect(() => {
    if (!open) return;
    const close = () => { setOpen(false); pill.current.focus(); };
    const onKey = (e) => e.key === 'Escape' && close();
    const onDown = (e) => !wrap.current.contains(e.target) && close();
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onDown);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('pointerdown', onDown);
    };
  }, [open]);

  const v = pillState(snap, now, snap.online);
  const lastError = snap.errors.at(-1)?.at ?? null;
  // role=alert sólo en el render en que aparece un error nuevo: un re-render no lo vuelve a anunciar.
  const fresh = lastError != null && lastError !== seenError.current;
  useEffect(() => { seenError.current = lastError; });

  const onButton = snap.status === 'error' ? retryNow : refresh;
  const label = [v.text, v.cursorText].join(' ').trim(); // < 900 px el texto se oculta: queda como nombre accesible

  return (
    <div className="syncwrap" ref={wrap}>
      <button type="button" className="pill" ref={pill} aria-label={label} aria-haspopup="dialog" aria-expanded={open} onClick={() => setOpen(!open)}>
        <span className="dot" style={{ background: DOT[v.tone] }} />
        {v.alert && <TriangleAlert size={16} aria-hidden="true" />}
        <span className="pill-t">{v.text}</span>
        {v.cursorText && <span className="pill-t mono dim">{v.cursorText}</span>}
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
            <div className="perr" role={fresh ? 'alert' : undefined}>
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
