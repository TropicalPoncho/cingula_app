import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { load, resetStore } from '../data/store.js';
import MapPage from '../pages/MapPage.jsx';
import { makeRows, makePages, ID, HTML_NAME } from '../test/fixtures.js';

// MapPage real + store real + fetch simulado: el menú con su estado de verdad (URL, panel y chip).
async function open(url) {
  const pages = makePages(makeRows(), 1000);
  vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, status: 200, text: async () => JSON.stringify(pages[0]) })));
  sessionStorage.setItem('cingula.key', 'K');
  await act(() => load());
  history.replaceState(null, '', url);
  render(<MapPage />);
}

const btn = () => screen.getByRole('button', { name: 'Capas y filtros' });
const menu = () => screen.queryByRole('dialog', { name: 'Capas y filtros' });
const aside = () => screen.queryByRole('complementary', { name: 'Detalle del elemento seleccionado' });
const chipX = () => screen.queryByRole('button', { name: 'Quitar filtro de recorrido' });

beforeEach(() => resetStore());
afterEach(() => {
  vi.unstubAllGlobals();
  history.replaceState(null, '', '/');
});

describe('MapBar: menú Capas y filtros (D-22)', () => {
  it('botón con aria-haspopup/aria-expanded; abre un diálogo no modal con los tres grupos', async () => {
    const user = userEvent.setup();
    await open('/');
    expect(btn()).toHaveAttribute('aria-haspopup', 'dialog');
    expect(btn()).toHaveAttribute('aria-expanded', 'false');
    expect(menu()).toBeNull();

    await user.click(btn());
    expect(btn()).toHaveAttribute('aria-expanded', 'true');
    expect(menu()).not.toHaveAttribute('aria-modal');
    const d = within(menu());
    expect(d.getByRole('combobox', { name: 'Recorrido' })).toHaveValue('');
    for (const n of ['Cobertura', 'Paths', 'Portales']) expect(d.getByRole('checkbox', { name: n })).toBeChecked();
    expect(d.getByRole('button', { name: 'Corredor' })).toHaveAttribute('aria-pressed', 'true');
    expect(d.getByRole('button', { name: 'Círculos' })).toHaveAttribute('aria-pressed', 'false');
  });

  it('Esc con el foco dentro de la tarjeta la cierra y enfoca el botón; un clic afuera también', async () => {
    const user = userEvent.setup();
    await open('/');
    await user.click(btn());
    screen.getByRole('checkbox', { name: 'Cobertura' }).focus();
    await user.keyboard('{Escape}');
    expect(menu()).toBeNull();
    expect(btn()).toHaveFocus();

    await user.click(btn());
    expect(menu()).not.toBeNull();
    await user.click(document.body);
    expect(menu()).toBeNull();
  });

  it('con el panel abierto, Esc cierra SÓLO la tarjeta: el panel sigue', async () => {
    const user = userEvent.setup();
    await open(`/?sel=obra:${ID.obA}`);
    expect(aside()).not.toBeNull();
    await user.click(btn());
    await user.keyboard('{Escape}');
    expect(menu()).toBeNull();
    expect(aside()).not.toBeNull();
    expect(location.search).toContain('sel=obra');

    await user.keyboard('{Escape}'); // ya sin tarjeta, el Esc vuelve a ser del panel
    expect(aside()).toBeNull();
  });

  it('elegir un recorrido filtra, abre su panel y muestra el chip; × lo quita, cierra el panel y enfoca el botón', async () => {
    const user = userEvent.setup();
    await open('/');
    expect(chipX()).toBeNull();
    await user.click(btn());
    await user.selectOptions(within(menu()).getByRole('combobox', { name: 'Recorrido' }), ID.rec1);
    expect(location.search).toContain(`rec=${ID.rec1}`);
    expect(aside()).not.toBeNull();
    expect(screen.getByText('Recorrido Norte', { selector: '.mchip-t' })).toBeInTheDocument();

    await user.click(chipX());
    expect(location.search).toBe('');
    expect(aside()).toBeNull();
    expect(chipX()).toBeNull();
    expect(btn()).toHaveFocus();
  });

  it('?rec=none muestra el chip "Sin recorrido"; el × lo quita sin tocar el panel de otra cosa', async () => {
    const user = userEvent.setup();
    await open(`/?rec=none&sel=obra:${ID.obC}`);
    expect(screen.getByText('Sin recorrido', { selector: '.mchip-t' })).toBeInTheDocument();
    await user.click(chipX());
    expect(location.search).not.toContain('rec=');
    expect(aside()).not.toBeNull();
  });

  it('?rec desconocido o con HTML no muestra chip ni elementos img (T-12-41)', async () => {
    await open(`/?rec=${encodeURIComponent(HTML_NAME)}`);
    expect(chipX()).toBeNull();
    expect(document.querySelector('img[src="x"]')).toBeNull(); // los img de Leaflet son los tiles, no éste
  });
});
