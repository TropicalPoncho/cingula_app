// Filas sintéticas generadas desde TABLE_SPEC (OI-03: nada copiado del prototipo ni de datos reales).
// Las usan Vitest y Playwright (por eso sólo importa el spec del backend: corre en Node y en jsdom).
import { TABLE_SPEC } from '../../api/_lib/spec.js';

const LAT0 = -42.08;
const LON0 = -71.62;
const M_PER_DEG = 111195;
const lonAt = (eastM) => LON0 + eastM / (M_PER_DEG * Math.cos((LAT0 * Math.PI) / 180));
const T = 1_700_000_000; // epoch en segundos, como el servidor
const DEL = T + 100;

// Ids legibles (el orden por uuid desempata `position`, por eso los triggers van con ceros a la izquierda).
export const ID = {
  rec1: 'rec-1', rec2: 'rec-2',
  arA: 'art-1', arB: 'art-2',
  obA: 'obra-A', obB: 'obra-B', obC: 'obra-C', obD: 'obra-D',
  pathA: 'path-A', portalA: 'path-A-portal', pathB: 'path-B', pathC: 'path-C', pathD: 'path-D',
  auFinal: 'aud-final', auNoFile: 'aud-nofile', auRec: 'aud-rec',
  auMissing: 'aud-no-existe',
  trgDeleted: 'trg-B-deleted', trgOrphan: 'trg-D-0', trgPortal: 'trg-A-portal',
  trA: (i) => `trg-A-${String(i).padStart(2, '0')}`,
  trB: (i) => `trg-B-${i}`,
};

export const LONG_NAME = 'Obra con un nombre larguísimo para probar el desborde'.padEnd(60, '.');
export const HTML_NAME = '<img src=x onerror=alert(1)>';
export const SENSITIVE = ['share_token', 'owner_id', 'user_id', 'checksum', 'storage_key'];

let seq;
const row = (table, over) => {
  const payload = Object.fromEntries(Object.keys(TABLE_SPEC[table].columns).map((c) => [c, null]));
  Object.assign(payload, { logical_version: 1, updated_at: T }, over);
  return { table, change_seq: String(seq++), payload };
};

export function makeRows() {
  seq = 101;
  const R = [];
  const add = (table, over) => R.push(row(table, over));

  add('recorridos', { uuid: ID.rec1, name: 'Recorrido Norte', description: 'Un recorrido de prueba.' });
  add('recorridos', { uuid: ID.rec2, name: 'Recorrido Sur' });

  add('artistas', { uuid: ID.arA, name: 'Ana Lúcar', bio: 'Bio de prueba.', user_id: 'user-secreto' });
  add('artistas', { uuid: ID.arB, name: 'Bruno Mayo' });

  add('audios', {
    uuid: ID.auFinal, kind: 'final', title: 'Audio final', description: 'Con archivo.', duration_seconds: 75,
    storage_key: 'obras/secreto/final.mp3', checksum: 'sha-secreto',
  });
  add('audios', { uuid: ID.auNoFile, kind: 'final', title: 'Audio sin archivo', duration_seconds: 30 });
  add('audios', { uuid: ID.auRec, kind: 'grabacion', title: 'Grabación', duration_seconds: 12 });

  const cover = { cover_lat: LAT0, cover_lon: LON0, cover_min_lat: LAT0 - 0.001, cover_max_lat: LAT0 + 0.001, cover_min_lon: LON0 - 0.001, cover_max_lon: LON0 + 0.004 };
  add('obras', { uuid: ID.obA, name: 'Obra Aurora', recorrido_uuid: ID.rec1, visibility: 'public', owner_id: 'dueno-secreto', share_token: 'token-secreto', ...cover });
  add('obras', { uuid: ID.obB, name: LONG_NAME, recorrido_uuid: ID.rec1, visibility: 'draft', ...cover });
  add('obras', { uuid: ID.obC, name: HTML_NAME, visibility: 'private' }); // sin recorrido y sin cobertura
  add('obras', { uuid: ID.obD, name: 'Obra borrada', recorrido_uuid: ID.rec1, visibility: 'public', deleted_at: DEL });

  add('obra_artistas', { uuid: 'oa-1', obra_uuid: ID.obA, artista_uuid: ID.arA });
  add('obra_artistas', { uuid: 'oa-2', obra_uuid: ID.obA, artista_uuid: ID.arB });
  add('obra_artistas', { uuid: 'oa-3', obra_uuid: ID.obB, artista_uuid: ID.arB });
  add('obra_artistas', { uuid: 'oa-4', obra_uuid: ID.obB, artista_uuid: ID.arA, deleted_at: DEL }); // borrado: sin crédito
  add('obra_artistas', { uuid: 'oa-5', obra_uuid: ID.obD, artista_uuid: ID.arB }); // huérfano: obra borrada

  add('paths', { uuid: ID.pathA, obra_uuid: ID.obA, kind: 'route', name: 'Ruta A', audio_uuid: ID.auFinal, tolerance_meters: 5 });
  add('paths', { uuid: ID.portalA, obra_uuid: ID.obA, kind: 'portal', name: 'Portal A', audio_uuid: ID.auFinal });
  add('paths', { uuid: ID.pathB, obra_uuid: ID.obB, kind: 'route', name: 'Ruta B', audio_uuid: ID.auNoFile, grabacion_uuid: ID.auRec });
  add('paths', { uuid: ID.pathC, obra_uuid: ID.obC, kind: 'route', name: 'Ruta C', audio_uuid: ID.auMissing }); // audio inexistente
  add('paths', { uuid: ID.pathD, obra_uuid: ID.obD, kind: 'route', name: 'Ruta D' }); // huérfano: obra borrada

  // Ruta A: 32 triggers a 10 m (radio 12), salto de 40 m entre el 15 y el 16 (hueco) y dos `position`
  // repetidas (el 11 comparte la del 10, el 21 la del 20). Se emiten al revés: el orden sale del modelo.
  const trA = [];
  for (let i = 0; i < 32; i++) {
    const east = i <= 15 ? i * 10 : 150 + 40 + (i - 16) * 10;
    const position = i === 11 ? 10 : i === 21 ? 20 : i;
    trA.push({ uuid: ID.trA(i), path_uuid: ID.pathA, position, name: `t${i}`, latitude: LAT0, longitude: lonAt(east), radius_meters: 12, offset_ms: i * 1200 });
  }
  trA.reverse().forEach((t) => add('triggers', t));
  add('triggers', { uuid: ID.trgPortal, path_uuid: ID.portalA, position: 0, name: 'p', description: 'Descripción del portal.', latitude: LAT0 + 0.0005, longitude: LON0, radius_meters: 15, offset_ms: 0 });
  for (let i = 0; i < 3; i++) {
    add('triggers', { uuid: ID.trB(i), path_uuid: ID.pathB, position: i, name: `b${i}`, latitude: LAT0 - 0.0005, longitude: lonAt(i * 10), radius_meters: 12, offset_ms: i * 1000 });
  }
  add('triggers', { uuid: ID.trgDeleted, path_uuid: ID.pathB, position: 3, name: 'b3', latitude: LAT0 - 0.0005, longitude: lonAt(30), radius_meters: 12, offset_ms: 3000, deleted_at: DEL });
  add('triggers', { uuid: ID.trgOrphan, path_uuid: ID.pathD, position: 0, name: 'd0', latitude: LAT0, longitude: LON0, radius_meters: 12, offset_ms: 0 }); // huérfano

  return R;
}

// Una página como la del servidor: filas con change_seq > cursor (BigInt, nunca Number).
export function pageAfter(rows, cursor, limit) {
  const rest = rows.filter((r) => BigInt(r.change_seq) > BigInt(cursor));
  const changes = rest.slice(0, limit);
  return { changes, nextCursor: changes.length ? changes.at(-1).change_seq : cursor, hasMore: rest.length > limit };
}

export function makePages(rows, limit) {
  const pages = [];
  let cursor = '0';
  do {
    const p = pageAfter(rows, cursor, limit);
    pages.push(p);
    cursor = p.nextCursor;
    if (!p.hasMore) break;
  } while (true);
  return pages;
}
