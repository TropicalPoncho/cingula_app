import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { load, resetStore } from '../data/store.js';
import { makeRows, makePages, ID, HTML_NAME } from '../test/fixtures.js';
import Obras from './Obras.jsx';

const ok = (body) => ({ ok: true, status: 200, text: async () => JSON.stringify(body) });

// Store real + fetch simulado, como SidePanel.spec: la página se prueba con su estado de verdad.
async function open({ url = '/obras', uuid, rows = makeRows() } = {}) {
  const pages = makePages(rows, 1000);
  vi.stubGlobal('fetch', vi.fn(async () => ok(pages[0])));
  sessionStorage.setItem('cingula.key', 'K');
  await act(() => load());
  history.replaceState(null, '', url);
  return render(<Obras uuid={uuid} />);
}

const list = () => screen.getByRole('list', { name: 'Listado de obras' });
const rowNames = () => within(list()).getAllByRole('listitem').map((li) => li.querySelector('.t').textContent);

beforeEach(() => resetStore());
afterEach(() => {
  resetStore(); // cancela el reintento automático que deja un pull fallido
  vi.unstubAllGlobals();
  history.replaceState(null, '', '/');
});

describe('Obras', () => {
  it('lista las 3 obras vivas con conteo, sin la borrada; la primera queda abierta por defecto', async () => {
    await open();
    expect(screen.getByText('3 obras')).toBeInTheDocument();
    expect(rowNames()).toHaveLength(3);
    expect(rowNames()).not.toContain('Obra borrada');
    // OI-09: sin uuid -> primera obra filtrada. Es la C (sin cobertura): ese estado se ve en el detalle.
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent(HTML_NAME);
    expect(screen.getByText('Sin cobertura todavía')).toBeInTheDocument();
  });

  it('filtra por recorrido, por Sin recorrido y por visibilidad', async () => {
    const user = userEvent.setup();
    await open();
    await user.selectOptions(screen.getByLabelText('Recorrido'), 'Recorrido Norte');
    expect(screen.getByText('2 obras')).toBeInTheDocument();
    expect(rowNames()).not.toContain(HTML_NAME);
    await user.selectOptions(screen.getByLabelText('Recorrido'), 'Sin recorrido');
    expect(screen.getByText('1 obra')).toBeInTheDocument();
    expect(rowNames()).toEqual([HTML_NAME]);
    await user.selectOptions(screen.getByLabelText('Recorrido'), 'Todos');
    await user.selectOptions(screen.getByLabelText('Visibilidad'), 'Borrador');
    expect(screen.getByText('1 obra')).toBeInTheDocument();
    expect(rowNames()[0]).toMatch(/^Obra con un nombre/);
    expect(location.search).toBe('?vis=draft');
  });

  it('sin coincidencias: mensaje fijo; un filtro desconocido en la URL equivale a Todos', async () => {
    const user = userEvent.setup();
    await open({ url: '/obras?rec=inventado&vis=zzz' });
    expect(screen.getByText('3 obras')).toBeInTheDocument();
    await user.selectOptions(screen.getByLabelText('Recorrido'), 'Recorrido Sur'); // existe, sin obras
    expect(screen.getByText('Ninguna obra coincide con los filtros.')).toBeInTheDocument();
    expect(screen.getByText('0 obras')).toBeInTheDocument();
  });

  it('/obras/:uuid muestra el detalle expandido de esa obra con el breadcrumb Obras / Obra', async () => {
    await open({ url: `/obras/${ID.obA}`, uuid: ID.obA });
    const crumbs = screen.getByRole('navigation', { name: 'Ruta' });
    expect(within(crumbs).getByRole('link', { name: 'Obras' })).toHaveAttribute('href', '/obras');
    expect(within(crumbs).getByText('Obra Aurora')).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('Obra Aurora');
    expect(screen.getByRole('heading', { level: 2 })).toHaveClass('dtitle'); // expandido, como el panel
    expect(screen.getByRole('link', { name: 'Ana Lúcar' })).toHaveAttribute('href', `/artistas/${ID.arA}`);
    expect(list().querySelector('[aria-current="true"]')).toHaveAttribute('href', `/obras/${ID.obA}`); // fila activa
  });

  it('una obra sin recorrido dice "Sin recorrido" en la fila y el detalle', async () => {
    await open({ url: `/obras/${ID.obC}`, uuid: ID.obC });
    const row = within(list()).getAllByRole('listitem').find((li) => li.textContent.includes(HTML_NAME));
    expect(within(row).getByText('Sin recorrido')).toBeInTheDocument();
    expect(screen.getAllByText('Sin recorrido').length).toBeGreaterThan(1);
    expect(screen.getByText('Sin cobertura todavía')).toBeInTheDocument();
  });

  it('el texto del servidor se muestra como texto (nada de HTML crudo)', async () => {
    await open();
    expect(document.querySelector('img[src="x"]')).toBeNull();
  });
});

// Estados de página (E4): la página nunca queda en blanco ante carga, vacío, error o uuid inexistente.
describe('Obras: estados', () => {
  it('cargando: 3 filas esqueleto y detalle vacío', async () => {
    vi.stubGlobal('fetch', vi.fn(() => new Promise(() => {}))); // el pull nunca termina
    sessionStorage.setItem('cingula.key', 'K');
    act(() => { load(); });
    history.replaceState(null, '', '/obras');
    const { container } = render(<Obras />);
    expect(container.querySelectorAll('.ent.skel')).toHaveLength(3);
    expect(screen.queryByRole('list')).toBeNull();
    expect(screen.getByRole('region', { name: 'Detalle' })).toBeEmptyDOMElement();
  });

  it('vacío: copy fijo (y no el de filtros sin coincidencias)', async () => {
    await open({ rows: [] });
    expect(screen.getByText('Todavía no hay obras en el servidor.')).toBeInTheDocument();
    expect(screen.queryByText('Ninguna obra coincide con los filtros.')).toBeNull();
  });

  it('error de primera lectura: .perr con el código y Reintentar lectura que vuelve a pedir', async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn(async () => ({ ok: false, status: 503, text: async () => '{"error":"boom"}' }));
    vi.stubGlobal('fetch', fetchMock);
    sessionStorage.setItem('cingula.key', 'K');
    await act(() => load());
    history.replaceState(null, '', '/obras');
    render(<Obras />);
    const alert = screen.getByRole('alert');
    expect(alert).toHaveClass('perr');
    expect(alert).toHaveTextContent('No se pudo leer el servidor.');
    expect(alert).toHaveTextContent('GET /sync/pull → 503');
    const calls = fetchMock.mock.calls.length;
    await user.click(screen.getByRole('button', { name: 'Reintentar lectura' }));
    expect(fetchMock.mock.calls.length).toBeGreaterThan(calls);
  });

  it('uuid inexistente: mensaje fijo y Volver al listado; el texto de la URL no se renderiza', async () => {
    await open({ url: '/obras/<b>zzz</b>', uuid: '<b>zzz</b>' });
    expect(screen.getByText('No encontramos esta obra.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Volver al listado' })).toHaveAttribute('href', '/obras');
    expect(document.body).not.toHaveTextContent('zzz');
  });
});

// D-12 + mini-mapa (Task 3).
describe('Obras: selección anidada y mini-mapa', () => {
  const crumbText = () => screen.getByRole('navigation', { name: 'Ruta' }).textContent;

  it('?sel=path:<uuid> muestra el path con Obras / Obra / Path y Volver a {Obra} sin salir de la página', async () => {
    const user = userEvent.setup();
    await open({ url: `/obras/${ID.obA}?sel=path:${ID.pathA}`, uuid: ID.obA });
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('Ruta A');
    expect(crumbText()).toBe('Obras/Obra Aurora/Ruta A');
    await user.click(screen.getByRole('button', { name: /Volver a Obra Aurora/ }));
    expect(location.pathname).toBe(`/obras/${ID.obA}`);
    expect(location.search).toBe('');
  });

  it('un portal de la lista abre su detalle por setParams (replaceState, sin historial nuevo)', async () => {
    const user = userEvent.setup();
    await open({ url: `/obras/${ID.obA}`, uuid: ID.obA });
    const before = history.length;
    await user.click(screen.getByRole('button', { name: /Portal A/ }));
    expect(decodeURIComponent(location.search)).toBe(`?sel=portal:${ID.portalA}`);
    expect(history.length).toBe(before);
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('Portal A');
  });

  it('un sel de otra obra, inexistente o de otro tipo se ignora y queda el detalle de la obra', async () => {
    for (const bad of [`path:${ID.pathB}`, 'path:no-existe', `recorrido:${ID.rec1}`, `obra:${ID.obB}`, 'x']) {
      resetStore();
      const { unmount } = await open({ url: `/obras/${ID.obA}?sel=${bad}`, uuid: ID.obA });
      expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('Obra Aurora');
      unmount();
    }
  });

  it('el link al recorrido abre el mapa: los recorridos no tienen página (D-10)', async () => {
    const user = userEvent.setup();
    await open({ url: `/obras/${ID.obA}`, uuid: ID.obA });
    await user.click(screen.getAllByRole('button', { name: 'Recorrido Norte' })[0]);
    expect(location.pathname).toBe('/');
    expect(new URLSearchParams(location.search).get('sel')).toBe(`recorrido:${ID.rec1}`);
  });

  it('mini-mapa: role=img "Mapa de {obra}" sólo para obras con cobertura', async () => {
    const first = await open({ url: `/obras/${ID.obA}`, uuid: ID.obA });
    expect(screen.getByRole('img', { name: 'Mapa de Obra Aurora' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '© OpenStreetMap contributors' })).toBeInTheDocument();
    first.unmount();
    resetStore();
    const { unmount } = await open({ url: `/obras/${ID.obC}`, uuid: ID.obC });
    expect(screen.queryByRole('img', { name: /^Mapa de/ })).toBeNull(); // C no tiene cobertura: no hay nada que dibujar
    unmount();
  });
});
