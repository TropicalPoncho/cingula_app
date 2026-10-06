// Matriz de estados de la pill de sync (UI-SPEC "Estado de sync", WEB-07, D-13). Pura: sin DOM ni reloj.
import { rel } from './format.js';

const p2 = (n) => String(n).padStart(2, '0');
const hms = (t) => { const d = new Date(t); return `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}`; };
const fecha = (t) => { const d = new Date(t); return `${p2(d.getDate())}.${p2(d.getMonth() + 1)}.${p2(d.getFullYear() % 100)}`; };

function lastPullRow(at, now) {
  const hoy = new Date(at).toDateString() === new Date(now).toDateString();
  return hoy ? `hoy ${hms(at)} · hace ${rel(now - at)}` : `${fecha(at)} ${hms(at)}`;
}

// `GET /sync/pull?cursor={c} → {código} {texto} (página {k})`, sin headers ni clave (T-12-17).
const errorLine = (e) =>
  [`${hms(e.at)} `, `GET /sync/pull?cursor=${e.cursor ?? '0'} →`, e.status ?? 'sin respuesta', e.text, `(página ${e.page})`]
    .filter(Boolean)
    .join(' ');

export function pillState(s, now) {
  const cursorText = s.cursor != null ? `cursor ${s.cursor}` : '';
  const base = { tone: 'ink', alert: false, cursorText, errors: [], note: '' };
  const act = { label: 'Actualizar datos', disabled: false };

  if (s.status === 'error') {
    const data = s.lastPullAt != null;
    return {
      ...base, tone: 'ambar', alert: true,
      text: data ? `Error de pull · datos de hace ${rel(now - s.lastPullAt)}` : 'Error de pull · sin datos',
      rows: [
        ...(data ? [{ label: 'Último pull OK', value: lastPullRow(s.lastPullAt, now) }] : []),
        { label: 'Cursor', value: `${s.cursor ?? '0'} (no avanzó)`, mono: true },
        { label: 'Estado', value: 'Pull incompleto: se muestran los datos del último pull completo.' },
      ],
      errors: s.errors.map(errorLine),
      button: { label: 'Reintentar lectura', disabled: false },
    };
  }
  if (s.status === 'ready') {
    return {
      ...base, tone: 'mint', text: `Sync al día · pull hace ${rel(now - s.lastPullAt)}`,
      rows: [
        { label: 'Último pull', value: lastPullRow(s.lastPullAt, now) },
        { label: 'Cursor', value: s.cursor, mono: true },
        { label: 'Filas leídas', value: `${s.read} · ${s.discarded} con deleted_at descartadas` },
        { label: 'Estado', value: 'Sin errores' },
      ],
      button: act,
    };
  }
  return {
    ...base, text: `Leyendo… ${s.read} filas`,
    rows: [{ label: 'Estado', value: `Pull en curso · página ${s.page + 1}` }],
    button: { ...act, disabled: true },
  };
}
