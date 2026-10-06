// Matriz de estados de la pill de sync (UI-SPEC "Estado de sync", WEB-07, D-13). Pura: sin DOM ni reloj.
import { rel } from './format.js';

// [DEFAULT] de la UI-SPEC (OI-09), sin validar con el usuario.
export const STALE_MS = 15 * 60_000; // último pull OK más viejo que esto = Desactualizado
export const RETRY_MS = 30_000; // reintento automático cada 30 s...
export const MAX_RETRIES = 3; // ...hasta 3 veces

const p2 = (n) => String(n).padStart(2, '0');
const hms = (t) => { const d = new Date(t); return `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}`; };
const fecha = (t) => { const d = new Date(t); return `${p2(d.getDate())}.${p2(d.getMonth() + 1)}.${p2(d.getFullYear() % 100)}`; };

function lastPullRow(at, now) {
  const hoy = new Date(at).toDateString() === new Date(now).toDateString();
  return hoy ? `hoy ${hms(at)} · hace ${rel(now - at)}` : `${fecha(at)} ${hms(at)}`;
}

// `HH:MM:SS  GET /sync/pull?cursor={c} → {código} {texto} (página {k})` [+ `(reintento {i} de 3)`];
// sin headers ni clave (T-12-17).
const errorLine = (e) =>
  [`${hms(e.at)} `, `GET /sync/pull?cursor=${e.cursor ?? '0'} →`, e.status ?? 'sin respuesta', e.text, `(página ${e.page})`,
    e.retry && `(reintento ${e.retry} de ${MAX_RETRIES})`]
    .filter(Boolean)
    .join(' ');

// -> { tone: 'mint'|'ambar'|'ink', alert, text, cursorText, rows: [{ label, value, mono? }], errors, button, note }
export function pillState(s, now, online = true) {
  const cursorText = s.cursor != null ? `cursor ${s.cursor}` : '';
  const base = { tone: 'ink', alert: false, cursorText, errors: [], note: '' };
  const act = { label: 'Actualizar datos', disabled: false };
  const data = s.lastPullAt != null;
  const ago = data ? rel(now - s.lastPullAt) : '';
  const row = (label, value, mono) => ({ label, value, mono });

  if (s.status === 'error') {
    return {
      ...base, tone: 'ambar', alert: true,
      text: data ? `Error de pull · datos de hace ${ago}` : 'Error de pull · sin datos',
      rows: [
        ...(data ? [row('Último pull OK', lastPullRow(s.lastPullAt, now))] : []),
        row('Cursor', `${s.cursor ?? '0'} (no avanzó)`, true),
        // Sin datos la frase de la UI-SPEC sería falsa (no hay "último pull completo"): se dice la verdad.
        row('Estado', data ? 'Pull incompleto: se muestran los datos del último pull completo.' : 'Pull incompleto: todavía no hay datos para mostrar.'),
      ],
      errors: s.errors.map(errorLine),
      button: { label: 'Reintentar lectura', disabled: false },
      note: s.retry ? 'Próximo reintento automático en 30 s.' : 'Reintentá cuando tengas conexión.',
    };
  }

  if (s.status !== 'ready') {
    return {
      ...base, text: `Leyendo… ${s.read} filas`,
      rows: [row('Estado', `Pull en curso · página ${s.page + 1}`)],
      button: { ...act, disabled: true },
    };
  }

  const lastRows = [row('Último pull', lastPullRow(s.lastPullAt, now)), row('Cursor', s.cursor, true)];
  if (!online) {
    return {
      ...base, text: `Sin conexión · datos de hace ${ago}`,
      rows: [...lastRows, row('Estado', 'La web sólo funciona con conexión.')],
      button: { ...act, disabled: true },
    };
  }
  if (now - s.lastPullAt > STALE_MS) {
    return {
      ...base, tone: 'ambar', text: `Datos de hace ${ago}`,
      rows: [...lastRows, row('Estado', 'Hace más de 15 min que no se actualiza.')],
      button: act,
    };
  }
  return {
    ...base, tone: 'mint', text: `Sync al día · pull hace ${ago}`,
    rows: [
      ...lastRows,
      row('Filas leídas', `${s.read} · ${s.discarded} con deleted_at descartadas`),
      row('Estado', 'Sin errores'),
    ],
    button: act,
  };
}
