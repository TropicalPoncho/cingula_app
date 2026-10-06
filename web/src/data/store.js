// Estado de datos y de sync de la pestaña. Sin librería de estado: useSyncExternalStore.
import { useSyncExternalStore } from 'react';
import { pullAll, HttpError } from './pull.js';
import { applyRows, emptyTables } from './model.js';
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

// Salir de la web / clave vencida: ningún dato del servidor sobrevive a la sesión.
export function resetStore() {
  gen++;
  state = initial();
  subs.forEach((f) => f());
}

// Todo-o-nada: se acumula en un buffer y el store se reemplaza recién con hasMore=false;
// un pull roto nunca pisa los datos previos ni deja una vista a medias.
export async function load() {
  if (state.status === 'loading') return;
  const mine = gen;
  set({ status: 'loading', read: 0, page: 0 });
  try {
    const { rows, cursor } = await pullAll({
      key: getKey(),
      cursor: '0',
      onPage: ({ page, rows: n }) => mine === gen && set({ page, read: n }),
    });
    if (mine !== gen) return;
    const { tables, read, discarded } = applyRows(emptyTables(), rows);
    set({ status: 'ready', tables, cursor, read, discarded, lastPullAt: Date.now() });
  } catch (e) {
    if (mine !== gen) return;
    if (e instanceof HttpError && e.status === 401) {
      clearKey();
      resetStore();
      navigate('/acceso?motivo=401', { replace: true });
      return;
    }
    // Sin headers ni clave: sólo posición del pull y código.
    const err = {
      at: Date.now(),
      cursor: e.cursor ?? null,
      page: e.page ?? state.page,
      status: e instanceof HttpError ? e.status : null,
      text: e instanceof HttpError ? e.body.slice(0, 200) : String(e.message ?? e),
    };
    set({ status: 'error', errors: [...state.errors, err] });
  }
}
