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
