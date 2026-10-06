import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { load, resetStore } from '../data/store.js';
import { setParams } from '../app/router.jsx';
import MapPage from '../pages/MapPage.jsx';
import { makeRows, makePages, ID, HTML_NAME } from '../test/fixtures.js';
import SidePanel from './SidePanel.jsx';

// MapPage real + store real + fetch simulado: prueba el panel con su estado de verdad (URL y plegado).
async function open(url) {
  const pages = makePages(makeRows(), 1000);
  vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, status: 200, text: async () => JSON.stringify(pages[0]) })));
  sessionStorage.setItem('cingula.key', 'K');
  await act(() => load());
  history.replaceState(null, '', url);
  render(<MapPage />);
}

const aside = () => screen.queryByRole('complementary', { name: 'Detalle del elemento seleccionado' });
const live = () => document.querySelector('[aria-live="polite"]');

beforeEach(() => resetStore());
afterEach(() => {
  vi.unstubAllGlobals();
  history.replaceState(null, '', '/');
});

describe('SidePanel con MapPage', () => {
  it('plegar -> riel de 48 px con "Abrir panel" y texto vertical; reabrir vuelve al estado previo (expandido)', async () => {
    const user = userEvent.setup();
    await open(`/?sel=obra:${ID.obA}&x=1`);
    expect(aside()).toHaveClass('exp');
    await user.click(screen.getByRole('button', { name: 'Plegar panel' }));
    expect(aside()).toHaveClass('rail');
    expect(aside()).not.toHaveClass('exp');
    expect(within(aside()).getByText('OBRA · Obra Aurora')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Abrir panel' }));
    expect(aside()).not.toHaveClass('rail');
    expect(aside()).toHaveClass('exp'); // conserva el flag (vive en la URL)
    expect(location.search).toContain('x=1');
  });

  it('elegir otro elemento con el panel plegado lo despliega', async () => {
    const user = userEvent.setup();
    await open(`/?sel=obra:${ID.obA}`);
    await user.click(screen.getByRole('button', { name: 'Plegar panel' }));
    expect(aside()).toHaveClass('rail');
    act(() => setParams({ sel: `obra:${ID.obB}` }));
    expect(aside()).not.toHaveClass('rail');
    expect(screen.getByRole('heading', { name: /Obra con un nombre/ })).toBeInTheDocument();
  });

  it('cerrar (X) limpia sel y x y el panel no se renderiza', async () => {
    const user = userEvent.setup();
    await open(`/?sel=obra:${ID.obA}&x=1`);
    await user.click(screen.getByRole('button', { name: 'Cerrar panel' }));
    expect(aside()).toBeNull();
    expect(location.search).toBe('');
  });

  it('Esc: expandido -> compacto; compacto -> cierra', async () => {
    const user = userEvent.setup();
    await open(`/?sel=obra:${ID.obA}&x=1`);
    await user.keyboard('{Escape}');
    expect(aside()).not.toHaveClass('exp');
    expect(decodeURIComponent(location.search)).toBe(`?sel=obra:${ID.obA}`);
    await user.keyboard('{Escape}');
    expect(aside()).toBeNull();
    expect(location.search).toBe('');
  });

  it('Esc con el foco en un diálogo abierto no toca el panel', async () => {
    const user = userEvent.setup();
    await open(`/?sel=obra:${ID.obA}`);
    render(<div role="dialog" aria-label="Sync"><button type="button">dentro</button></div>);
    await user.click(screen.getByRole('button', { name: 'dentro' }));
    await user.keyboard('{Escape}');
    expect(aside()).not.toBeNull();
  });

  it('sel inexistente o mal formado: aviso y "Cerrar aviso" limpia sel; el texto de la URL no se interpola', async () => {
    const user = userEvent.setup();
    await open('/?sel=obra:%3Cimg%20src=x%3E');
    expect(within(aside()).getByText('Este elemento ya no existe en el servidor.')).toBeInTheDocument();
    expect(aside().innerHTML).not.toContain('img');
    await user.click(screen.getByRole('button', { name: 'Cerrar aviso' }));
    expect(aside()).toBeNull();
    expect(location.search).toBe('');
  });

  it('un deep link no muestra "ya no existe" mientras se lee el servidor', async () => {
    history.replaceState(null, '', `/?sel=obra:${ID.obA}`);
    render(<MapPage />); // store vacío (idle): sin datos
    expect(aside()).toBeNull();
  });

  it('aria-live dice "Seleccionado: {Tipo} {título}" y cambia con sel', async () => {
    await open(`/?sel=obra:${ID.obA}`);
    expect(live()).toHaveTextContent('Seleccionado: Obra Obra Aurora');
    act(() => setParams({ sel: `obra:${ID.obC}` }));
    expect(live()).toHaveTextContent(`Seleccionado: Obra ${HTML_NAME}`);
  });

  it('el nombre con HTML se renderiza como texto, nunca como elemento (T-12-22)', async () => {
    await open(`/?sel=obra:${ID.obC}`);
    expect(screen.getByRole('heading', { name: HTML_NAME })).toBeInTheDocument();
    expect(aside().querySelector('img')).toBeNull();
  });

  it('accesibilidad: aside con nombre, botones con aria-label y breadcrumb "Ruta"', async () => {
    await open(`/?sel=obra:${ID.obA}`);
    for (const n of ['Expandir a pantalla completa', 'Plegar panel', 'Cerrar panel']) {
      expect(screen.getByRole('button', { name: n })).toBeInTheDocument();
    }
    expect(screen.getByRole('navigation', { name: 'Ruta' })).toBeInTheDocument();
  });
});

describe('listas del panel compacto', () => {
  const view = (n) => ({
    type: 'obra', typeLabel: 'OBRA', title: 'T', subtitle: 's', back: null, description: null, facts: [],
    crumbs: [{ label: 'T', sel: null }],
    lists: [{ title: 'Paths', rows: Array.from({ length: n }, (_, i) => ({ label: `P${i}`, sub: 'route', sel: `path:p${i}` })) }],
  });

  it('más de 4 filas: muestra 4 y "+N más", que expande el panel', async () => {
    const user = userEvent.setup();
    const onExpand = vi.fn();
    render(<SidePanel view={view(32)} onExpand={onExpand} onCollapse={() => {}} onClose={() => {}} onSelect={() => {}} />);
    expect(screen.getAllByRole('listitem')).toHaveLength(4);
    await user.click(screen.getByRole('button', { name: '+28 más' }));
    expect(onExpand).toHaveBeenCalledWith(true);
  });

  it('4 filas o menos: sin "+N más"; expandido muestra todas', () => {
    const { rerender } = render(<SidePanel view={view(4)} onExpand={() => {}} onCollapse={() => {}} onClose={() => {}} onSelect={() => {}} />);
    expect(screen.queryByText(/más$/)).toBeNull();
    rerender(<SidePanel view={view(9)} expanded onExpand={() => {}} onCollapse={() => {}} onClose={() => {}} onSelect={() => {}} />);
    expect(screen.getAllByRole('listitem')).toHaveLength(9);
  });

  it('listas vacías y descripción vacía se omiten (sin título de sección)', () => {
    const v = { ...view(0), lists: [] };
    render(<SidePanel view={v} onExpand={() => {}} onCollapse={() => {}} onClose={() => {}} onSelect={() => {}} />);
    expect(screen.queryByRole('heading', { level: 3 })).toBeNull();
    expect(document.querySelector('.desc')).toBeNull();
  });
});
