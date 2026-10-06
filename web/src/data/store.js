// Estado de datos y de sync de la pestaña. Sin librería de estado: useSyncExternalStore.
import { useMemo, useSyncExternalStore } from 'react';
import { pullAll, HttpError } from './pull.js';
import { applyRows, buildModel, emptyTables } from './model.js';
import { getKey, clearKey } from '../app/session.js';
import { navigate } from '../app/router.jsx';
import { RETRY_MS, MAX_RETRIES } from '../app/syncState.js';

const initial = () => ({
  status: 'idle', // idle | loading | ready | error
  tables: emptyTables(),
  cursor: null, // string tal cual (R12)
  lastPullAt: null, // momento del último pull completo OK
  read: 0,
  discarded: 0,
  page: 0,
  errors: [],
  online: navigator.onLine,
  retry: null, // { attempt: 1..3, nextAt } mientras hay un reintento automático agendado
});
let state = initial();
let gen = 0; // un pull en vuelo cuyo `gen` quedó viejo (salir de la web) no escribe nada
let timer = null;
let autoTry = 0; // reintentos automáticos ya consumidos en esta racha de fallos
const subs = new Set();
const set = (patch) => {
  state = { ...state, ...patch };
  subs.forEach((f) => f());
};
const cancelRetry = () => {
  clearTimeout(timer);
  timer = null;
};
addEventListener('online', () => set({ online: true }));
addEventListener('offline', () => set({ online: false }));

export const useStore = () =>
  useSyncExternalStore((f) => (subs.add(f), () => subs.delete(f)), () => state);

// Memo por identidad de `tables`: el modelo se calcula una vez por pull.
export function useModel() {
  const { tables } = useStore();
  return useMemo(() => buildModel(tables), [tables]);
}

// Salir de la web / clave vencida: ningún dato del servidor sobrevive a la sesión.
export function resetStore() {
  gen++;
  cancelRetry();
  autoTry = 0;
  state = initial();
  subs.forEach((f) => f());
}

// Todo-o-nada: se acumula en un buffer y el store se reemplaza recién con hasMore=false;
// un pull roto nunca pisa los datos previos ni deja una vista a medias.
// Completa (cursor 0, reemplaza) o incremental (desde el cursor guardado, sobre una copia).
async function pull(incremental) {
  if (state.status === 'loading') return;
  const mine = gen;
  const inc = incremental && state.cursor != null;
  cancelRetry();
  set({ status: 'loading', read: 0, page: 0, retry: null });
  try {
    const { rows, cursor } = await pullAll({
      key: getKey(),
      cursor: inc ? state.cursor : '0',
      onPage: ({ page, rows: n }) => mine === gen && set({ page, read: n }),
    });
    if (mine !== gen) return;
    const { tables, read, discarded } = applyRows(inc ? state.tables : emptyTables(), rows);
    // El cursor nunca retrocede (BigInt: bigint de Postgres, R12).
    const keep = inc && BigInt(cursor) < BigInt(state.cursor);
    autoTry = 0;
    set({
      status: 'ready', tables: inc && !rows.length ? state.tables : tables, cursor: keep ? state.cursor : cursor,
      read, discarded, lastPullAt: Date.now(), errors: [],
    });
  } catch (e) {
    if (mine !== gen) return;
    if (e instanceof HttpError && e.status === 401) {
      clearKey();
      resetStore();
      navigate('/acceso?motivo=401', { replace: true });
      return;
    }
    // Sin headers ni clave: sólo posición del pull, código y el `error` del JSON (T-12-17).
    const err = {
      at: Date.now(),
      cursor: e.cursor ?? null,
      page: e.page ?? state.page,
      status: e instanceof HttpError ? e.status : null,
      text: e instanceof HttpError ? jsonError(e.body) : String(e.message ?? e).slice(0, 200),
      retry: autoTry || undefined, // `(reintento {i} de 3)`; la lectura inicial y la manual no lo llevan
    };
    // Hasta MAX_RETRIES reintentos automáticos, uno cada RETRY_MS; después queda en error (T-12-18).
    const retry = autoTry < MAX_RETRIES ? { attempt: autoTry + 1, nextAt: Date.now() + RETRY_MS } : null;
    if (retry) {
      timer = setTimeout(() => {
        autoTry++;
        pull(true);
      }, RETRY_MS);
    }
    set({ status: 'error', errors: [...state.errors, err].slice(-10), retry });
  }
}

function jsonError(body) {
  try {
    const m = JSON.parse(body)?.error;
    return typeof m === 'string' ? m.slice(0, 200) : '';
  } catch {
    return '';
  }
}

// Las tres entradas son del usuario (o de la primera carga): reinician la racha de reintentos.
export const load = () => ((autoTry = 0), pull(false)); // primera carga
export const refresh = () => ((autoTry = 0), pull(true)); // `Actualizar datos`
export const retryNow = refresh; // con datos: incremental; sin datos (cursor null): `pull` cae a completa
