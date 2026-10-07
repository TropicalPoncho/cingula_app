import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { load, resetStore } from '../data/store.js';
import { makeRows, makePages, ID, SENSITIVE } from '../test/fixtures.js';
import Artistas from './Artistas.jsx';

const ok = (body) => ({ ok: true, status: 200, text: async () => JSON.stringify(body) });

async function open({ url = '/artistas', uuid, rows = makeRows() } = {}) {
  const pages = makePages(rows, 1000);
  vi.stubGlobal('fetch', vi.fn(async () => ok(pages[0])));
  sessionStorage.setItem('cingula.key', 'K');
  await act(() => load());
  history.replaceState(null, '', url);
  return render(<Artistas uuid={uuid} />);
}

const detail = () => screen.getByRole('region', { name: 'Detalle' });

beforeEach(() => resetStore());
afterEach(() => {
  resetStore();
  vi.unstubAllGlobals();
  history.replaceState(null, '', '/');
});

describe('Artistas', () => {
  it('lista con conteo y `{n} obra(s)`; sin uuid abre el primero', async () => {
    await open();
    expect(screen.getByText('2 artistas')).toBeInTheDocument();
    const rows = within(screen.getByRole('list', { name: 'Listado de artistas' })).getAllByRole('listitem');
    expect(rows.map((r) => r.querySelector('.t').textContent)).toEqual(['Ana Lúcar', 'Bruno Mayo']);
    expect(within(rows[0]).getByText('1 obra')).toBeInTheDocument(); // el obra_artistas borrado no cuenta
    expect(within(rows[1]).getByText('2 obras')).toBeInTheDocument(); // la obra borrada no cuenta
    expect(within(detail()).getByRole('heading', { level: 2 })).toHaveTextContent('Ana Lúcar');
  });

  it('detalle con bio: ARTISTA, título, sub fijo, Nombre / Obras / Bio y el usuario nunca aparece', async () => {
    await open({ url: `/artistas/${ID.arA}`, uuid: ID.arA });
    const d = detail();
    expect(within(d).getByText('ARTISTA')).toBeInTheDocument();
    expect(within(d).getByRole('heading', { level: 2 })).toHaveClass('dtitle');
    expect(within(d).getByText('Los créditos de cada recorrido se calculan con los artistas de sus obras.')).toBeInTheDocument();
    for (const k of ['Nombre', 'Obras', 'Bio']) expect(within(d).getByText(k)).toBeInTheDocument();
    expect(within(d).getByText('Bio de prueba.')).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent('user-secreto');
    for (const k of SENSITIVE) expect(document.body).not.toHaveTextContent(k);
  });

  it('un artista sin bio no muestra la fila Bio', async () => {
    await open({ url: `/artistas/${ID.arB}`, uuid: ID.arB });
    expect(within(detail()).queryByText('Bio')).toBeNull();
    expect(within(detail()).getByText('Nombre')).toBeInTheDocument();
  });

  it('APARECE EN lista sólo obras vivas, con recorrido y visibilidad, enlazadas a /obras/:uuid', async () => {
    await open({ url: `/artistas/${ID.arB}`, uuid: ID.arB });
    const section = within(detail()).getByText('APARECE EN').closest('section');
    const links = within(section).getAllByRole('link');
    expect(links).toHaveLength(2); // Obra Aurora y la obra B; la D (borrada) no
    expect(links.map((l) => l.getAttribute('href')).sort()).toEqual([`/obras/${ID.obA}`, `/obras/${ID.obB}`].sort());
    const aurora = links.find((l) => l.textContent.includes('Obra Aurora'));
    expect(aurora).toHaveTextContent('Recorrido Norte');
    expect(aurora).toHaveTextContent('Pública');
    expect(section).not.toHaveTextContent('Obra borrada');
  });

  it('una obra sin recorrido dice "Sin recorrido" en APARECE EN', async () => {
    const rows = makeRows();
    rows.push({ table: 'obra_artistas', change_seq: '999', payload: { ...rows.find((r) => r.table === 'obra_artistas').payload, uuid: 'oa-c', obra_uuid: ID.obC, artista_uuid: ID.arA } });
    await open({ url: `/artistas/${ID.arA}`, uuid: ID.arA, rows });
    expect(within(detail()).getByText('Sin recorrido')).toBeInTheDocument();
  });

  it('cargando: 3 filas esqueleto; vacío: copy fijo', async () => {
    vi.stubGlobal('fetch', vi.fn(() => new Promise(() => {})));
    sessionStorage.setItem('cingula.key', 'K');
    act(() => { load(); });
    const { container, unmount } = render(<Artistas />);
    expect(container.querySelectorAll('.ent.skel')).toHaveLength(3);
    unmount();
    resetStore();
    await open({ rows: makeRows().filter((r) => r.table !== 'artistas' && r.table !== 'obra_artistas') });
    expect(screen.getByText('Todavía no hay artistas en el servidor.')).toBeInTheDocument();
  });

  it('error de primera lectura: .perr con Reintentar lectura', async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn(async () => ({ ok: false, status: 500, text: async () => '{}' }));
    vi.stubGlobal('fetch', fetchMock);
    sessionStorage.setItem('cingula.key', 'K');
    await act(() => load());
    render(<Artistas />);
    expect(screen.getByRole('alert')).toHaveClass('perr');
    const calls = fetchMock.mock.calls.length;
    await user.click(screen.getByRole('button', { name: 'Reintentar lectura' }));
    expect(fetchMock.mock.calls.length).toBeGreaterThan(calls);
  });

  it('uuid inexistente: mensaje fijo y Volver al listado', async () => {
    await open({ url: '/artistas/no-existe', uuid: 'no-existe' });
    expect(screen.getByText('No encontramos este artista.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Volver al listado' })).toHaveAttribute('href', '/artistas');
  });
});
