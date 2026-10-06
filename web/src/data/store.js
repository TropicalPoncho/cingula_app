// Estado de datos y de sync de la pestaña. Sin librería de estado: useSyncExternalStore.
import { useMemo, useSyncExternalStore } from 'react';
import { pullAll, HttpError } from './pull.js';
import { applyRows, buildModel, emptyTables } from './model.js';
import { getKey, clearKey } from '../app/session.js';
import { navigate } from '../app/router.jsx';

const initial = () => ({
  status: 'idle', // idle | loading | ready | error
  tables: emptyTables(),
  cursor: null, // string tal cual (R12)
  lastPullAt: null,
  read: 0,
  discarded: 0,
  page: 0,
  errors: [],
});
let state = initial();
let gen = 0; // un pull en vuelo cuyo `gen` quedó viejo (salir de la web) no escribe nada
const subs = new Set();
const set = (patch) => {
  state = { ...state, ...patch };
  subs.forEach((f) => f());
};

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
  set({ status: 'loading', read: 0, page: 0 });
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
    };
    set({ status: 'error', errors: [...state.errors, err].slice(-10) });
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

export const load = () => pull(false); // primera carga
export const refresh = () => pull(true); // `Actualizar datos`
export const retryNow = refresh; // con datos: incremental; sin datos (cursor null): `pull` cae a completa
